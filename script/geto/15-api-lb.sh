#!/bin/bash
# geto — API Load Balancer (Soal 15)
# Network 4 (Data Center), eth0 statis 10.69.4.2/24.
# Nginx sebagai load balancer untuk worker API:
#   - upstream api_cluster: nanami + todo, Weighted Round Robin 3:1
#   - (Soal 18) kirara sebagai backup server + passive health check
# Hanya geto yang boleh meneruskan trafik ke worker API (worker mem-allow geto).
# Container debinet (Debian 13, TANPA systemd).
#
# Pemakaian:
#   ./15-api-lb.sh

NODE="geto"
IP="10.69.4.2"
GATEWAY="10.69.4.1"
DOMAIN="jujutsu.K11.com"
SELF_IP="10.69.4.2"

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

# ---------- nginx: upstream api_cluster (weighted 3:1) + backup kirara ----------
cat > /etc/nginx/sites-available/api-lb.conf <<EOF
upstream api_cluster {
	# Weighted Round Robin 3:1 + passive health check (Soal 18)
	# max_fails=2 fail_timeout=5s: server dianggap mati setelah 2 kegagalan
	# dalam 5 detik, lalu dicoba lagi setelah 5 detik.
	server 10.69.4.5:80 weight=3 max_fails=2 fail_timeout=5s;   # nanami
	server 10.69.4.6:80 weight=1 max_fails=2 fail_timeout=5s;   # todo

	# backup: hanya dipakai bila seluruh server utama gagal (Soal 18)
	server 10.69.4.7:80 backup;                                  # kirara
}

server {
	listen 80 default_server;
	server_name $DOMAIN;

	# teruskan header identitas klien ke worker (Soal 17)
	proxy_set_header Host              \$host;
	proxy_set_header X-Real-IP         \$remote_addr;
	proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
	proxy_set_header X-Forwarded-Proto \$scheme;

	location / {
		proxy_pass http://api_cluster;
	}
}
EOF

ln -sf /etc/nginx/sites-available/api-lb.conf /etc/nginx/sites-enabled/api-lb.conf
rm -f /etc/nginx/sites-enabled/default

nginx -t || exit 1

pkill -f nginx 2>/dev/null || true
sleep 1
nginx
sleep 2

echo "[$NODE] API load balancer up (upstream api_cluster: nanami 3 / todo 1, backup kirara)"
echo "--- proses ---"
pgrep -a nginx | head -3
echo "--- distribusi backend (uji 8 request) ---"
for i in 1 2 3 4 5 6 7 8; do
	curl -s --max-time 5 -H "Host: $DOMAIN" http://127.0.0.1/ 2>/dev/null | grep -o '"worker":"[^"]*"' || echo "(backend mati)"
done
