#!/bin/sh
# jichi — DHCP Relay (Soal 3)
# Teruskan DHCP dari Network 2 (eth2) & Network 3 (eth3) ke tengen 10.69.4.10.
# Network 1 (eth1) & 4 (eth4) tak di-relay (server lokal / DMZ statis).
# Prefix internal 10.69 (verifikasi ke Master Sheet asisten).

# resolusi awal
echo 'nameserver 192.168.122.1' > /etc/resolv.conf

# Image debinet = Debian buster (EOL): mirror deb.debian.org 404 -> archive.debian.org.
SUITE=$(. /etc/os-release 2>/dev/null; printf '%s' "$VERSION_CODENAME")
[ -n "$SUITE" ] || SUITE=buster

apt-get update || true
if ! apt-cache show isc-dhcp-relay >/dev/null 2>&1; then
	echo "[-] paket tak ditemukan di mirror bawaan; beralih ke archive.debian.org ($SUITE)"
	echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid
	cat > /etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian $SUITE main contrib non-free
deb http://archive.debian.org/debian $SUITE-updates main contrib non-free
deb http://archive.debian.org/debian-security $SUITE/updates main contrib non-free
EOF
	apt-get update
fi

DEBIAN_FRONTEND=noninteractive apt-get install -y isc-dhcp-relay

# eth2/eth3 = sisi client; eth4 = sisi server (tengen 10.69.4.10).
# dhcrelay hanya memproses interface yang didaftarkan, jadi eth4 wajib ada
# agar balasan (DHCPOFFER) dari server tidak dibuang.
cat > /etc/default/isc-dhcp-relay <<'EOF'
SERVERS="10.69.4.10"
INTERFACES="eth2 eth3 eth4"
OPTIONS=""
EOF

service isc-dhcp-relay restart

echo "[jichi] dhcrelay up"
ps -ef | grep '[d]hcrelay' || true
