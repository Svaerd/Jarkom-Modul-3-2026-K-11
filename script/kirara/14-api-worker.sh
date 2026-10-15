#!/bin/bash
# kirara — API Worker (cadangan) (Soal 14)
# Network 4 (Data Center), eth0 statis 10.69.4.5/24.
# Layanan API (Nginx + PHP-FPM) yang mencatat tiap request ke DB yaga (10.69.4.8),
# tabel request_logs, database db_shibuya_K11.
# AKSES DIBATASI: hanya boleh diakses lewat geto (10.69.4.2); selain itu ditolak.
# Container debinet (Debian 13, TANPA systemd).
#
# Pemakaian:
#   ./14-api-worker.sh

NODE="kirara"
IP="10.69.4.7"
GATEWAY="10.69.4.1"
DOMAIN="jujutsu.K11.com"
PROXY_IP="10.69.4.2"          # geto = satu-satunya jalur masuk API worker
DB_HOST="10.69.4.8"           # yaga
DB_NAME="db_shibuya_K11"
DB_USER="k11"
DB_PASS="k11pass"

# ---------- apt: IPv4 + non-interaktif + retry ----------
rm -f /usr/sbin/policy-rc.d
mkdir -p /etc/apt/apt.conf.d
printf '%s\n' 'Acquire::ForceIPv4 "true";'                              > /etc/apt/apt.conf.d/99force-ipv4
printf '%s\n' 'Dpkg::Options { "--force-confdef"; "--force-confold"; };'  > /etc/apt/apt.conf.d/99noninteractive
printf '%s\n' 'Acquire::Retries "8";' 'Acquire::http::Timeout "60";' 'Acquire::https::Timeout "60";' 'Acquire::http::Pipeline-Depth "0";' > /etc/apt/apt.conf.d/99robust-lab
export DEBIAN_FRONTEND=noninteractive
APTOPTS="-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# ---------- IP statis + route ----------
ip link set eth0 up
ip addr replace $IP/24 dev eth0
ip route replace default via $GATEWAY 2>/dev/null || true

cat > /etc/resolv.conf <<'EOF'
nameserver 10.69.1.2
nameserver 10.69.1.3
EOF

# ---------- install nginx + php-fpm + mariadb client ----------
attempt=0
while [ $attempt -lt 5 ] && ! command -v nginx >/dev/null 2>&1; do
	attempt=$((attempt + 1))
	echo "[*] percobaan install ke-$attempt ..."
	echo 'nameserver 192.168.122.1' > /etc/resolv.conf
	apt-get $APTOPTS --fix-missing update
	apt-get $APTOPTS --fix-missing install nginx php-fpm php-mysql mariadb-client
	cat > /etc/resolv.conf <<'EOF'
nameserver 10.69.1.2
nameserver 10.69.1.3
EOF
	sleep 2
done

if ! command -v nginx >/dev/null 2>&1; then
	echo "[$NODE] GAGAL install nginx. Cek koneksi lalu ulangi script ini."
	exit 1
fi

PHPV=$(ls /usr/sbin/php-fpm* 2>/dev/null | sed 's#.*/php-fpm##' | head -n1)
[ -n "$PHPV" ] || PHPV=$(ls /etc/php/ 2>/dev/null | head -n1)
FPM_SOCK="/run/php/php${PHPV}-fpm.sock"
mkdir -p /run/php /var/www/html

# ---------- endpoint API ----------
cat > /var/www/html/index.php <<EOF
<?php
header('Content-Type: application/json');

\$host    = gethostname();
\$method  = \$_SERVER['REQUEST_METHOD'] ?? '-';
\$uri     = \$_SERVER['REQUEST_URI'] ?? '/';
\$client  = \$_SERVER['REMOTE_ADDR'] ?? '-';

// ambil client IP asli dari reverse proxy geto (bila ada)
\$xff = \$_SERVER['HTTP_X_FORWARDED_FOR'] ?? '';
\$xri = \$_SERVER['HTTP_X_REAL_IP'] ?? '';
if (\$xri !== '') {
	\$client = \$xri;
} elseif (\$xff !== '') {
	\$parts = explode(',', \$xff);
	\$client = trim(\$parts[0]);
}

// catat ke DB yaga
\$logged = false;
\$err = '';
try {
	\$pdo = new PDO('mysql:host=$DB_HOST;dbname=$DB_NAME;charset=utf8mb4', '$DB_USER', '$DB_PASS', [
		PDO::ATTR_TIMEOUT => 3,
		PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
	]);
	\$stmt = \$pdo->prepare('INSERT INTO request_logs (client_ip, method, path, status) VALUES (?, ?, ?, ?)');
	\$stmt->execute([\$client, \$method, \$uri, 200]);
	\$logged = true;
} catch (Exception \$e) {
	\$err = \$e->getMessage();
}

echo json_encode([
	'worker'   => \$host,
	'service'  => 'api',
	'method'   => \$method,
	'path'     => \$uri,
	'client_ip'=> \$client,
	'logged'   => \$logged,
	'error'    => \$err,
]);
EOF

# ---------- php-fpm pool ----------
if [ -d "/etc/php/$PHPV/fpm/pool.d" ]; then
	cat > "/etc/php/$PHPV/fpm/pool.d/www.conf" <<EOF
[www]
user = www-data
group = www-data
listen = $FPM_SOCK
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
EOF
fi

# ---------- nginx vhost API: batasi hanya geto ----------
cat > /etc/nginx/sites-available/api.conf <<EOF
server {
	listen 80 default_server;
	server_name $DOMAIN;

	root /var/www/html;
	index index.php index.html;

	# hanya geto (jalur proxy API) yang boleh mengakses worker ini
	allow $PROXY_IP;
	deny all;

	# API: semua path diarahkan ke index.php (front controller)
	location / {
		try_files \$uri \$uri/ /index.php?\$query_string;
	}

	location ~ \.php\$ {
		include snippets/fastcgi-php.conf;
		fastcgi_pass unix:$FPM_SOCK;
		fastcgi_param HTTP_X_REAL_IP \$http_x_real_ip;
		fastcgi_param HTTP_X_FORWARDED_FOR \$http_x_forwarded_for;
	}
}
EOF

ln -sf /etc/nginx/sites-available/api.conf /etc/nginx/sites-enabled/api.conf
rm -f /etc/nginx/sites-enabled/default

chown -R www-data:www-data /var/www/html 2>/dev/null || true

nginx -t || exit 1

# ---------- jalankan ----------
pkill -f nginx 2>/dev/null || true
sleep 1
nginx

pkill -f "php-fpm" 2>/dev/null || true
sleep 1
if command -v "php-fpm$PHPV" >/dev/null 2>&1; then
	"php-fpm$PHPV" -D 2>/dev/null || "php-fpm$PHPV"
else
	php-fpm -D 2>/dev/null || php-fpm
fi

sleep 2

echo "[$NODE] API worker up (vhost $DOMAIN, akses hanya dari $PROXY_IP, DB $DB_HOST)"
echo "--- proses ---"
pgrep -a nginx | head -2
pgrep -a php-fpm | head -2
echo "--- uji lokal (loopback 127.0.0.1) ---"
code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $DOMAIN" http://127.0.0.1/api/test)
echo "HTTP $code (403 = benar; hanya $PROXY_IP/geto yang diizinkan)"
