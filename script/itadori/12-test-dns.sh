#!/bin/bash
# itadori — Klien Network 2 (Divisi A) — uji DNS Soal 12
# Membuktikan dari sisi client:
#   - A record jujutsu.K11.com -> gojo (10.69.1.4)
#   - CNAME www -> jujutsu.K11.com
#   - PTR (reverse) 10.69.1.4 -> jujutsu.K11.com
#   - forwarder: client tetap bisa resolve + ping domain internet (google.com)
#
# Pemakaian:
#   ./12-test-dns.sh          # query ke master (10.69.1.2) & slave (10.69.1.3)

DOMAIN="jujutsu.K11.com"
MASTER="10.69.1.2"
SLAVE="10.69.1.3"
GOJO_IP="10.69.1.4"

# pastikan dig tersedia (image client alpinet; bind-tools via apk)
if ! command -v dig >/dev/null 2>&1; then
	echo "[*] dig belum ada, memasang bind-tools..."
	apk add --no-cache bind-tools >/dev/null 2>&1 || true
fi
if ! command -v dig >/dev/null 2>&1; then
	echo "[-] dig tidak tersedia. Pasang manual: apk add bind-tools"
	exit 1
fi

echo "=============================================="
echo " Identitas client"
echo "=============================================="
echo "hostname : $(hostname)"
echo "IP client: $(ip -4 addr show dev eth0 2>/dev/null | awk '/inet / {print $2; exit}')"
echo "resolver :"; cat /etc/resolv.conf

echo
echo "=============================================="
echo " 1) A record $DOMAIN (-> gojo)"
echo "=============================================="
echo -n "dari master : "; dig @$MASTER "$DOMAIN" A +short
echo -n "dari slave  : "; dig @$SLAVE  "$DOMAIN" A +short

echo
echo "=============================================="
echo " 2) CNAME www.$DOMAIN (-> domain utama)"
echo "=============================================="
echo -n "dari master : "; dig @$MASTER "www.$DOMAIN" CNAME +short
echo -n "dari slave  : "; dig @$SLAVE  "www.$DOMAIN" CNAME +short
echo "-- resolve akhir www (A) --"
dig @$MASTER "www.$DOMAIN" A +short

echo
echo "=============================================="
echo " 3) Reverse DNS / PTR gojo ($GOJO_IP)"
echo "=============================================="
echo -n "dari master : "; dig @$MASTER -x "$GOJO_IP" +short
echo -n "dari slave  : "; dig @$SLAVE  -x "$GOJO_IP" +short

echo
echo "=============================================="
echo " 4) DNS Forwarder: resolusi domain internet"
echo "=============================================="
echo -n "google.com via $MASTER : "; dig @$MASTER google.com A +short | head -n1
echo -n "google.com via $SLAVE  : "; dig @$SLAVE  google.com A +short | head -n1

echo
echo "=============================================="
echo " 5) Ping domain internet (pakai resolver client)"
echo "=============================================="
ping -c 3 google.com

echo
echo "=============================================="
echo " Selesai. Screenshot bagian 1-5 sebagai bukti."
echo "=============================================="
