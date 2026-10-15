#!/bin/bash
# gojo — Public Reverse Proxy (Soal 16 & 17)
# Network 1 (DMZ), eth0 statis 10.69.1.4/24.
#
# Soal 16 — Path-Based Routing untuk domain jujutsu.K11.com (+ www):
#   - request "/"     -> Round Robin ke worker frontend (maki, panda)
#   - request "/api"  -> diteruskan ke geto (internal load balancer)
#
# Soal 17 — Meneruskan identitas klien ke geto via header:
#   - X-Real-IP        = IP asli klien
#   - X-Forwarded-For  = rangkaian proxy yang dilalui
# (geto kemudian memverifikasi & meneruskan IP asli ke worker API.)
#
# Container debinet (Debian 13, TANPA systemd) -> nginx dijalankan langsung.
#
# Pemakaian:
#   ./16-reverse-proxy.sh

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

# ---------- nginx: path-based routing ----------
cat > /etc/nginx/sites-available/reverse-proxy.conf <<EOF
# Upstream worker frontend (Round Robin maki/panda)
upstream web_cluster {
	server $MAKI:80;    # maki
	server $PANDA:80;   # panda
}

server {
	listen 80 default_server;
	server_name $DOMAIN $WWW;

	# ---- Soal 16: "/" -> worker frontend (Round Robin) ----
	location / {
		proxy_pass http://web_cluster;
		proxy_set_header Host              \$host;
		# ---- Soal 17: teruskan identitas klien ----
		proxy_set_header X-Real-IP         \$remote_addr;
		proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
		proxy_set_header X-Forwarded-Proto \$scheme;
	}

	# ---- Soal 16: "/api" -> geto (internal load balancer) ----
	location /api {
		proxy_pass http://$GETO;
		proxy_set_header Host              \$host;
		# ---- Soal 17: IP asli klien diteruskan ke geto ----
		proxy_set_header X-Real-IP         \$remote_addr;
		proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
		proxy_set_header X-Forwarded-Proto \$scheme;
	}
}
EOF

ln -sf /etc/nginx/sites-available/reverse-proxy.conf /etc/nginx/sites-enabled/reverse-proxy.conf
rm -f /etc/nginx/sites-enabled/default

nginx -t || exit 1

pkill -f nginx 2>/dev/null || true
sleep 1
nginx
sleep 2

echo "[$NODE] reverse proxy up (domain $DOMAIN)"
echo "  /     -> web_cluster (maki $MAKI, panda $PANDA) Round Robin"
echo "  /api  -> geto $GETO"
echo "--- proses ---"
pgrep -a nginx | head -3
