#!/bin/bash
# gojo — Proxy Caching & Rate Limiting (Soal 19)
# Network 1 (DMZ), eth0 statis 10.69.1.4/24.
#
# Menulis ulang config gojo yang menggabungkan:
#   - Soal 16: path-based routing ("/" -> web_cluster, "/api" -> geto)
#   - Soal 17: header identitas klien (X-Real-IP, X-Forwarded-For)
#   - Soal 19: Nginx Proxy Caching halaman web (10 menit) + header X-Cache-Status
#   - Soal 19: rate limiting "/api" 10 request/detik per IP klien
#
# Detail Soal 19:
#   * proxy_cache_path ... keys_zone=web_cache  -> simpan cache halaman web
#   * proxy_cache_valid 200 10m                 -> cache berlaku 10 menit
#   * add_header X-Cache-Status \$upstream_cache_status -> MISS/HIT/EXPIRED
#   * limit_req_zone \$binary_remote_addr rate=10r/s      -> 10 req/detik per IP
#   * limit_req_status 429                       -> balasan saat limit terlampaui
#
# Container debinet (Debian 13, TANPA systemd).
#
# Pemakaian:
#   ./19-cache-ratelimit.sh

NODE="gojo"
IP="10.69.1.4"
GATEWAY="10.69.1.1"
DOMAIN="jujutsu.K11.com"
WWW="www.jujutsu.K11.com"
MAKI="10.69.4.3"
PANDA="10.69.4.4"
GETO="10.69.4.2"

# ---------- apt: IPv4 + non-interaktif + retry ----------
rm -f /usr/sbin/policy-rc.d
mkdir -p /etc/apt/apt.conf.d
printf '%s\n' 'Acquire::ForceIPv4 "true";'                              > /etc/apt/apt.conf.d/99force-ipv4
printf '%s\n' 'Dpkg::Options { "--force-confdef"; "--force-confold"; };'  > /etc/apt/apt.conf.d/99noninteractive
printf '%s\n' 'Acquire::Retries "8";' 'Acquire::http::Timeout "60";' 'Acquire::https::Timeout "60";' > /etc/apt/apt.conf.d/99robust-lab
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

# ---------- install nginx ----------
attempt=0
while [ $attempt -lt 5 ] && ! command -v nginx >/dev/null 2>&1; do
	attempt=$((attempt + 1))
	echo "[*] percobaan install ke-$attempt ..."
	echo 'nameserver 192.168.122.1' > /etc/resolv.conf
	apt-get $APTOPTS --fix-missing update
	apt-get $APTOPTS --fix-missing install nginx
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

# ---------- direktori cache ----------
mkdir -p /var/cache/nginx/web
chown -R www-data:www-data /var/cache/nginx 2>/dev/null || true

# ---------- konteks http: cache zone + rate limit zone ----------
# /etc/nginx/conf.d/*.conf di-include di dalam blok http pada Debian.
cat > /etc/nginx/conf.d/19-cache-ratelimit.conf <<'EOF'
# ---- Soal 19: zona cache halaman web ----
proxy_cache_path /var/cache/nginx/web
	levels=1:2
	keys_zone=web_cache:10m
	max_size=100m
	inactive=10m
	use_temp_path=off;

# ---- Soal 19: zona rate limit per IP klien (10 req/detik) ----
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;

# ---- log format: tandai request yang kena rate limit ----
log_format rl '$remote_addr - [$time_local] "$request" $status '
              'cache=$upstream_cache_status limit=$limit_req_status '
              'ua="$http_user_agent"';
EOF

# ---------- vhost gojo: routing + cache + rate limit ----------
cat > /etc/nginx/sites-available/reverse-proxy.conf <<EOF
upstream web_cluster {
	server $MAKI:80;    # maki
	server $PANDA:80;   # panda
}

server {
	listen 80 default_server;
	server_name $DOMAIN $WWW;

	access_log /var/log/nginx/gojo-access.log rl;

	# ---- Soal 16 + 19: "/" -> worker frontend (Round Robin) + cache 10 menit ----
	location / {
		proxy_pass http://web_cluster;
		proxy_set_header Host              \$host;
		proxy_set_header X-Real-IP         \$remote_addr;
		proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
		proxy_set_header X-Forwarded-Proto \$scheme;

		# Soal 19: proxy caching
		proxy_cache            web_cache;
		proxy_cache_valid      200 10m;
		proxy_cache_use_stale  error timeout updating;
		proxy_cache_lock       on;
		add_header X-Cache-Status \$upstream_cache_status;
	}

	# ---- Soal 16 + 17 + 19: "/api" -> geto + rate limit 10 req/s ----
	location /api {
		# Soal 19: rate limiting (burst kecil, tolak sisanya dengan 429)
		limit_req        zone=api_limit burst=5 nodelay;
		limit_req_status 429;

		proxy_pass http://$GETO;
		proxy_set_header Host              \$host;
		proxy_set_header X-Real-IP         \$remote_addr;
		proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
		proxy_set_header X-Forwarded-Proto \$scheme;
	}
}
EOF

ln -sf /etc/nginx/sites-available/reverse-proxy.conf /etc/nginx/sites-enabled/reverse-proxy.conf
rm -f /etc/nginx/sites-enabled/default

nginx -t || exit 1

if pgrep -f nginx >/dev/null; then
	nginx -s reload 2>/dev/null || { pkill -f nginx; sleep 1; nginx; }
else
	nginx
fi
sleep 1

echo "[$NODE] gojo up: cache halaman web 10m + rate limit /api 10r/s per IP"
pgrep -a nginx | head -3
