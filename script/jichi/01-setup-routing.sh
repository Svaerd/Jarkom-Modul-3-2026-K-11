#!/bin/sh
# jichi — Router Utama (Soal 1)
# eth0 WAN (DHCP dari NAT), eth1..eth4 gateway Network 1..4.
# Prefix internal 10.69.x.x

sysctl -w net.ipv4.ip_forward=1

cat >/etc/network/interfaces <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

auto eth1
iface eth1 inet static
	address 10.69.1.1
	netmask 255.255.255.0

auto eth2
iface eth2 inet static
	address 10.69.2.1
	netmask 255.255.255.0

auto eth3
iface eth3 inet static
	address 10.69.3.1
	netmask 255.255.255.0

auto eth4
iface eth4 inet static
	address 10.69.4.1
	netmask 255.255.255.0
EOF

# flush dulu supaya script aman dijalankan ulang
iptables -t nat -F POSTROUTING 2>/dev/null || true
iptables -F FORWARD 2>/dev/null || true

iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
for i in 1 2 3 4; do
  iptables -A FORWARD -i eth$i -o eth0 -j ACCEPT
done
for i in 1 2 3 4; do
  iptables -A FORWARD -i eth0 -o eth$i -m state --state ESTABLISHED,RELATED -j ACCEPT
done

# image debinet tak punya ifupdown -> apply langsung pakai ip (idempotent)
for i in 1 2 3 4; do ip link set eth$i up; done
ip addr replace 10.69.1.1/24 dev eth1
ip addr replace 10.69.2.1/24 dev eth2
ip addr replace 10.69.3.1/24 dev eth3
ip addr replace 10.69.4.1/24 dev eth4

echo "[jichi] routing + NAT up"
ip -br addr
ip route
