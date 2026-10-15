#!/bin/bash
# 19-test-cache-ratelimit.sh — uji Proxy Cache + Rate Limit gojo (Soal 19)
# Dijalankan dari klien (mis. itadori / kusakabe) menuju gojo.
#
# Uji:
#   1. cache halaman web: akses pertama MISS, akses berikutnya HIT
#   2. rate limit /api   : request beruntun -> sebagian dibalas 429
#   3. lihat access log gojo untuk membedakan status
#
# Pemakaian:
#   ./19-test-cache-ratelimit.sh

DOMAIN="jujutsu.K11.com"
GOJO="10.69.1.4"

echo "=============================================="
echo " Uji Proxy Cache + Rate Limit gojo (Soal 19)"
echo "=============================================="

echo
echo "== 1) Proxy Cache halaman web (X-Cache-Status) =="
echo "   akses 1-5 (harus MISS lalu HIT) dan seterusnya:"
for i in 1 2 3 4 5; do
	S=$(curl -s -D - -o /dev/null --max-time 12 -H "Host: $DOMAIN" "http://$GOJO/" 2>/dev/null \
		| grep -i '^X-Cache-Status:' | tr -d '\r' | awk '{print $2}')
	echo "   request $i -> X-Cache-Status: ${S:-(tidak ada)}"
done

echo
echo "== 2) Rate Limit pada /api (batas 10 req/detik per IP) =="
echo "   mengirim 20 request cepat, hitung kode respons:"
declare -A CODE
for i in $(seq 1 20); do
	C=$(curl -s -o /dev/null -w "%{http_code}" --max-time 12 -H "Host: $DOMAIN" "http://$GOJO/api/test" 2>/dev/null)
	CODE[$C]=$(( ${CODE[$C]:-0} + 1 ))
done
for k in "${!CODE[@]}"; do
	echo "   HTTP $k -> ${CODE[$k]} request"
done
echo "   (harapan: sebagian 200, sebagian 429 karena limit 10r/s)"
if [ -n "${CODE[429]:-}" ]; then
	echo "   [OK] terlihat respons 429 -> rate limiting aktif"
else
	echo "   [cek] belum ada 429; coba naikkan jumlah request"
fi

echo
echo "=============================================="
echo " Selesai. Screenshot bagian 1-2 sebagai bukti."
echo "=============================================="
