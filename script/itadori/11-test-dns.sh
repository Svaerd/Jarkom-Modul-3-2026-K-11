#!/bin/sh
# itadori — Klien Network 2 (Divisi A) — uji DNS Soal 11
# Klien memperoleh IP via DHCP dari tengen (relay jichi eth2).
# Script ini HANYA untuk membuktikan: master & slave melayani zona
# jujutsu.K11.com, zona tersinkron, dan allow-transfer dibatasi ke slave.
#
# Pemakaian:
#   ./11-test-dns.sh          # query dig ke master & slave
#   ./11-test-dns.sh serial   # bandingkan serial SOA master vs slave (bukti sinkron)

DOMAIN="jujutsu.K11.com"
MASTER="10.69.1.2"
SLAVE="10.69.1.3"

# pastikan dig tersedia (image client alpinet; bind-tools via apk)
if ! command -v dig >/dev/null 2>&1; then
	echo "[*] dig belum ada, memasang bind-tools..."
	apk add --no-cache bind-tools >/dev/null 2>&1 || true
fi
if ! command -v dig >/dev/null 2>&1; then
	echo "[-] dig tidak tersedia. Pasang manual: apk add bind-tools"
	exit 1
fi

echo "=============================================="
echo " Identitas client"
echo "=============================================="
echo "hostname : $(hostname)"
echo "IP client: $(ip -4 addr show dev eth0 2>/dev/null | awk '/inet / {print $2; exit}')"
echo "resolver :"
cat /etc/resolv.conf
ip route

echo
echo "=============================================="
echo " 1) SOA di MASTER ($MASTER)"
echo "=============================================="
dig @$MASTER "$DOMAIN" SOA +noall +answer +authority

echo
echo "=============================================="
echo " 2) SOA di SLAVE ($SLAVE)"
echo "=============================================="
dig @$SLAVE "$DOMAIN" SOA +noall +answer +authority

echo
echo "=============================================="
echo " 3) NS delegasi untuk $DOMAIN"
echo "=============================================="
echo "-- dari master --"; dig @$MASTER "$DOMAIN" NS +short
echo "-- dari slave  --"; dig @$SLAVE  "$DOMAIN" NS +short

echo
echo "=============================================="
echo " 4) Glue A record NS (ns1 & ns2)"
echo "=============================================="
dig @$MASTER "ns1.$DOMAIN" A +short
dig @$MASTER "ns2.$DOMAIN" A +short

echo
echo "=============================================="
echo " 5) AXFR dari client -> harus DITOLAK"
echo "    (bukti allow-transfer hanya untuk slave)"
echo "=============================================="
dig @$MASTER "$DOMAIN" AXFR | head -n 5

if [ "$1" = "serial" ]; then
	echo
	echo "=============================================="
	echo " Ringkasan serial (bukti sinkronisasi zona)"
	echo "=============================================="
	MS=$(dig @$MASTER "$DOMAIN" SOA +short | awk '{print $3}')
	SS=$(dig @$SLAVE  "$DOMAIN" SOA +short | awk '{print $3}')
	echo "serial master (utahime) = $MS"
	echo "serial slave  (shoko)   = $SS"
	if [ -n "$MS" ] && [ "$MS" = "$SS" ]; then
		echo "[OK] zona tersinkronisasi ke shoko"
	else
		echo "[!!] serial belum sama - tunggu transfer / cek allow-transfer & notify"
	fi
fi

echo
echo "=============================================="
echo " Selesai. Screenshot bagian 1-5 sebagai bukti."
echo "=============================================="
