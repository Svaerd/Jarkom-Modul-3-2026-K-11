#!/bin/sh
# tengen — DHCP Server (Soal 7): rekap lease + cocokkan dengan kebijakan pool.
# Menampilkan /var/lib/dhcp/dhcpd.leases, lalu memverifikasi tiap MAC client:
# Pool1 (.2.10-.2.35), Pool2 (.2.70-.2.95), N3 short (.3.10-.3.89),
# N3 long (.3.100-.3.199), fixed kugisaki (.3.99). Prefix internal 10.69.

LEASES=/var/lib/dhcp/dhcpd.leases

echo "=============================================="
echo " Lease aktif di $HOSTNAME  ($(date '+%F %T'))"
echo "=============================================="
# ringkas: alamat + MAC + selisih starts/ends (cetak saat blok lease ditutup)
awk '
/^lease / { ip=$2; mac=""; s=""; e="" }
/hardware ethernet/ { mac=$3; gsub(/;/,"",mac) }
/^  starts/ { s=$3" "$4; gsub(/;/,"",s) }
/^  ends/   { e=$3" "$4; gsub(/;/,"",e) }
/^}/ { if (ip!="") printf "%-15s  %-17s  starts %s  ends %s\n", ip, mac, s, e; ip="" }
' "$LEASES"

echo
echo "=============================================="
echo " Pemeriksaan kebijakan"
echo "=============================================="
# MAC -> label + rentang IP valid
check() {
	mac=$1; label=$2; net=$3; lo=$4; hi=$5
	ip=$(awk -v m="$mac" '
		/^lease / { c=$2 }
		/hardware ethernet/ { gsub(/;/,"",$3); if ($3==m) print c }
	' "$LEASES" | tail -n1)
	if [ -z "$ip" ]; then
		printf '%-12s %-17s  [--] belum ada lease\n' "$label" "$mac"
		return
	fi
	last=${ip##*.}
	case "$ip" in
		10.69.$net.*) r="subnet OK" ;;
		*) r="SUBNET SALAH" ;;
	esac
	if [ "$last" -ge "$lo" ] && [ "$last" -le "$hi" ]; then
		r="$r, dalam rentang OK"
	else
		r="$r, DI LUAR rentang $lo-$hi"
	fi
	printf '%-12s %-17s  %-15s  %s\n' "$label" "$mac" "$ip" "$r"
}

check 02:42:47:5c:e2:00 itadori   2 10 35
check 02:42:de:fd:46:00 fushiguro 2 10 35
check 02:42:90:6f:b5:00 zenin     2 70 95
check 02:42:86:db:d5:00 okkotsu   2 70 95
check 02:42:a6:05:0a:00 ino       3 10 89
check 02:42:65:06:75:00 kusakabe  3 10 89
check 02:42:53:b6:7e:00 miwa      3 100 199
check 02:42:69:c1:4e:00 kugisaki  3 99 99

echo
echo "=============================================="
echo " Rentang terlarang N2: 10.69.2.36-10.69.2.69"
echo " (tidak boleh muncul sebagai lease di atas)"
echo "=============================================="
if awk '
	/^lease 10\.69\.2\./ { split($2,a,"."); if (a[4]>=36 && a[4]<=69) found=1 }
	END { exit found ? 0 : 1 }
' "$LEASES"; then
	echo "[!!] ada lease di rentang terlarang"
else
	echo "[OK] tidak ada lease di rentang terlarang"
fi
