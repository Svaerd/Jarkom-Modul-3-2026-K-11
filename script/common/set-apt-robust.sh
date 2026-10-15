#!/bin/bash
# set-apt-robust.sh — resep apt tahan koneksi lambat (Semua node Modul 3)
# - paksa IPv4 (lab hanya rute IPv4)
# - non-interaktif penuh (anti prompt conf-file Y/I/N/Z)
# - retry otomatis + timeout diperpanjang (koneksi lab tidak stabil)
# Jalankan sebagai root.

rm -f /usr/sbin/policy-rc.d
mkdir -p /etc/apt/apt.conf.d

printf '%s\n' 'Acquire::ForceIPv4 "true";'                              > /etc/apt/apt.conf.d/99force-ipv4
printf '%s\n' 'Dpkg::Options { "--force-confdef"; "--force-confold"; };'  > /etc/apt/apt.conf.d/99noninteractive
cat > /etc/apt/apt.conf.d/99robust-lab <<'EOF'
Acquire::Retries "8";
Acquire::http::Timeout "60";
Acquire::https::Timeout "60";
Acquire::http::Pipeline-Depth "0";
EOF

echo "[apt] IPv4 + non-interaktif + retry aktif"
cat /etc/apt/apt.conf.d/99robust-lab
