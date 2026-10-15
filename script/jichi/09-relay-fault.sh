#!/bin/sh
# jichi — DHCP Relay (Soal 9): simulasi gangguan relay.
# `stop`  : hentikan relay -> klien N2/N3 gagal memperoleh lease.
# `start` : hidupkan lagi    -> klien kembali memperoleh lease dengan gateway semula.
# `status`: tampilkan proses dhcrelay.
#
# Pemakaian: ./09-relay-fault.sh stop|start|status

case "$1" in
	stop)
		echo "[jichi] menghentikan DHCP relay..."
		service isc-dhcp-relay stop || true
		sleep 1
		if pgrep -x dhcrelay >/dev/null 2>&1; then
			echo "[-] dhcrelay masih jalan"
		else
			echo "[OK] relay MATI. Sekarang picu renew di klien (mis. fushiguro):"
			echo "     udhcpc -i eth0 -n -q     -> harus GAGAL ('no lease, failing')."
		fi
		;;
	start)
		echo "[jichi] menghidupkan DHCP relay..."
		service isc-dhcp-relay start || true
		sleep 1
		if pgrep -x dhcrelay >/dev/null 2>&1; then
			echo "[OK] relay HIDUP:"
			ps -ef | grep '[d]hcrelay'
			echo "     Ulangi renew di klien -> lease kembali diperoleh."
		else
			echo "[-] relay gagal start"
		fi
		;;
	status)
		service isc-dhcp-relay status 2>/dev/null || true
		ps -ef | grep '[d]hcrelay' || echo "[-] relay tidak jalan"
		;;
	*)
		echo "pemakaian: $0 stop|start|status"; exit 1 ;;
esac
