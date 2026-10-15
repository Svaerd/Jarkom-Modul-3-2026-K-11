#!/bin/bash
# yaga — MariaDB DB-Master (Soal 13)
# Network 4 (Data Center), eth0 statis 10.69.4.8/24.
# - Database  : db_shibuya_K11
# - Tabel     : request_logs
# - binary log: log-bin + server-id (replikasi)
# - Terima    : CHANGE MASTER TO dari slave inumaki (10.69.4.9)
# - Grant     : seluruh node Network 4 (10.69.4.0/24)
# Container debinet: TANPA systemd -> mariadbd dijalankan langsung (nohup).
#
# Pemakaian:
#   ./13-db-master.sh

IP="10.69.4.8"
GATEWAY="10.69.4.1"
DB="db_shibuya_K11"
REPL_USER="replicator"
REPL_PASS="k11repl"
SERVER_ID=1
DATADIR="/var/lib/mysql"
SOCKET="/run/mysqld/mysqld.sock"

# resep apt: IPv4 + non-interaktif (anti prompt Y/I/N/Z seperti saat conf file mariadb)
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

# resolusi sementara untuk unduh paket (konvensi AGENTS.md)
echo 'nameserver 192.168.122.1' > /etc/resolv.conf

# --- install MariaDB (retry, tahan koneksi lambat) ---
attempt=0
while [ $attempt -lt 5 ] && ! command -v mariadbd >/dev/null 2>&1 && ! command -v mysqld >/dev/null 2>&1; do
	attempt=$((attempt + 1))
	echo "[*] percobaan install ke-$attempt ..."
	apt-get $APTOPTS --fix-missing update
	apt-get $APTOPTS --fix-missing install mariadb-server mariadb-client
	sleep 2
done

if ! command -v mariadbd >/dev/null 2>&1 && ! command -v mysqld >/dev/null 2>&1; then
	echo "[yaga] GAGAL install MariaDB. Cek koneksi lalu ulangi script ini."
	exit 1
fi

# resolusi setelah paket terpasang -> DNS internal kawasan
cat > /etc/resolv.conf <<'EOF'
nameserver 10.69.1.2
nameserver 10.69.1.3
EOF

# --- IP statis + route ---
ip link set eth0 up
ip addr replace $IP/24 dev eth0
ip route replace default via $GATEWAY 2>/dev/null || true

# --- hentikan instance lama supaya config bersih ---
pkill -f mariadbd 2>/dev/null || true
pkill -f mysqld 2>/dev/null || true
sleep 2

# --- konfigurasi server: binary logging + server-id ---
mkdir -p /etc/mysql/mariadb.conf.d
cat > /etc/mysql/mariadb.conf.d/50-server.cnf <<EOF
[mysqld]
user                    = mysql
bind-address            = 0.0.0.0
server-id               = $SERVER_ID
log_bin                 = /var/log/mysql/mariadb-bin
log_bin_index           = /var/log/mysql/mariadb-bin.index
binlog_format           = ROW
max_binlog_size         = 100M
datadir                 = /var/lib/mysql
socket                  = $SOCKET
pid-file                = /run/mysqld/mysqld.pid
EOF

mkdir -p /run/mysqld /var/log/mysql
chown -R mysql:mysql /run/mysqld /var/log/mysql /var/lib/mysql 2>/dev/null || true

# --- init datadir bila kosong ---
if [ ! -d "$DATADIR/mysql" ]; then
	echo "[*] init datadir MariaDB..."
	mariadb-install-db --user=mysql --datadir="$DATADIR" >/dev/null 2>&1 || \
		mysql_install_db --user=mysql --datadir="$DATADIR" >/dev/null 2>&1
fi

# --- jalankan mariadbd (container tanpa systemd) ---
if command -v mariadbd >/dev/null 2>&1; then
	nohup mariadbd --user=mysql >/var/log/mysql/mariadbd.log 2>&1 &
else
	nohup mysqld --user=mysql >/var/log/mysql/mariadbd.log 2>&1 &
fi

# tunggu socket siap
for i in $(seq 1 30); do
	mariadb -uroot -e "SELECT 1" >/dev/null 2>&1 && break
	sleep 1
done

if ! mariadb -uroot -e "SELECT 1" >/dev/null 2>&1; then
	echo "[yaga] GAGAL start MariaDB:"
	tail -n 20 /var/log/mysql/mariadbd.log
	exit 1
fi

# --- database + tabel ---
mariadb -uroot <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB\`;
USE \`$DB\`;
CREATE TABLE IF NOT EXISTS request_logs (
	id          BIGINT AUTO_INCREMENT PRIMARY KEY,
	client_ip   VARCHAR(45),
	method      VARCHAR(10),
	path        VARCHAR(255),
	status      INT,
	created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF

# --- user replikasi untuk slave ---
mariadb -uroot <<EOF
CREATE USER IF NOT EXISTS '$REPL_USER'@'10.69.4.9' IDENTIFIED BY '$REPL_PASS';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO '$REPL_USER'@'10.69.4.9';
-- hak baca untuk seed awal (mysqldump dari slave)
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER ON \`$DB\`.* TO '$REPL_USER'@'10.69.4.9';
FLUSH PRIVILEGES;
EOF

# --- hak akses remote untuk SELURUH node Network 4 ---
mariadb -uroot <<EOF
CREATE USER IF NOT EXISTS 'k11'@'10.69.4.%' IDENTIFIED BY 'k11pass';
GRANT ALL PRIVILEGES ON \`$DB\`.* TO 'k11'@'10.69.4.%';
FLUSH PRIVILEGES;
EOF

echo "[yaga] DB-Master up (server-id=$SERVER_ID, db=$DB)"
echo "--- status master ---"
mariadb -uroot -e "SHOW MASTER STATUS;"
echo "--- tabel ---"
mariadb -uroot -e "SHOW TABLES;" "$DB"
echo "--- grant user ---"
mariadb -uroot -e "SELECT User, Host FROM mysql.user WHERE User IN ('$REPL_USER','k11');"
