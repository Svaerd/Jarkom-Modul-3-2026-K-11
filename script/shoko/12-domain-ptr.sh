#!/bin/bash
# shoko — DNS Slave BIND9 (Soal 12)
# Slave zona forward jujutsu.K11.com (Soal 11) + zona reverse PTR 1.69.10.in-addr.arpa.
# Kedua zona ditransfer otomatis dari master utahime (10.69.1.2).
# Container debinet: TANPA systemd -> named dijalankan langsung (nohup).

DOMAIN="jujutsu.K11.com"
IP="10.69.1.3"
MASTER_IP="10.69.1.2"
REVZONE="1.69.10.in-addr.arpa"

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

# ---- named.conf.options (slave juga meneruskan query eksternal) ----
cat > /etc/bind/named.conf.options <<'EOF'
options {
	directory "/var/cache/bind";

	forwarders {
		192.168.122.1;
	};

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

# ---- zona slave: forward + reverse (file zona TIDAK dibuat manual) ----
cat > /etc/bind/named.conf.local <<EOF
//
// Do NOT edit any of these unless you know what you are doing
//

zone "$DOMAIN" {
	type slave;
	file "/var/cache/bind/db.$DOMAIN";
	masters { $MASTER_IP; };
	allow-notify { $MASTER_IP; };
};

zone "$REVZONE" {
	type slave;
	file "/var/cache/bind/db.1.69.10";
	masters { $MASTER_IP; };
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

# resolver shoko = dirinya sendiri
cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
search K11.com
EOF

if pgrep named >/dev/null; then
	echo "[shoko] DNS slave (forward+PTR) up, master $MASTER_IP"
else
	echo "[shoko] GAGAL start named:"
	cat /var/log/named.log
	exit 1
fi

# paksa transfer awal kedua zona dari master
rndc retransfer "$DOMAIN" 2>/dev/null || true
rndc retransfer "$REVZONE" 2>/dev/null || true
sleep 3

echo "--- file zona hasil transfer ---"
ls -l "/var/cache/bind/db.$DOMAIN" 2>/dev/null || echo "  (zona forward belum ada)"
ls -l "/var/cache/bind/db.1.69.10" 2>/dev/null || echo "  (zona PTR belum ada)"
echo "--- test lokal ---"
echo -n "CNAME www      : "; dig @127.0.0.1 "www.$DOMAIN" CNAME +short
echo -n "PTR 10.69.1.4  : "; dig @127.0.0.1 -x 10.69.1.4 +short
