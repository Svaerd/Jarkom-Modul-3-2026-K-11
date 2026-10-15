#!/bin/bash
# shoko — DNS Slave BIND9 (Soal 11)
# Network 1 (DMZ), eth0 statis 10.69.1.3/24.
# Slave zona jujutsu.K11.com dari master utahime (10.69.1.2).
# Zona diambil otomatis (AXFR/IXFR) saat master kirim notify / serial naik.
# Container debinet: TANPA systemd -> named dijalankan langsung (nohup).

DOMAIN="jujutsu.K11.com"
IP="10.69.1.3"
MASTER_IP="10.69.1.2"
SLAVEFILE="/var/cache/bind/db.$DOMAIN"

# container-friendly: hapus policy-rc.d agar service bisa start
rm -f /usr/sbin/policy-rc.d

# resolusi sementara
echo 'nameserver 192.168.122.1' > /etc/resolv.conf

if ! command -v named >/dev/null 2>&1; then
	apt-get update
	DEBIAN_FRONTEND=noninteractive apt-get install -y bind9 bind9utils dnsutils
fi

# IP statis + route (idempotent)
ip link set eth0 up
ip addr replace $IP/24 dev eth0
ip route replace default via 10.69.1.1 2>/dev/null || true

# ---- named.conf.options ----
cat > /etc/bind/named.conf.options <<'EOF'
options {
	directory "/var/cache/bind";

	listen-on {
		127.0.0.1;
		10.69.1.3;
	};
	listen-on-v6 { none; };

	allow-query { any; };
	recursion yes;
	dnssec-validation no;

	auth-nxdomain no;
};
EOF

# ---- zona slave (file zona TIDAK dibuat manual; ditransfer dari master) ----
cat > /etc/bind/named.conf.local <<EOF
//
// Do NOT edit any of these unless you know what you are doing
//

zone "$DOMAIN" {
	type slave;
	file "$SLAVEFILE";
	masters { $MASTER_IP; };
	// terima notify hanya dari master
	allow-notify { $MASTER_IP; };
};
EOF

chown -R bind:bind /var/cache/bind /etc/bind 2>/dev/null || true

named-checkconf

# container tanpa systemd: matikan instance lama, jalankan named baru
pkill named 2>/dev/null || true
sleep 1
nohup /usr/sbin/named -f -c /etc/bind/named.conf -u bind >/var/log/named.log 2>&1 &
sleep 2

# resolver shoko = dirinya sendiri (AGENTS: DNS server pakai dirinya)
cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
search K11.com
EOF

if pgrep named >/dev/null; then
	echo "[shoko] DNS slave up untuk $DOMAIN (master $MASTER_IP)"
else
	echo "[shoko] GAGAL start named:"
	cat /var/log/named.log
	exit 1
fi

# paksa transfer awal dari master
rndc retransfer "$DOMAIN" 2>/dev/null || true
sleep 2

echo "--- file zona hasil transfer ---"
ls -l "$SLAVEFILE" 2>/dev/null || echo "  (belum ada - tunggu transfer dari master)"
echo "--- test lokal ---"
dig @127.0.0.1 "$DOMAIN" SOA +short
