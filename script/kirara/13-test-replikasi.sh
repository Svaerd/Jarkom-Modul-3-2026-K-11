#!/bin/bash
# kirara — Uji Replikasi MariaDB (Soal 13)
# Dijalankan dari node Network 4 (client), bukan dari yaga/inumaki.
# Insert data baru ke MASTER, lalu baca hasilnya di SLAVE.
#
# Pemakaian:
#   ./13-test-replikasi.sh

MASTER_IP="10.69.4.8"
SLAVE_IP="10.69.4.9"
DB="db_shibuya_K11"
USER="k11"
PASS="k11pass"
MARKER="repl-test-$(date +%s)"
MARKER_PATH="/$MARKER"

# ambil IPv4 klien tanpa prefix CIDR (10.69.4.7/24 -> 10.69.4.7)
CLIENT_IP=$(ip -4 -br addr show eth0 2>/dev/null | awk '{print $3}' | cut -d/ -f1)

# ---------- tentukan biner client MariaDB ----------
# pakai `mariadb` kalau ada, kalau tidak `mysql` (mariadb-client menyediakan keduanya)
DBBIN=""
if command -v mariadb >/dev/null 2>&1; then
	DBBIN="mariadb"
elif command -v mysql >/dev/null 2>&1; then
	DBBIN="mysql"
fi

# ---------- pasang client bila belum ada (non-interaktif + IPv4 + retry) ----------
if [ -z "$DBBIN" ]; then
	echo "[*] mariadb-client belum ada, memasang..."
	rm -f /usr/sbin/policy-rc.d
	mkdir -p /etc/apt/apt.conf.d
	printf '%s\n' 'Acquire::ForceIPv4 "true";'                              > /etc/apt/apt.conf.d/99force-ipv4
	printf '%s\n' 'Dpkg::Options { "--force-confdef"; "--force-confold"; };'  > /etc/apt/apt.conf.d/99noninteractive
	printf '%s\n' 'Acquire::Retries "8";' 'Acquire::http::Timeout "60";' 'Acquire::https::Timeout "60";' > /etc/apt/apt.conf.d/99robust-lab
	export DEBIAN_FRONTEND=noninteractive
	echo 'nameserver 192.168.122.1' > /etc/resolv.conf

	attempt=0
	while [ $attempt -lt 5 ] && [ -z "$DBBIN" ]; do
		attempt=$((attempt + 1))
		echo "[*] percobaan install ke-$attempt ..."
		apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold --fix-missing update
		apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold --fix-missing install mariadb-client
		if command -v mariadb >/dev/null 2>&1; then
			DBBIN="mariadb"
		elif command -v mysql >/dev/null 2>&1; then
			DBBIN="mysql"
		fi
	done
fi

# resolusi kembali ke DNS kawasan
cat > /etc/resolv.conf <<'EOF'
nameserver 10.69.1.2
nameserver 10.69.1.3
EOF

if [ -z "$DBBIN" ]; then
	echo "[-] mariadb-client GAGAL dipasang (koneksi lab). Jalankan ulang script ini."
	exit 1
fi
echo "[*] memakai client: $DBBIN"

echo "=============================================="
echo " Uji Replikasi MariaDB (client: $(hostname) $CLIENT_IP)"
echo "=============================================="

echo
echo "== 1) hak akses remote ke MASTER ($MASTER_IP) =="
$DBBIN -h "$MASTER_IP" -u "$USER" -p"$PASS" -e "SELECT 'akses-master-OK' AS status;" 2>&1

echo
echo "== 2) INSERT data baru di MASTER =="
$DBBIN -h "$MASTER_IP" -u "$USER" -p"$PASS" "$DB" <<EOF
INSERT INTO request_logs (client_ip, method, path, status)
VALUES ('$CLIENT_IP', 'GET', '$MARKER_PATH', 200);
EOF
echo "inserted marker: $MARKER_PATH"
$DBBIN -h "$MASTER_IP" -u "$USER" -p"$PASS" "$DB" -e "SELECT COUNT(*) AS jumlah_di_master FROM request_logs;"

echo
echo "== 3) tunggu replikasi (3 detik) =="
sleep 3

echo
echo "== 4) baca di SLAVE ($SLAVE_IP) =="
$DBBIN -h "$SLAVE_IP" -u "$USER" -p"$PASS" "$DB" <<EOF
SELECT COUNT(*) AS jumlah_di_slave FROM request_logs;
SELECT id, client_ip, path FROM request_logs WHERE path = '$MARKER_PATH';
EOF

echo
echo "== 5) cek baris marker di kedua server =="
M=$($DBBIN -h "$MASTER_IP" -u "$USER" -p"$PASS" "$DB" -N -B -e "SELECT COUNT(*) FROM request_logs WHERE path = '$MARKER_PATH';" 2>/dev/null)
S=$($DBBIN -h "$SLAVE_IP" -u "$USER" -p"$PASS" "$DB" -N -B -e "SELECT COUNT(*) FROM request_logs WHERE path = '$MARKER_PATH';" 2>/dev/null)
echo "marker di master = $M , di slave = $S"
if [ "$M" = "1" ] && [ "$S" = "1" ]; then
	echo "[OK] replikasi berhasil - data master tersalin ke slave"
else
	echo "[!!] replikasi belum sinkron - cek SHOW SLAVE STATUS di inumaki"
fi

echo
echo "=============================================="
echo " Selesai. Screenshot bagian 1-5 sebagai bukti."
echo "=============================================="
