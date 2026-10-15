#!/bin/bash
# 18-worker-ctl.sh — kendalikan layanan Nginx worker (Soal 18)
# Dipakai untuk mensimulasikan gangguan: hentikan layanan Nginx pada nanami/todo,
# lalu hidupkan kembali.
#
# Pemakaian (jalankan DI node worker, mis. nanami atau todo):
#   ./18-worker-ctl.sh stop
#   ./18-worker-ctl.sh start
#   ./18-worker-ctl.sh status

ACTION="${1:-status}"
PHPV=$(ls /usr/sbin/php-fpm* 2>/dev/null | sed 's#.*/php-fpm##' | head -n1)

start_nginx() {
	nginx -t || exit 1
	nginx
	echo "[+] nginx dijalankan pada $(hostname)"
}

case "$ACTION" in
	stop)
		echo "[*] menghentikan layanan nginx pada $(hostname) ..."
		pkill -f nginx 2>/dev/null || true
		sleep 1
		if pgrep -f nginx >/dev/null; then
			echo "[!] nginx masih berjalan"
		else
			echo "[OK] nginx dihentikan (simulasi gangguan)"
		fi
		;;
	start)
		echo "[*] menghidupkan layanan nginx pada $(hostname) ..."
		if pgrep -f nginx >/dev/null; then
			echo "[i] nginx sudah berjalan"
		else
			start_nginx
		fi
		;;
	status)
		if pgrep -f nginx >/dev/null; then
			echo "[OK] nginx BERJALAN pada $(hostname)"
			pgrep -a nginx | head -2
		else
			echo "[X] nginx MATI pada $(hostname)"
		fi
		;;
	*)
		echo "Pemakaian: $0 {stop|start|status}"
		exit 1
		;;
esac
