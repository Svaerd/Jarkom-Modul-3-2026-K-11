#!/bin/sh
# tengen / jichi — autostart DHCP Server & Relay (Soal 10).
# Gambar debinet tak pakai systemd: autostart dhcpd/dhcrelay dilakukan lewat
# hook `up bash /root/<node>.sh` pada /etc/network/interfaces, yang menjalankan
# ulang script konfigurasi saat node restart (volume /root ikut persisten).
# Script ini membuktikan hook + symlink rc ada dan service sedang jalan.
# Prefix internal 10.69.

HOST=$(hostname)

case "$HOST" in
	tengen) HOOK=/root/tengen.sh; SVC=isc-dhcp-server; PAT='[d]hcpd' ;;
	jichi)  HOOK=/root/jichi.sh;  SVC=isc-dhcp-relay;  PAT='[d]hcrelay' ;;
	*) echo "host '$HOST' bukan tengen/jichi"; exit 1 ;;
esac

echo "=============================================="
echo " Autostart $SVC pada $HOST"
echo "=============================================="

echo "--- 1) hook di /etc/network/interfaces ---"
if grep -q "bash $HOOK" /etc/network/interfaces; then
	echo "[OK] ada baris: up bash $HOOK"
else
	echo "[!!] hook TIDAK ada; jalankan script config node lebih dulu"; exit 1
fi

echo
echo "--- 2) script hook ---"
ls -l "$HOOK" 2>/dev/null || echo "[!!] $HOOK tidak ada"
echo "--- isi $HOOK ---"; cat "$HOOK" 2>/dev/null

echo
echo "--- 3) symlink rc (autostart lewat init) ---"
ls -l /etc/rc*.d/ 2>/dev/null | grep "$SVC" || echo "(tak ada symlink rc; andalkan hook above)"

echo
echo "--- 4) status service saat ini ---"
service "$SVC" status 2>/dev/null || true
ps -ef | grep "$PAT" || echo "[!!] proses dhcp tidak jalan"

echo
echo "Restart node (GNS3: stop lalu start) untuk membuktikan autostart:"
echo "  tengen : isc-dhcp-server tetap 'running' setelah naik"
echo "  jichi  : dhcrelay tetap jalan di eth2/eth3/eth4"
echo "Lalu verifikasi klien: jalankan 07-verify-client.sh di tiap klien,"
echo "dan 07-verify-leases.sh di tengen (Pool1/Pool2/short/long/fixed tetap berlaku)."
