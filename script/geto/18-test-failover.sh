#!/bin/bash
# 18-test-failover.sh — uji backup & passive health check geto (Soal 18)
#
# Skenario:
#   1. kondisi normal   -> request dilayani nanami/todo (kirara tidak dipakai)
#   2. nanami + todo dimatikan -> request otomatis dialihkan ke kirara (TANPA 502)
#   3. nanami + todo dihidupkan -> trafik kembali normal
#
# Dijalankan DI geto. Penghentian worker dilakukan lewat console node
# (script `18-worker-ctl.sh stop|start` di nanami/todo).
#
# Pemakaian:
#   ./18-test-failover.sh normal
#   ./18-test-failover.sh failover
#   ./18-test-failover.sh            # jalankan keduanya berurutan

DOMAIN="jujutsu.K11.com"
TARGET="http://127.0.0.1/api/test"
N=12

# ---- kirim sejumlah request, laporkan worker & kode HTTP ----
hitung() {
	local n="$1" i w c
	declare -A CNT CODE
	for i in $(seq 1 "$n"); do
		c=$(curl -s -o /tmp/_r.txt -w "%{http_code}" --max-time 10 -H "Host: $DOMAIN" "$TARGET" 2>/dev/null)
		CODE[$c]=$(( ${CODE[$c]:-0} + 1 ))
		w=$(sed 's/.*"worker":"\([^"]*\)".*/\1/' /tmp/_r.txt 2>/dev/null)
		case "$w" in
			nanami|todo|kirara) CNT[$w]=$(( ${CNT[$w]:-0} + 1 ));;
		esac
	done
	echo "  worker : nanami=${CNT[nanami]:-0}  todo=${CNT[todo]:-0}  kirara=${CNT[kirara]:-0}"
	echo -n "  HTTP   : "
	for k in "${!CODE[@]}"; do echo -n "$k=${CODE[$k]} "; done
	echo
	echo "${CODE[502]:-0}" > /tmp/_502.txt
	echo "${CNT[kirara]:-0}" > /tmp/_kirara.txt
}

echo "=============================================="
echo " Uji Failover Load Balancer geto (Soal 18)"
echo "  upstream: nanami(3) todo(1) + backup kirara"
echo "  health  : max_fails=2 fail_timeout=5s"
echo "=============================================="

mode="$1"

if [ "$mode" != "failover" ]; then
	echo
	echo "== 1) KONDISI NORMAL (nanami + todo hidup) =="
	hitung "$N"
	echo "  -> harapan: kirara=0, tanpa 502"
fi

if [ "$mode" != "normal" ]; then
	echo
	echo "== 2) KONDISI FAILOVER (nanami + todo MATI) =="
	# warmup: beri 3 request agar health check menandai server utama down
	echo "   (warmup 3 request agar passive health check aktif)"
	for i in 1 2 3; do curl -s -o /dev/null --max-time 10 -H "Host: $DOMAIN" "$TARGET" 2>/dev/null; done
	sleep 1
	hitung "$N"
	if [ "$(cat /tmp/_502.txt)" = "0" ]; then
		echo "  [OK] TIDAK ADA 502 -> backup kirara menangani request"
	else
		echo "  [!!] ada 502 -> backup belum menangani"
	fi
	echo "  -> harapan: kirara>0, tanpa 502"
fi

echo
echo "=== selesai ==="
