#!/bin/bash
# 20-log-analysis.sh — Analisis access log gojo (Soal 20)
# Dijalankan DI gojo.
#
# Membantu membedakan jenis kegagalan request saat benchmark:
#   - 2xx/3xx  : sukses (200 juga termasuk HIT/MISS cache)
#   - 429      : ditolak kebijakan rate limit
#   - 499/502/504 : masalah koneksi / aplikasi / backend
#
# Format log gojo (dari 19-cache-ratelimit.sh):
#   $remote_addr - [$time_local] "$request" $status cache=$upstream_cache_status limit=$limit_req_status ...
#
# Pemakaian:
#   ./20-log-analysis.sh

LOG="/var/log/nginx/gojo-access.log"

if [ ! -f "$LOG" ]; then
	echo "[-] log tidak ditemukan: $LOG"
	exit 1
fi

echo "=============================================="
echo " Analisis access log gojo ($LOG)"
echo "=============================================="

echo
echo "== Total request =="
wc -l < "$LOG"

echo
echo "== Distribusi kode status =="
awk '{for(i=1;i<=NF;i++) if($i ~ /^[1-5][0-9][0-9]$/){print $i; break}}' "$LOG" \
	| sort | uniq -c | sort -rn

echo
echo "== Distribusi status cache (MISS/HIT/EXPIRED) =="
grep -o 'cache=[A-Z]*' "$LOG" | sort | uniq -c | sort -rn

echo
echo "== Request yang ditolak rate limit (429) =="
grep -c ' 429 ' "$LOG" || echo 0

echo
echo "== 10 request terakhir =="
tail -10 "$LOG"

echo
echo "=============================================="
echo " Interpretasi:"
echo "  - 429 muncul  -> rate limit /api bekerja"
echo "  - cache=HIT   -> proxy cache bekerja (akses ulang halaman web)"
echo "  - 502/504     -> backend (worker) tidak terjangkau"
echo "=============================================="
