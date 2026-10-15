#!/bin/sh
# Set IP statis + gateway untuk host infrastruktur (Soal 1).
# Jalankan di node masing-masing; IP ditentukan dari hostname (bisa di-override: ./01-static-ip.sh <nama>).
# Skema IP usulan K-11 — SESUAIKAN bila tabel spesifikasi asisten berbeda.

HOST=$(printf '%s' "${1:-$(hostname)}" | tr 'A-Z' 'a-z')

case "$HOST" in
	utahime) IP=10.69.1.2;  GW=10.69.1.1 ;;
	shoko)   IP=10.69.1.3;  GW=10.69.1.1 ;;
	gojo)    IP=10.69.1.4;  GW=10.69.1.1 ;;
	geto)    IP=10.69.4.2;  GW=10.69.4.1 ;;
	maki)    IP=10.69.4.3;  GW=10.69.4.1 ;;
	panda)   IP=10.69.4.4;  GW=10.69.4.1 ;;
	nanami)  IP=10.69.4.5;  GW=10.69.4.1 ;;
	todo)    IP=10.69.4.6;  GW=10.69.4.1 ;;
	kirara)  IP=10.69.4.7;  GW=10.69.4.1 ;;
	yaga)    IP=10.69.4.8;  GW=10.69.4.1 ;;
	inumaki) IP=10.69.4.9;  GW=10.69.4.1 ;;
	tengen)  IP=10.69.4.10; GW=10.69.4.1 ;;
	*) echo "host '$HOST' tidak dikenal; pakai: $0 <nama>"; exit 1 ;;
esac

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
	address $IP
	netmask 255.255.255.0
	gateway $GW
EOF

# Soal 10: autostart — /etc/network/interfaces menjalankan /root/<node>.sh saat boot.
# Hook /root/tengen.sh dibuat saat deploy; hanya tengen yang memilikinya.
if [ "$HOST" = tengen ]; then
	printf 'up bash /root/tengen.sh\n' >> /etc/network/interfaces
fi

# resolver sementara sampai DNS internal hidup
echo 'nameserver 192.168.122.1' > /etc/resolv.conf

# image debinet tak punya ifupdown -> apply langsung pakai ip (idempotent)
ip link set eth0 up
ip addr replace $IP/24 dev eth0
ip route replace default via $GW

echo "[$HOST] eth0 = $IP/24 gw $GW"
ip -br addr
ip route
