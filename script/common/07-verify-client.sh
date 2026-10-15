#!/bin/sh
# <client> — uji konfigurasi jaringan sisi klien (Soal 7)
# Dijalankan di tiap klien N2/N3 (image alpinet). Aman dijalankan berkali-kali.
# Membuktikan: mask /24, gateway & broadcast benar, DNS 10.69.1.2/10.69.1.3,
# domain-search jujutsu.K11.com, dan IP berada di dalam kebijakan pool-nya.
# Prefix internal 10.69.

HOST=$(hostname)

case "$HOST" in
	itadori|fushiguro) NET=2; LO=10;  HI=35;  KET="N2 Pool 1 (.2.10-.2.35)" ;;
	zenin|okkotsu)     NET=2; LO=70;  HI=95;  KET="N2 Pool 2 (.2.70-.2.95)" ;;
	ino|kusakabe)      NET=3; LO=10;  HI=89;  KET="N3 short lease (.3.10-.3.89)" ;;
	miwa)              NET=3; LO=100; HI=199; KET="N3 long lease (.3.100-.3.199)" ;;
	kugisaki)          NET=3; LO=99;  HI=99;  KET="N3 fixed address (.3.99)" ;;
	*) echo "host '$HOST' bukan klien N2/N3"; exit 1 ;;
esac

# parsing tanpa flag -o/-br: BusyBox ip pada image client (alpinet) tak mendukungnya
INET=$(ip -4 addr show dev eth0 2>/dev/null | awk '/inet / {print $2; exit}')
IP=${INET%%/*}
MASK=${INET##*/}
GW=$(ip route 2>/dev/null | awk '/^default/ {print $3; exit}')
BRD=$(ip -4 addr show dev eth0 2>/dev/null | awk '/inet / {for(i=1;i<=NF;i++) if($i=="brd"){print $(i+1); exit}}')
DNS=$(awk '/^nameserver/ {print $2}' /etc/resolv.conf | tr '\n' ' ')
SEARCH=$(awk '/^search/ {print $2}' /etc/resolv.conf)
LAST=${IP##*.}

echo "=============================================="
echo " Klien $HOST  ($KET)"
echo "=============================================="
printf 'ip            : %s\n' "$IP"
printf 'prefix/mask   : /%s (%s)\n' "$MASK" "$( [ "$MASK" = 24 ] && echo 255.255.255.0 )"
printf 'gateway       : %s\n' "$GW"
printf 'broadcast     : %s\n' "$BRD"
printf 'dns           : %s\n' "$DNS"
printf 'domain-search : %s\n' "$SEARCH"
echo "--- ip route ---"; ip route
echo "--- /etc/resolv.conf ---"; cat /etc/resolv.conf

echo
echo "=============================================="
echo " Pemeriksaan kebijakan"
echo "=============================================="
OK=1

if [ -z "$IP" ]; then echo "[!!] belum memperoleh lease (udhcpc -i eth0)"; exit 1; fi

case "$IP" in
	10.69.$NET.*) echo "[OK] subnet sesuai ($IP di 10.69.$NET.0/24)" ;;
	*) echo "[!!] subnet SALAH: $IP bukan 10.69.$NET.0/24"; OK=0 ;;
esac

if [ "$LAST" -ge "$LO" ] && [ "$LAST" -le "$HI" ]; then
	echo "[OK] alamat dalam rentang $KET"
else
	echo "[!!] alamat $LAST DI LUAR rentang $LO-$HI ($KET)"; OK=0
fi

[ "$MASK" = 24 ] && echo "[OK] subnet mask /24" || { echo "[!!] mask salah: /$MASK"; OK=0; }
[ "$GW" = "10.69.$NET.1" ] && echo "[OK] gateway 10.69.$NET.1" || { echo "[!!] gateway salah: $GW"; OK=0; }
[ "$BRD" = "10.69.$NET.255" ] && echo "[OK] broadcast 10.69.$NET.255" || { echo "[!!] broadcast salah: $BRD"; OK=0; }

case "$DNS" in
	*10.69.1.2*10.69.1.3*) echo "[OK] DNS 10.69.1.2 & 10.69.1.3" ;;
	*) echo "[!!] DNS tidak sesuai: $DNS"; OK=0 ;;
esac

[ "$SEARCH" = "jujutsu.K11.com" ] && echo "[OK] domain-search jujutsu.K11.com" || { echo "[!!] domain-search salah: $SEARCH"; OK=0; }

echo
if [ "$OK" = 1 ]; then
	echo ">>> HASIL: klien $HOST SESUAI kebijakan."
else
	echo ">>> HASIL: ada ketidaksesuaian, periksa tanda [!!] di atas."
fi
