#!/bin/bash
# utahime — DNS Master BIND9 (Soal 11)
# Network 1 (DMZ), eth0 statis 10.69.1.2/24.
# Zona jujutsu.K11.com: SOA, NS delegasi ns1(utahime .2) + ns2(shoko .3),
# allow-transfer hanya ke slave (10.69.1.3).
# Container debinet: TANPA systemd -> named dijalankan langsung (nohup).
#
# Pemakaian:
#   ./11-dns-master.sh            # setup, serial default = 1
#   ./11-dns-master.sh 2          # tulis zona dengan serial baru (memicu transfer ke slave)
#   ./11-dns-master.sh bump       # naikkan serial dari file zona saat ini lalu reload

DOMAIN="jujutsu.K11.com"
IP="10.69.1.2"
SLAVE_IP="10.69.1.3"
ZONEFILE="/etc/bind/zones/db.$DOMAIN"

# serial: arg angka, "bump", atau default 1
if [ "$1" = "bump" ] && [ -f "$ZONEFILE" ]; then
	SERIAL=$(sed -n 's/^[[:space:]]*\([0-9][0-9]*\).*; Serial.*/\1/p' "$ZONEFILE" | head -n1)
	[ -n "$SERIAL" ] || SERIAL=1
	SERIAL=$((SERIAL + 1))
else
	SERIAL="${1:-1}"
fi

# container-friendly: hapus policy-rc.d agar service bisa start
rm -f /usr/sbin/policy-rc.d

# resolusi sementara
echo 'nameserver 192.168.122.1' > /etc/resolv.conf

# Debian modern (trixie/bookworm) -> mirror utama sudah berisi bind9
if ! command -v named >/dev/null 2>&1; then
	apt-get update
	DEBIAN_FRONTEND=noninteractive apt-get install -y bind9 bind9utils dnsutils
fi

# IP statis + route (idempotent)
ip link set eth0 up
ip addr replace $IP/24 dev eth0
ip route replace default via 10.69.1.1 2>/dev/null || true

mkdir -p /etc/bind/zones

# ---- named.conf.options: juga jadi forwarder (dipakai Soal 12) ----
cat > /etc/bind/named.conf.options <<'EOF'
options {
	directory "/var/cache/bind";

	// forwarder ke gateway NAT (resolusi eksternal)
	forwarders {
		192.168.122.1;
	};

	listen-on {
		127.0.0.1;
		10.69.1.2;
	};
	listen-on-v6 { none; };

	allow-query { any; };
	recursion yes;
	dnssec-validation no;

	auth-nxdomain no;

	// delegasi zona dinyatakan di named.conf.local
};
EOF

# ---- zona master ----
cat > /etc/bind/named.conf.local <<EOF
//
// Do NOT edit any of these unless you know what you are doing
//

zone "$DOMAIN" {
	type master;
	file "$ZONEFILE";
	// hanya slave shoko yang boleh AXFR/IXFR
	allow-transfer { $SLAVE_IP; };
	notify yes;
	also-notify { $SLAVE_IP; };
};
EOF

# ---- file zona ----
cat > "$ZONEFILE" <<EOF
;
; BIND data file for $DOMAIN
; DNS Master: utahime (10.69.1.2) -> ns1
; DNS Slave : shoko   (10.69.1.3) -> ns2
;
\$TTL    604800
@       IN      SOA     ns1.$DOMAIN. admin.$DOMAIN. (
			$SERIAL   ; Serial
			604800    ; Refresh
			86400     ; Retry
			2419200   ; Expire
			604800 )  ; Negative Cache TTL
;
; Name servers (delegasi NS untuk kedua server)
@       IN      NS      ns1.$DOMAIN.
@       IN      NS      ns2.$DOMAIN.

; Glue A record kedua NS
ns1     IN      A       10.69.1.2
ns2     IN      A       10.69.1.3
EOF

chown -R bind:bind /etc/bind 2>/dev/null || true

named-checkconf
named-checkzone "$DOMAIN" "$ZONEFILE" || exit 1

# container tanpa systemd: matikan instance lama, jalankan named baru
pkill named 2>/dev/null || true
sleep 1
nohup /usr/sbin/named -f -c /etc/bind/named.conf -u bind >/var/log/named.log 2>&1 &
sleep 2

# resolver utahime = dirinya sendiri (DNS server pakai dirinya sendiri)
cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
search K11.com
EOF

if pgrep named >/dev/null; then
	echo "[utahime] DNS master up untuk $DOMAIN (serial $SERIAL)"
else
	echo "[utahime] GAGAL start named:"
	cat /var/log/named.log
	exit 1
fi

echo "--- test lokal ---"
dig @127.0.0.1 "$DOMAIN" SOA +short
dig @127.0.0.1 "$DOMAIN" NS +short
