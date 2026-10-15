#!/bin/bash
# 16-test-routing.sh — uji path-based routing & header klien (Soal 16 & 17)
# Dijalankan dari klien (mis. itadori / kusakabe) menuju gojo.
#
# Uji:
#   1. "/"     -> dikerjakan worker frontend (maki/panda), Round Robin
#   2. "/api"  -> diteruskan ke geto lalu worker API (nanami/todo/kirara)
#   3. header  -> client_ip yang tercatat = IP klien ASLI (bukan IP gojo)
#
# Pemakaian:
#   ./16-test-routing.sh

DOMAIN="jujutsu.K11.com"
GOJO="10.69.1.4"

SELF_IP=$(ip -4 -br addr show eth0 2>/dev/null | awk '{print $3}' | cut -d/ -f1)

echo "=============================================="
echo " Uji Routing gojo (client: $(hostname) $SELF_IP)"
echo "=============================================="

echo
echo "== 1) Path '/' -> worker frontend (Round Robin maki/panda) =="
for i in 1 2 3 4 5 6; do
	W=$(curl -s --max-time 12 -H "Host: $DOMAIN" "http://$GOJO/" 2>/dev/null \
		| grep -o 'Web Worker: <b>[^<]*' | sed 's/.*<b>//')
	echo "  request $i -> ${W:-(kosong)}"
done

echo
echo "== 2) Path '/api' -> geto -> worker API =="
for i in 1 2 3 4; do
	B=$(curl -s --max-time 12 -H "Host: $DOMAIN" "http://$GOJO/api/test" 2>/dev/null)
	W=$(printf '%s' "$B" | sed 's/.*"worker":"\([^"]*\)".*/\1/')
	C=$(printf '%s' "$B" | sed 's/.*"client_ip":"\([^"]*\)".*/\1/')
	echo "  request $i -> worker=${W:-(kosong)} client_ip=${C:-?}"
done

echo
echo "== 3) Bukti header X-Real-IP (Soal 17) =="
echo "  IP klien sebenarnya : $SELF_IP"
echo "  client_ip tercatat  : (lihat hasil bagian 2 di atas)"
echo "  Jika client_ip == $SELF_IP, artinya header diteruskan dengan benar."

echo
echo "=============================================="
echo " Catatan: 'client_ip' harus sama dengan IP klien ($SELF_IP),"
echo " BUKAN IP gojo (10.69.1.4) atau geto (10.69.4.2)."
echo "=============================================="
