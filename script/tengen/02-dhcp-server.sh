#!/bin/sh
# tengen — DHCP Server (Soal 2)
# Network 4 = subnet lokal tanpa pool dinamis; deklarasikan scope Network 2 & 3.
# Pool/lease/fixed address diisi bertahap di Soal 4-6.
# Prefix internal 10.69 (verifikasi ke Master Sheet asisten).

# resolusi awal (pola AGENTS.md)
echo 'nameserver 192.168.122.1' > /etc/resolv.conf

# Image debinet = Debian buster (EOL): mirror deb.debian.org sudah 404,
# paket pindah ke archive.debian.org. Deteksi dulu; kalau paket tak ketemu, beralih.
SUITE=$(. /etc/os-release 2>/dev/null; printf '%s' "$VERSION_CODENAME")
[ -n "$SUITE" ] || SUITE=buster

apt-get update || true
if ! apt-cache show isc-dhcp-server >/dev/null 2>&1; then
	echo "[-] paket tak ditemukan di mirror bawaan; beralih ke archive.debian.org ($SUITE)"
	echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid
	cat > /etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian $SUITE main contrib non-free
deb http://archive.debian.org/debian $SUITE-updates main contrib non-free
deb http://archive.debian.org/debian-security $SUITE/updates main contrib non-free
EOF
	apt-get update
fi

DEBIAN_FRONTEND=noninteractive apt-get install -y isc-dhcp-server

# satu-satunya NIC tengen = eth0 (Network 4)
cat > /etc/default/isc-dhcp-server <<'EOF'
INTERFACESv4="eth0"
INTERFACESv6=""
EOF

cat > /etc/dhcp/dhcpd.conf <<'EOF'
authoritative;
option domain-name "jujutsu.K11.com";
option domain-name-servers 10.69.1.2, 10.69.1.3;

# Network 4 (Data Center) — subnet lokal, tanpa pool dinamis.
subnet 10.69.4.0 netmask 255.255.255.0 {
	option routers 10.69.4.1;
}

# Network 2 (Divisi A) — dilayani via DHCP relay jichi eth2.
subnet 10.69.2.0 netmask 255.255.255.0 {
	option routers 10.69.2.1;
	option broadcast-address 10.69.2.255;
}

# Network 3 (Divisi B) — dilayani via DHCP relay jichi eth3.
subnet 10.69.3.0 netmask 255.255.255.0 {
	option routers 10.69.3.1;
	option broadcast-address 10.69.3.255;
}
EOF

dhcpd -t -cf /etc/dhcp/dhcpd.conf
service isc-dhcp-server restart

echo "[tengen] isc-dhcp-server up"
service isc-dhcp-server status || true
