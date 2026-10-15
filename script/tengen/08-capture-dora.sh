#!/bin/sh
# tengen — DHCP Server (Soal 8): packet capture urutan DORA + giaddr.
# Menjalankan tcpdump di eth0 selama N detik (default 30). Selama itu, picu
# renew dari salah satu klien N2/N3 (mis. di fushiguro: `udhcpc -i eth0 -n -q`).
# -U wajib: tanpa itu tcpdump menyangga tulisannya ke file dan hasilnya kosong.
# Prefix internal 10.69.
#
# Pemakaian: ./08-capture-dora.sh [detik]

SECS=${1:-30}
OUT=/tmp/dora.txt

pkill -9 tcpdump 2>/dev/null || true
rm -f "$OUT"

echo "[tengen] menangkap DHCP (port 67/68) di eth0 selama ${SECS}s..."
echo "         >>> picu renew di klien sekarang, mis.: udhcpc -i eth0 -n -q <<<"
tcpdump -U -i eth0 -n -vv port 67 or port 68 > "$OUT" 2>&1 &
TPID=$!
sleep "$SECS"
kill "$TPID" 2>/dev/null || true
wait "$TPID" 2>/dev/null || true

echo
echo "=============================================="
echo " Ringkasan DORA (giaddr = Gateway-IP)"
echo "=============================================="
if ! grep -q 'DHCP-Message' "$OUT"; then
	echo "[-] tak ada paket DHCP tertangkap. Cek relay jichi + ulangi."
	exit 1
fi
grep -E 'DHCP-Message|Gateway-IP|Your-IP|Server-ID|Lease-Time|Client-Ethernet' "$OUT"

echo
echo "Urutan seharusnya: Discover -> Offer -> Request -> ACK"
echo "giaddr (Gateway-IP) N2 = 10.69.2.1, N3 = 10.69.3.1"
echo "Raw: $OUT   (bisa di-cat lagi sebagai bukti)"
