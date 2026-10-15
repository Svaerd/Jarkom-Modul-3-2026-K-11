#!/bin/bash
# inumaki — MariaDB DB-Slave (Soal 13)
# Network 4 (Data Center), eth0 statis 10.69.4.9/24.
# Menyalin db_shibuya_K11 dari master yaga (10.69.4.8) secara realtime.
#
# Container debinet (Debian 13 trixie, TANPA systemd):
#   - named/mariadbd dijalankan langsung via nohup
#   - apt dipaksa IPv4 + non-interaktif (jaringan lab hanya rute IPv4)
#
# Pemakaian:
#   ./13-db-slave.sh

IP="10.69.4.9"
GATEWAY="10.69.4.1"
MASTER_IP="10.69.4.8"
DB="db_shibuya_K11"
REPL_USER="replicator"
REPL_PASS="k11repl"
APP_USER="k11"
APP_PASS="k11pass"
SERVER_ID=2
DATADIR="/var/lib/mysql"
SOCKET="/run/mysqld/mysqld.sock"

# ---------- apt: IPv4 + non-interaktif (anti prompt Y/I/N/Z) ----------
rm -f /usr/sbin/policy-rc.d
mkdir -p /etc/apt/apt.conf.d
printf '%s\n' 'Acquire::ForceIPv4 "true";'                             > /etc/apt/apt.conf.d/99force-ipv4
printf '%s\n' 'Dpkg::Options { "--force-confdef"; "--force-confold"; };' > /etc/apt/apt.conf.d/99noninteractive
cat > /etc/apt/apt.conf.d/99robust-lab <<'EOF'
Acquire::Retries "8";
Acquire::http::Timeout "60";
Acquire::https::Timeout "60";
Acquire::http::Pipeline-Depth "0";
EOF
export DEBIAN_FRONTEND=noninteractive
APTOPTS="-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# resolusi sementara untuk unduh paket (konvensi awal)
echo 'nameserver 192.168.122.1' > /etc/resolv.conf

# ---------- install MariaDB (retry, tahan koneksi lambat) ----------
attempt=0
while [ $attempt -lt 5 ] && ! command -v mariadbd >/dev/null 2>&1 && ! command -v mysqld >/dev/null 2>&1; do
	attempt=$((attempt + 1))
	echo "[*] percobaan install ke-$attempt ..."
	apt-get $APTOPTS --fix-missing update
	apt-get $APTOPTS --fix-missing install mariadb-server mariadb-client
	sleep 2
done

if ! command -v mariadbd >/dev/null 2>&1 && ! command -v mysqld >/dev/null 2>&1; then
	echo "[inumaki] GAGAL install MariaDB. Cek koneksi lalu ulangi script ini."
	exit 1
fi

# ---------- IP statis + route ----------
ip link set eth0 up
ip addr replace $IP/24 dev eth0
ip route replace default via $GATEWAY 2>/dev/null || true

# resolusi setelah paket terpasang -> DNS internal kawasan
cat > /etc/resolv.conf <<'EOF'
nameserver 10.69.1.2
nameserver 10.69.1.3
EOF

# ---------- hentikan instance lama ----------
pkill -f mariadbd 2>/dev/null || true
pkill -f mysqld 2>/dev/null || true
sleep 2

# ---------- konfigurasi server: server-id unik + relay log ----------
mkdir -p /etc/mysql/mariadb.conf.d /run/mysqld /var/log/mysql
cat > /etc/mysql/mariadb.conf.d/50-server.cnf <<EOF
[mysqld]
user                    = mysql
bind-address            = 0.0.0.0
server-id               = $SERVER_ID
relay-log               = /var/log/mysql/mariadb-relay-bin
relay-log-index         = /var/log/mysql/mariadb-relay-bin.index
log_bin                 = /var/log/mysql/mariadb-bin
datadir                 = /var/lib/mysql
socket                  = $SOCKET
pid-file                = /run/mysqld/mysqld.pid
EOF

chown -R mysql:mysql /run/mysqld /var/log/mysql /var/lib/mysql 2>/dev/null || true

# ---------- init datadir bila kosong ----------
if [ ! -d "$DATADIR/mysql" ]; then
	echo "[*] init datadir MariaDB..."
	mariadb-install-db --user=mysql --datadir="$DATADIR" >/dev/null 2>&1 || \
		mysql_install_db --user=mysql --datadir="$DATADIR" >/dev/null 2>&1
fi

# ---------- jalankan mariadbd ----------
if command -v mariadbd >/dev/null 2>&1; then
	nohup mariadbd --user=mysql >/var/log/mysql/mariadbd.log 2>&1 &
else
	nohup mysqld --user=mysql >/var/log/mysql/mariadbd.log 2>&1 &
fi

for i in $(seq 1 40); do
	mariadb -uroot -e "SELECT 1" >/dev/null 2>&1 && break
	sleep 1
done

if ! mariadb -uroot -e "SELECT 1" >/dev/null 2>&1; then
	echo "[inumaki] GAGAL start MariaDB:"
	tail -n 20 /var/log/mysql/mariadbd.log
	exit 1
fi

# ---------- seed awal: dump dari master + koordinat binlog dari header dump ----------
echo "[*] dump awal dari master $MASTER_IP ..."
SEED_OK=0
if mariadb-dump -h "$MASTER_IP" -u "$REPL_USER" -p"$REPL_PASS" \
		--single-transaction --master-data=2 --databases "$DB" > /tmp/seed.sql 2>/dev/null; then
	SEED_OK=1
fi

BINLOG_FILE=""
BINLOG_POS=""
if [ "$SEED_OK" = "1" ]; then
	BINLOG_FILE=$(sed -n "s/.*MASTER_LOG_FILE='\([^']*\)'.*/\1/p" /tmp/seed.sql | head -n1)
	BINLOG_POS=$(sed -n "s/.*MASTER_LOG_POS=\([0-9]*\).*/\1/p" /tmp/seed.sql | head -n1)
	mariadb -uroot < /tmp/seed.sql && echo "  [OK] seed diimport (koordinat dari dump)"
else
	echo "  [!] dump awal gagal; fallback koordinat dari SHOW MASTER STATUS"
fi

# ---------- fallback: koordinat binlog master saat ini ----------
if [ -z "$BINLOG_FILE" ] || [ -z "$BINLOG_POS" ]; then
	STATUS=$(mariadb -h "$MASTER_IP" -u "$REPL_USER" -p"$REPL_PASS" -e "SHOW MASTER STATUS\G" 2>/dev/null)
	BINLOG_FILE=$(printf '%s\n' "$STATUS" | sed -n 's/^[[:space:]]*File:[[:space:]]*//p')
	BINLOG_POS=$(printf '%s\n' "$STATUS" | sed -n 's/^[[:space:]]*Position:[[:space:]]*//p')
fi

if [ -z "$BINLOG_FILE" ] || [ -z "$BINLOG_POS" ]; then
	echo "[inumaki] GAGAL ambil koordinat binlog dari master."
	echo "           Pastikan 13-db-master.sh sudah jalan di yaga."
	exit 1
fi
echo "[*] koordinat start slave: $BINLOG_FILE @ $BINLOG_POS"

# ---------- user app remote di slave (agar node Network 4 bisa baca slave) ----------
mariadb -uroot <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB\`;
CREATE USER IF NOT EXISTS '$APP_USER'@'10.69.4.%' IDENTIFIED BY '$APP_PASS';
GRANT ALL PRIVILEGES ON \`$DB\`.* TO '$APP_USER'@'10.69.4.%';
FLUSH PRIVILEGES;
EOF

# ---------- CHANGE MASTER TO ----------
mariadb -uroot <<EOF
STOP SLAVE;
RESET SLAVE ALL;
CHANGE MASTER TO
	MASTER_HOST     = '$MASTER_IP',
	MASTER_USER     = '$REPL_USER',
	MASTER_PASSWORD = '$REPL_PASS',
	MASTER_LOG_FILE = '$BINLOG_FILE',
	MASTER_LOG_POS  = $BINLOG_POS;
START SLAVE;
EOF

sleep 2

echo "[inumaki] DB-Slave up (server-id=$SERVER_ID, master=$MASTER_IP)"
echo "--- status slave ---"
mariadb -uroot -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Master_Host|Seconds_Behind_Master|Last_Error|Last_IO_Error"
echo "--- isi tabel ---"
mariadb -uroot -e "SELECT COUNT(*) AS jumlah FROM request_logs;" "$DB" 2>/dev/null || \
	echo "  (database belum ada - cek seed & binlog master)"
