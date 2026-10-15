#!/bin/bash
# 15-test-lb.sh — uji distribusi Weighted Round Robin geto (Soal 15)
# Dijalankan DI geto (atau node Network 4). 12 request ke endpoint /api,
# hitung berapa kali tiap worker (nanami/todo) menjawab.

DOMAIN="jujutsu.K11.com"
TARGET="http://127.0.0.1/api/test"
N=12

declare -A COUNT
echo "=== $N request ke $TARGET (via geto) ==="
for i in $(seq 1 $N); do
	W=$(curl -s --max-time 12 -H "Host: $DOMAIN" "$TARGET" 2>/dev/null | sed 's/.*"worker":"\([^"]*\)".*/\1/')
	[ -z "$W" ] && W="(kosong)"
	COUNT[$W]=$(( ${COUNT[$W]:-0} + 1 ))
done

echo "--- hasil ---"
for k in "${!COUNT[@]}"; do
	echo "  $k : ${COUNT[$k]}"
done

# ringkasan rasio
echo "--- rasio ---"
NANAMI=${COUNT[nanami]:-0}
TODO=${COUNT[todo]:-0}
KIRARA=${COUNT[kirara]:-0}
echo "  nanami=$NANAMI  todo=$TODO  kirara(backup)=$KIRARA"
if [ "$NANAMI" -gt "$TODO" ] && [ "$KIRARA" -eq 0 ]; then
	echo "[OK] weighted 3:1 berlaku (nanami > todo), backup kirara belum dipakai"
else
	echo "[cek] nanami=$NANAMI todo=$TODO kirara=$KIRARA"
fi
