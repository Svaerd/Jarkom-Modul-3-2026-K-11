#!/bin/bash
# utahime — DNS Master BIND9 (Soal 12)
# Melanjutkan zona Soal 11 (SOA/NS/ns1/ns2 tetap ditulis ulang), lalu menambah:
#   - A record   : jujutsu.K11.com -> gojo (10.69.1.4)
#   - CNAME      : www -> jujutsu.K11.com
#   - zona PTR   : 1.69.10.in-addr.arpa, 10.69.1.4 -> jujutsu.K11.com
#   - forwarder  : 192.168.122.1 (gateway internet)
# Container debinet: TANPA systemd -> named dijalankan langsung (nohup).
#
# Pemakaian:
#   ./12-domain-ptr-forwarder.sh          # serial = zona lama + 1
#   ./12-domain-ptr-forwarder.sh 5        # paksa serial = 5

DOMAIN="jujutsu.K11.com"
IP="10.69.1.2"
SLAVE_IP="10.69.1.3"
GOJO_IP="10.69.1.4"
REVZONE="1.69.10.in-addr.arpa"
FWDZONE="/etc/bind/zones/db.$DOMAIN"
REVFILE="/etc/bind/zones/db.1.69.10"

# serial: arg angka, atau auto-increment dari zona lama, default 2
if [ -n "$1" ]; then
	SERIAL="$1"
elif [ -f "$FWDZONE" ]; then
	SERIAL=$(sed -n 's/^[[:space:]]*\([0-9][0-9]*\).*; Serial.*/\1/p' "$FWDZONE" | head -n1)
	[ -n "$SERIAL" ] || SERIAL=1
	SERIAL=$((SERIAL + 1))
else
	SERIAL=2
fi

# container-friendly: hapus policy-rc.d
rm -f /usr/sbin/policy-rc.d

# resolusi sementara
echo 'nameserver 192.168.122.1' > /etc/resolv.conf

# bind9 sudah dipasang di Soal 11; pasang bila belum ada
if ! command -v named >/dev/null 2>&1; then
	apt-get update
	DEBIAN_FRONTEND=noninteractive apt-get install -y bind9 bind9utils dnsutils
fi

# IP statis + route (idempotent)
ip link set eth0 up
ip addr replace $IP/24 dev eth0
ip route replace default via 10.69.1.1 2>/dev/null || true

mkdir -p /etc/bind/zones

# ---- named.conf.options: DNS Forwarder ke gateway internet ----
cat > /etc/bind/named.conf.options <<'EOF'
options {
	directory "/var/cache/bind";

	// DNS Forwarder: alamat di luar kawasan Shibuya diteruskan ke gateway NAT
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
};
EOF

# ---- zona forward (master) + zona reverse PTR (master) ----
cat > /etc/bind/named.conf.local <<EOF
//
// Do NOT edit any of these unless you know what you are doing
//

zone "$DOMAIN" {
	type master;
	file "$FWDZONE";
	// hanya slave shoko yang boleh AXFR/IXFR
	allow-transfer { $SLAVE_IP; };
	notify yes;
	also-notify { $SLAVE_IP; };
};

zone "$REVZONE" {
	type master;
	file "$REVFILE";
	allow-transfer { $SLAVE_IP; };
	notify yes;
	also-notify { $SLAVE_IP; };
};
EOF

# ---- file zona forward ----
cat > "$FWDZONE" <<EOF
;
; BIND data file for $DOMAIN (Soal 11 + 12)
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

; ---- Soal 12 ----
; Pintu masuk utama -> gojo
@       IN      A       $GOJO_IP
; Alias www -> domain utama
www     IN      CNAME   $DOMAIN.
EOF

# ---- file zona reverse (PTR) ----
cat > "$REVFILE" <<EOF
;
; BIND reverse data file for $REVZONE (Soal 12)
; Memetakan IP gojo kembali ke domain resminya
;
\$TTL    604800
@       IN      SOA     ns1.$DOMAIN. admin.$DOMAIN. (
			$SERIAL   ; Serial
			604800    ; Refresh
			86400     ; Retry
			2419200   ; Expire
			604800 )  ; Negative Cache TTL
;
@       IN      NS      ns1.$DOMAIN.
@       IN      NS      ns2.$DOMAIN.

; gojo (10.69.1.4) -> jujutsu.K11.com
4       IN      PTR     $DOMAIN.
EOF

chown -R bind:bind /etc/bind 2>/dev/null || true

named-checkconf
named-checkzone "$DOMAIN" "$FWDZONE" || exit 1
named-checkzone "$REVZONE" "$REVFILE" || exit 1

# container tanpa systemd: matikan instance lama, jalankan named baru
pkill named 2>/dev/null || true
sleep 1
nohup /usr/sbin/named -f -c /etc/bind/named.conf -u bind >/var/log/named.log 2>&1 &
sleep 2

# resolver utahime = dirinya sendiri
cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
search K11.com
EOF

if pgrep named >/dev/null; then
	echo "[utahime] DNS master (forward+PTR+forwarder) up, serial $SERIAL"
else
	echo "[utahime] GAGAL start named:"
	cat /var/log/named.log
	exit 1
fi

echo "--- test lokal ---"
echo -n "A jujutsu.$DOMAIN    : "; dig @127.0.0.1 "$DOMAIN" A +short
echo -n "CNAME www.$DOMAIN    : "; dig @127.0.0.1 "www.$DOMAIN" CNAME +short
echo -n "PTR 10.69.1.4        : "; dig @127.0.0.1 -x "$GOJO_IP" +short
echo -n "forwarder google.com : "; dig @127.0.0.1 google.com A +short | head -n1
