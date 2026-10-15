#!/bin/bash
# geto — Trusted Proxy / realip (Soal 17)
# Network 4 (Data Center), eth0 statis 10.69.4.2/24.
#
# Masalah: worker API menerima koneksi dari geto, sehingga default-nya
# REMOTE_ADDR = 10.69.4.2 (geto), bukan IP klien. Agar tercatat IP klien asli:
#   - geto hanya PERCAYA header dari gojo (10.69.1.4) -> set_real_ip_from
#   - geto membaca X-Real-IP kiriman gojo  -> real_ip_header X-Real-IP
#   - setelah itu \$remote_addr geto = IP klien asli, lalu diteruskan
#     kembali ke worker sebagai X-Real-IP.
#
# Script ini menulis ulang config geto (upstream api_cluster tetap sama)
# dan me-reload nginx. Tidak memasang paket (nginx sudah ada dari Soal 15).
#
# Pemakaian:
#   ./17-trusted-proxy.sh

NODE="geto"
DOMAIN="jujutsu.K11.com"
GOJO_IP="10.69.1.4"
NANAMI="10.69.4.5"
TODO="10.69.4.6"
KIRARA="10.69.4.7"

if ! command -v nginx >/dev/null 2>&1; then
	echo "[$NODE] nginx belum terpasang. Jalankan 15-api-lb.sh dulu."
	exit 1
fi

# ---------- config: realip (hanya percaya gojo) + weighted RR + backup ----------
cat > /etc/nginx/sites-available/api-lb.conf <<EOF
upstream api_cluster {
	# Weighted Round Robin 3:1 + passive health check (Soal 15 & 18)
	server $NANAMI:80 weight=3 max_fails=2 fail_timeout=5s;   # nanami
	server $TODO:80   weight=1 max_fails=2 fail_timeout=5s;   # todo
	server $KIRARA:80 backup;                                 # kirara (cadangan)
}

server {
	listen 80 default_server;
	server_name $DOMAIN;

	# ---- Soal 17: hanya percaya header alamat klien dari gojo ----
	set_real_ip_from $GOJO_IP;
	real_ip_header   X-Real-IP;
	real_ip_recursive on;

	location / {
		proxy_pass http://api_cluster;

		# teruskan IP klien asli (setelah realip) ke worker API
		proxy_set_header Host              \$host;
		proxy_set_header X-Real-IP         \$remote_addr;
		proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
		proxy_set_header X-Forwarded-Proto \$scheme;
	}
}
EOF

ln -sf /etc/nginx/sites-available/api-lb.conf /etc/nginx/sites-enabled/api-lb.conf
rm -f /etc/nginx/sites-enabled/default

nginx -t || exit 1

# reload bila sudah jalan, atau start bila belum
if pgrep -f nginx >/dev/null; then
	nginx -s reload 2>/dev/null || { pkill -f nginx; sleep 1; nginx; }
else
	nginx
fi
sleep 1

echo "[$NODE] trusted proxy (realip) aktif"
echo "  hanya percaya X-Real-IP dari gojo ($GOJO_IP)"
echo "  upstream: nanami(3) todo(1) + backup kirara"
pgrep -a nginx | head -3
