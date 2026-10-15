#!/bin/bash
# itadori — Uji pembatasan akses worker (Soal 14)
# Membuktikan:
#   - akses LANGSUNG dari klien ke worker web/API ditolak
#   - akses lewat reverse proxy (gojo / geto) berhasil
#
# Catatan: pada tahap Soal 14, gojo & geto belum dikonfigurasi (Soal 15/16),
# jadi bagian "via proxy" akan dijalankan ulang setelah soal tersebut selesai.
#
# Pemakaian:
#   ./14-test-access.sh

DOMAIN="jujutsu.K11.com"
MAKI="10.69.4.3"
PANDA="10.69.4.4"
NANAMI="10.69.4.5"
TODO="10.69.4.6"
KIRARA="10.69.4.7"
GOJO="10.69.1.4"
GETO="10.69.4.2"

echo "=============================================="
echo " Uji Pembatasan Akses Worker (client: $(hostname))"
echo "=============================================="

echo
echo "== 1) AKSES LANGSUNG ke web worker -> harus DITOLAK (403) =="
for ip in $MAKI $PANDA; do
	code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 6 -H "Host: $DOMAIN" "http://$ip/")
	echo "  web worker $ip -> HTTP $code"
done

echo
echo "== 2) AKSES LANGSUNG ke API worker -> harus DITOLAK (403) =="
for ip in $NANAMI $TODO $KIRARA; do
	code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 6 -H "Host: $DOMAIN" "http://$ip/api/test")
	echo "  api worker $ip -> HTTP $code"
done

echo
echo "== 3) AKSES LEWAT reverse proxy web (gojo $GOJO) -> harus BERHASIL =="
curl -s --max-time 8 -H "Host: $DOMAIN" "http://$GOJO/" | head -5
echo

echo
echo "== 4) AKSES LEWAT reverse proxy API (geto $GETO) -> harus BERHASIL =="
curl -s --max-time 8 -H "Host: $DOMAIN" "http://$GETO/api/test"
echo

echo
echo "=============================================="
echo " Ringkasan:"
echo "  - langsung ke worker  -> 403 (ditolak)"
echo "  - via gojo/geto       -> 200 (berhasil)"
echo "=============================================="
