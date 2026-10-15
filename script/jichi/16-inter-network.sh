#!/bin/bash
# jichi — forwarding antar-network internal (prasyarat Soal 16)
# gojo (Network 1) harus bisa menjangkau worker di Network 4 (maki/panda/geto).
# Aturan dasar Soal 1 hanya mengizinkan ethN -> eth0 (internet), belum antar-zona.
# Script ini menambahkan ACCEPT untuk semua pasangan interface internal (eth1..eth4).
#
# Pemakaian (jalankan di jichi):
#   ./16-inter-network.sh

echo "[*] menambahkan forwarding antar-network internal (eth1..eth4) ..."

for i in 1 2 3 4; do
	for j in 1 2 3 4; do
		[ "$i" = "$j" ] && continue
		# hindari duplikasi aturan
		if ! iptables -C FORWARD -i "eth$i" -o "eth$j" -j ACCEPT 2>/dev/null; then
			iptables -A FORWARD -i "eth$i" -o "eth$j" -j ACCEPT
		fi
	done
done

echo "[jichi] forwarding internal aktif"
iptables -L FORWARD -n -v --line-numbers | head -25
