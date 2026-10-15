#!/bin/sh
# tengen — DHCP Server: Network 3 (Soal 5 & 6)
# Short lease 1800s: ino, kusakabe (pool .3.10–.3.89)
# Long lease 43200s: miwa (pool .3.100–.3.199)
# Fixed: kugisaki MAC 02:42:69:c1:4e:00 -> 10.69.3.99 (di luar pool)
# DNS: 10.69.1.2, 10.69.1.3; domain-search jujutsu.K11.com (atau K11.com? soal: <xxxx>.com)

echo 'nameserver 192.168.122.1' > /etc/resolv.conf

cat >> /etc/dhcp/dhcpd.conf <<'EOF'

# Network 3 classes
class "n3-short" {
  match pick-first-value (option dhcp-client-identifier, hardware);
}
class "n3-long" {
  match pick-first-value (option dhcp-client-identifier, hardware);
}

# ino: 02:42:a6:05:0a:00
# kusakabe: 02:42:65:06:75:00
# miwa: 02:42:53:b6:7e:00
subclass "n3-short" 1:02:42:a6:05:0a:00;
subclass "n3-short" 1:02:42:65:06:75:00;
subclass "n3-long"  1:02:42:53:b6:7e:00;

# Fixed lease kugisaki (S6) — di luar pool dinamis
host kugisaki {
  hardware ethernet 02:42:69:c1:4e:00;
  fixed-address 10.69.3.99;
}

subnet 10.69.3.0 netmask 255.255.255.0 {
  option routers 10.69.3.1;
  option broadcast-address 10.69.3.255;
  option domain-name "jujutsu.K11.com";
  option domain-name-servers 10.69.1.2, 10.69.1.3;
  option domain-search "jujutsu.K11.com";

  # short
  pool {
    allow members of "n3-short";
    default-lease-time 1800;
    max-lease-time 1800;
    range 10.69.3.10 10.69.3.89;
  }

  # long
  pool {
    allow members of "n3-long";
    default-lease-time 43200;
    max-lease-time 43200;
    range 10.69.3.100 10.69.3.199;
  }
}
EOF

dhcpd -t -cf /etc/dhcp/dhcpd.conf
service isc-dhcp-server restart

echo "[tengen] N3 (short/long + fixed) applied"
service isc-dhcp-server status
