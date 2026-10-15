#!/bin/bash
# 17-test-clientip.sh — verifikasi client_ip terverifikasi (Soal 17)
# Dijalankan DARI klien (Network 2 mis. itadori, atau Network 3 mis. ino).
#
# Membuktikan: alamat yang tercatat di tabel request_logs = IP KLIEN ASLI,
# bukan IP gojo (10.69.1.4) maupun geto (10.69.4.2).
#
# Alur:
#   1. kirim request ke http://jujutsu.K11.com/api  (melewati gojo -> geto -> worker)
#   2. lihat client_ip pada respons JSON worker
#   3. (bila client DB tersedia) query langsung ke yaga untuk cross-check
#
# Pemakaian:
#   ./17-test-clientip.sh

DOMAIN="jujutsu.K11.com"
GOJO="10.69.1.4"
DB_HOST="10.69.4.8"
DB_NAME="db_shibuya_K11"
DB_USER="k11"
DB_PASS="k11pass"

SELF_IP=$(ip -4 -br addr show eth0 2>/dev/null | awk '{print $3}' | cut -d/ -f1)

echo "=============================================="
echo " Verifikasi client_ip (Soal 17)"
echo " klien: $(hostname)  IP asli: $SELF_IP"
echo "=============================================="

echo
echo "== 1) Kirim request ke /api lewat gojo =="
BODY=$(curl -s --max-time 12 -H "Host: $DOMAIN" "http://$GOJO/api/test" 2>/dev/null)
echo "  respons: $BODY"
W=$(printf '%s' "$BODY" | sed 's/.*"worker":"\([^"]*\)".*/\1/')
C=$(printf '%s' "$BODY" | sed 's/.*"client_ip":"\([^"]*\)".*/\1/')
echo "  worker    : ${W:-?}"
echo "  client_ip : ${C:-?}"

echo
echo "== 2) Penilaian =="
if [ "$C" = "$SELF_IP" ]; then
	echo "  [OK] client_ip = IP klien asli ($SELF_IP)"
	echo "       (bukan gojo 10.69.1.4 / geto 10.69.4.2)"
else
	echo "  [!!] client_ip=$C tidak sama dengan IP klien=$SELF_IP"
fi

echo
echo "== 3) Cross-check di database yaga (bila client tersedia) =="
DBBIN=""
command -v mariadb >/dev/null 2>&1 && DBBIN="mariadb"
[ -z "$DBBIN" ] && command -v mysql >/dev/null 2>&1 && DBBIN="mysql"

if [ -n "$DBBIN" ]; then
	$DBBIN -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" \
		-e "SELECT id, client_ip, method, path, created_at FROM request_logs ORDER BY id DESC LIMIT 5;" 2>&1
else
	echo "  (client mariadb tidak ada; jalankan 17-test-clientip.sh versi DB dari node Network 4,"
	echo "   atau periksa manual: mariadb -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME -e 'SELECT * FROM request_logs ORDER BY id DESC LIMIT 5;')"
fi

echo
echo "=============================================="
echo " Bukti sahih: baris request_logs.client_ip = $SELF_IP"
echo "=============================================="
