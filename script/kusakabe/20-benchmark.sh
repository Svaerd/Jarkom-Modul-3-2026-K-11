#!/bin/bash
# 20-benchmark.sh — Benchmark kapasitas layanan (Soal 20)
# Dijalankan DARI kusakabe (Network 3). kusakabe = Alpine Linux (pakai `apk`).
#
# Langkah:
#   1. pastikan Apache Benchmark (`apache2-utils`) tersedia via apk
#   2. benchmark halaman web : ab -n 600 -c 30 http://jujutsu.K11.com/
#   3. benchmark endpoint API: untuk mengamati efek rate limiting (banyak 429)
#   4. catat RPS, Time per request, Failed requests, Non-2xx
#
# Pemakaian:
#   ./20-benchmark.sh          # halaman web saja (sesuai soal)
#   ./20-benchmark.sh api      # halaman web + API
#
# Catatan DNS: kusakabe memakai resolver kawasan (10.69.1.2). Bila nama domain
# belum ter-resolve, script otomatis memakai --resolve ke gojo (10.69.1.4).

DOMAIN="jujutsu.K11.com"
GOJO="10.69.1.4"
URL_WEB="http://$DOMAIN/"
URL_API="http://$DOMAIN/api/test"

# ---------- pastikan ab terpasang (Alpine: apk) ----------
if ! command -v ab >/dev/null 2>&1; then
	echo "[*] apache2-utils belum ada, memasang via apk ..."
	# pakai DNS publik sementara untuk unduh paket
	echo 'nameserver 192.168.122.1' > /etc/resolv.conf
	apk update 2>/dev/null || true
	apk add --no-cache apache2-utils 2>/dev/null || apk add apache2-utils 2>/dev/null || true
	# kembalikan resolver kawasan
	{
		echo 'nameserver 10.69.1.2'
		echo 'nameserver 10.69.1.3'
	} > /etc/resolv.conf
fi

if ! command -v ab >/dev/null 2>&1; then
	echo "[-] Apache Benchmark (ab) gagal dipasang via apk."
	echo "    Cek koneksi lalu ulangi: apk add apache2-utils"
	exit 1
fi

# ---------- tentukan cara mengakses domain ----------
# Utamakan URL domain (sesuai soal). Bila DNS gagal, fallback --resolve.
RESOLVE_OPT=""
if ! ping -c 1 -W 3 "$DOMAIN" >/dev/null 2>&1 && ! getent hosts "$DOMAIN" >/dev/null 2>&1; then
	echo "[i] DNS belum me-resolve $DOMAIN -> memakai --resolve ke $GOJO"
	RESOLVE_OPT="--resolve $DOMAIN:80:$GOJO"
fi

echo "=============================================="
echo " Benchmark Layanan Jujutsu (Soal 20)"
echo " host: $(hostname)  target: $URL_WEB"
echo "=============================================="

echo
echo "############ BENCHMARK 1: halaman web ############"
echo "ab -n 600 -c 30 $URL_WEB $RESOLVE_OPT"
ab -n 600 -c 30 $RESOLVE_OPT "$URL_WEB" 2>&1 | \
	grep -E "Complete requests|Failed requests|Non-2xx|Requests per second|Time per request|Transfer rate|Percentage|Keep-Alive"

echo
if [ "$1" = "api" ]; then
	echo "############ BENCHMARK 2: endpoint API (efek rate limiting) ############"
	echo "ab -n 200 -c 20 $URL_API $RESOLVE_OPT"
	ab -n 200 -c 20 $RESOLVE_OPT "$URL_API" 2>&1 | \
		grep -E "Complete requests|Failed requests|Non-2xx|Requests per second|Time per request|Percentage"
	echo
	echo "Catatan: banyak Non-2xx (429) = rate limiting 10 req/s bekerja."
else
	echo "(jalankan dengan argumen 'api' untuk menguji endpoint /api)"
fi

echo
echo "=============================================="
echo " Catat untuk laporan:"
echo "  - Requests per second (RPS)"
echo "  - Time per request [ms] (latensi rata-rata)"
echo "  - Failed requests"
echo "  - Non-2xx responses (API: 429 dari rate limit)"
echo "=============================================="
