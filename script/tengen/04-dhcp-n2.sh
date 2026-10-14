#!/bin/sh
# tengen — DHCP Server: Network 2 pools & class by MAC (Soal 4)
# Pool 1: 10.69.2.10–10.69.2.35 (itadori, fushiguro)
# Pool 2: 10.69.2.70–10.69.2.95 (zenin, okkotsu)
# Range 10.69.2.36–10.69.2.69 dilarang
# Domain & DNS sesuai ketentuan: domain jujutsu.K11.com, DNS 10.69.1.2 10.69.1.3
# Prefix internal 10.69

# resolusi awal
echo 'nameserver 192.168.122.1' >/etc/resolv.conf

cat >>/etc/dhcp/dhcpd.conf <<'EOF'

# Network 2 classes (pisahkan berdasarkan MAC)
class "pool1-n2" {
  match pick-first-value (option dhcp-client-identifier, hardware);
}

class "pool2-n2" {
  match pick-first-value (option dhcp-client-identifier, hardware);
}

# MAC sesuai topologi
# itadori: 02:42:47:5c:e2:00
# fushiguro: 02:42:de:fd:46:00
# zenin: 02:42:90:6f:b5:00
# okkotsu: 02:42:86:db:d5:00
subclass "pool1-n2" 1:02:42:47:5c:e2:00;
subclass "pool1-n2" 1:02:42:de:fd:46:00;
subclass "pool2-n2" 1:02:42:90:6f:b5:00;
subclass "pool2-n2" 1:02:42:86:db:d5:00;

subnet 10.69.2.0 netmask 255.255.255.0 {
  option routers 10.69.2.1;
  option broadcast-address 10.69.2.255;
  option domain-name "jujutsu.K11.com";
  option domain-name-servers 10.69.1.2, 10.69.1.3;

  pool {
    allow members of "pool1-n2";
    range 10.69.2.10 10.69.2.35;
  }

  pool {
    allow members of "pool2-n2";
    range 10.69.2.70 10.69.2.95;
  }
}
EOF

dhcpd -t -cf /etc/dhcp/dhcpd.conf
service isc-dhcp-server restart

echo "[tengen] N2 pools & classes applied"
service isc-dhcp-server status
