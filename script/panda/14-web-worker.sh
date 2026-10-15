#!/bin/bash
# panda — Web Worker (Soal 14)
# Network 4 (Data Center), eth0 statis 10.69.4.3/24.
# Nginx + PHP-FPM menyajikan halaman frontend yang menampilkan hostname.
# Virtual host merespons domain layanan jujutsu.K11.com (+ www).
# AKSES DIBATASI: hanya boleh diakses lewat gojo (10.69.1.4); selain itu ditolak.
# Container debinet (Debian 13, TANPA systemd) -> nginx/php-fpm dijalankan langsung.
#
# Pemakaian:
#   ./14-web-worker.sh

NODE="panda"
IP="10.69.4.4"
GATEWAY="10.69.4.1"
DOMAIN="jujutsu.K11.com"
WWW="www.jujutsu.K11.com"
PROXY_IP="10.69.1.4"          # gojo = satu-satunya jalur masuk web worker

# ---------- apt: IPv4 + non-interaktif + retry (jaringan lab labil) ----------
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

# resolusi: pakai DNS kawasan (utahime/shoko)
cat > /etc/resolv.conf <<'EOF'
nameserver 10.69.1.2
nameserver 10.69.1.3
EOF

# ---------- install nginx + php-fpm ----------
attempt=0
while [ $attempt -lt 5 ] && ! command -v nginx >/dev/null 2>&1; do
	attempt=$((attempt + 1))
	echo "[*] percobaan install ke-$attempt ..."
	echo 'nameserver 192.168.122.1' > /etc/resolv.conf
	apt-get $APTOPTS --fix-missing update
	apt-get $APTOPTS --fix-missing install nginx php-fpm php-mysql
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

# deteksi versi php-fpm
PHPV=$(ls /usr/sbin/php-fpm* 2>/dev/null | sed 's#.*/php-fpm##' | head -n1)
[ -n "$PHPV" ] || PHPV=$(ls /etc/php/ 2>/dev/null | head -n1)
echo "[*] php-fpm versi: $PHPV"

# ---------- root dokumen ----------
mkdir -p /var/www/html

cat > /var/www/html/index.php <<'EOF'
<?php
$host = gethostname();
echo "<!DOCTYPE html><html><head><title>Jujutsu High</title></head><body>";
echo "<h1>Curtain Protocol - Jujutsu High</h1>";
echo "<p>Web Worker: <b>" . htmlspecialchars($host) . "</b></p>";
echo "<p>Served at: " . date("Y-m-d H:i:s") . "</p>";
echo "<p>Remote addr: " . htmlspecialchars($_SERVER['REMOTE_ADDR'] ?? '-') . "</p>";
echo "</body></html>";
EOF

# ---------- php-fpm pool: socket ----------
FPM_SOCK="/run/php/php${PHPV}-fpm.sock"
mkdir -p /run/php
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

# ---------- nginx vhost: batasi hanya gojo ----------
cat > /etc/nginx/sites-available/worker.conf <<EOF
server {
	listen 80 default_server;
	server_name $DOMAIN $WWW;

	root /var/www/html;
	index index.php index.html;

	# hanya gojo (jalur proxy web) yang boleh mengakses worker ini
	allow $PROXY_IP;
	deny all;

	location / {
		try_files \$uri \$uri/ =404;
	}

	location ~ \.php\$ {
		include snippets/fastcgi-php.conf;
		fastcgi_pass unix:$FPM_SOCK;
	}
}
EOF

ln -sf /etc/nginx/sites-available/worker.conf /etc/nginx/sites-enabled/worker.conf
rm -f /etc/nginx/sites-enabled/default

chown -R www-data:www-data /var/www/html 2>/dev/null || true

nginx -t || exit 1

# ---------- jalankan nginx + php-fpm (tanpa systemd) ----------
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

echo "[$NODE] web worker up (vhost $DOMAIN, akses hanya dari $PROXY_IP)"
echo "--- proses ---"
pgrep -a nginx | head -3
pgrep -a php-fpm | head -3
echo "--- uji lokal (loopback 127.0.0.1) ---"
code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $DOMAIN" http://127.0.0.1/)
echo "HTTP $code (403 = benar; hanya $PROXY_IP/gojo yang diizinkan)"
