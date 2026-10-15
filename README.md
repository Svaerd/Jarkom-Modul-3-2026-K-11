# Jarkom-Modul-3-2026-K-11

Laporan Praktikum Modul 3 — Komunikasi Data & Jaringan Komputer 2026
**Curtain Protocol: Shibuya Incident — Pemulihan Jaringan dan Layanan Jujutsu High**

Anggota Kelompok K-11:

- Hasheemi Rafsanjani (5027251015)
- Husam Danish (5027251060)

Konvensi: prefix jaringan internal `10.69.x.x`, netmask `/24`, domain `jujutsu.K11.com`.

## Soal 1 — Konektivitas Dasar dan Routing `jichi`

**Tujuan.** Memulihkan konektivitas antar-zona. `jichi` berperan sebagai router utama: antarmuka `eth0` memperoleh WAN dari NAT, sedangkan `eth1`–`eth4` menjadi gateway **Network 1–4**. IPv4 forwarding dan source NAT (masquerade) diaktifkan, lalu setiap host infrastruktur diberi IP statis sesuai rancangan.

**Pemetaan interface `jichi`:**

| Interface | Peran | Alamat |
|-----------|-------|--------|
| `eth0`   | WAN (DHCP dari NAT1) | `192.168.122.207/24` |
| `eth1`   | Gateway Network 1 (DMZ) | `10.69.1.1/24` |
| `eth2`   | Gateway Network 2 (Klien Divisi A) | `10.69.2.1/24` |
| `eth3`   | Gateway Network 3 (Klien Divisi B) | `10.69.3.1/24` |
| `eth4`   | Gateway Network 4 (Data Center) | `10.69.4.1/24` |

### 1.1 Konfigurasi Interface `jichi`

Konfigurasi `/etc/network/interfaces` pada `jichi`:

```sh
cat /etc/network/interfaces
```

![](./Attachments/image-5.webp)
> **[Screenshot: `/etc/network/interfaces` pada `jichi`]**

### 1.2 Aktifkan IPv4 Forwarding dan Source NAT

Diaktifkan melalui script `/root/01-setup-routing.sh`:

```sh
....
iptables -t nat -F POSTROUTING 2>/dev/null || true
iptables -F FORWARD 2>/dev/null || true

iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
for i in 1 2 3 4; do
	iptables -A FORWARD -i eth$i -o eth0 -j ACCEPT
done
for i in 1 2 3 4; do
	iptables -A FORWARD -i eth0 -o eth$i -m state --state ESTABLISHED,RELATED -j ACCEPT
done
....
```

yang kemudian akan menghasilkan seperti ini:
```sh
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth2 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth3 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth4 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o eth1 -m state --state ESTABLISHED,RELATED -j ACCEPT
```

Hasil `ip addr show` pada `jichi` (semua interface naik dengan alamat benar):
![|500](./Attachments/image-1.webp)

IPv4 forwarding aktif:
```sh
cat /proc/sys/net/ipv4/ip_forward
```

![ip_forward = 1](./Attachments/image-2.webp)

Aturan masquerade pada tabel NAT:
```sh
iptables -t nat -L POSTROUTING -v -n
```

![MASQUERADE pada POSTROUTING](./Attachments/image-3.webp)

### 1.3 Verifikasi Gateway (`jichi` → NAT)

`jichi` dapat menjangkau gateway NAT `192.168.122.1`:
```sh
ping -c3 192.168.122.1
```

![](./Attachments/image-6.webp)

### 1.4 Verifikasi IPv4 Forwarding

Forwarding diuji dari host infrastruktur menuju gateway network-nya. Contoh pada `tengen` (Network 4):
```sh
ping -c3 10.69.4.1
```

Dan dari host klien/infrastruktur melalui masquerade `jichi` — contoh `tengen` (Network 4):

```sh
ping -c3 1.1.1.1
```
![ping gateway dan cloudflare dari tengen](./Attachments/image-4.webp)

Pada `Utahime`
![](./Attachments/image-7.webp)
> **[Screenshot: `ping -c3 10.69.1.1` dari `utahime` (Network 1)]**

![](./Attachments/image-10.webp)
> **[Screenshot: `ping -c3 1.1.1.1` dari `utahime` (Network 1)]**

### 1.5 Verifikasi Akses Eksternal (Masquerading)

Akses eksternal dibuktikan dari `jichi` sendiri:
```sh
ping -c3 192.168.122.1
ping -c3 8.8.8.8
```
![akses eksternal dari jichi](./Attachments/image.webp)

### 1.6 IP Statis Host Infrastruktur

Selain `jichi`, host infrastruktur diberi IP statis. Disimpan sebagai script di `/root` tiap node. Rancangan:

| Network | Host | Alamat | Gateway |
|---------|------|--------|---------|
| 1 | `utahime` (DNS master) | `10.69.1.2/24` | `10.69.1.1` |
| 1 | `shoko` (DNS slave) | `10.69.1.3/24` | `10.69.1.1` |
| 1 | `gojo` (reverse proxy) | `10.69.1.4/24` | `10.69.1.1` |
| 4 | `geto` (internal LB) | `10.69.4.2/24` | `10.69.4.1` |
| 4 | `maki` (worker web) | `10.69.4.3/24` | `10.69.4.1` |
| 4 | `panda` (worker web) | `10.69.4.4/24` | `10.69.4.1` |
| 4 | `nanami` (worker API) | `10.69.4.5/24` | `10.69.4.1` |
| 4 | `todo` (worker API) | `10.69.4.6/24` | `10.69.4.1` |
| 4 | `kirara` (worker API cadangan) | `10.69.4.7/24` | `10.69.4.1` |
| 4 | `yaga` (DB master) | `10.69.4.8/24` | `10.69.4.1` |
| 4 | `inumaki` (DB slave) | `10.69.4.9/24` | `10.69.4.1` |
| 4 | `tengen` (DHCP server) | `10.69.4.10/24` | `10.69.4.1` |

Contoh bukti IP statis pada host Network 1 (`utahime`) dan host Network 4 (`tengen`):

```sh
ip -br addr
```

![](./Attachments/image-8.webp)
> **[Screenshot: `ip -br addr` pada `utahime` (Network 1)]**

![](./Attachments/image-9.webp)
> **[Screenshot: `ip -br addr` pada `tengen` (Network 4)]**

---

## Soal 2 — DHCP Server `tengen`

**Tujuan.** `tengen` (Data Center, `10.69.4.10`) menjadi DHCP server. Network 4 dideklarasikan sebagai **subnet lokal tanpa pool dinamis**, sedangkan scope untuk **Network 2** dan **Network 3** disiapkan agar permintaan dari kedua subnet dapat dilayani. Service harus aktif tanpa error **“No subnet declaration”**.

**Langkah.** Install `isc-dhcp-server`, set `INTERFACESv4="eth0"`, tulis `/etc/dhcp/dhcpd.conf` berisi tiga deklarasi `subnet` (N4 lokal, N2 dan N3 untuk relay), lalu validasi dan restart service. Disimpan sebagai script `/root/02-dhcp-server.sh`:

```sh
cat /root/02-dhcp-server.sh
```

Isi `/etc/dhcp/dhcpd.conf`:

```sh
cat /etc/dhcp/dhcpd.conf
```

![](./Attachments/image-11.webp)
> **[Screenshot: `/etc/dhcp/dhcpd.conf` pada `tengen`]**

Validasi konfigurasi:

```sh
dhcpd -t -cf /etc/dhcp/dhcpd.conf
```

![](./Attachments/image-12.webp)
> **[Screenshot: output `dhcpd -t` tanpa error]**

Status service aktif:

```sh
service isc-dhcp-server status
```
![](./Attachments/image-13.webp)
> **[Screenshot: `isc-dhcp-server` aktif]**

Pesan startup dhcpd (termasuk bila ada “No subnet declaration”) tak masuk syslog karena image debinet tanpa syslog daemon — tampil di console saat restart:

```sh
service isc-dhcp-server restart
```

![](./Attachments/image-14.webp)
> **[Screenshot: output restart tanpa “No subnet declaration”]**

---

## Soal 3 — DHCP Relay `jichi`

**Tujuan.** Permintaan alamat dari Divisi A dan Divisi B tidak dapat menyeberangi subnet secara langsung. `jichi` dikonfigurasi sebagai **DHCP Relay** menuju `tengen` (`10.69.4.10`), memakai `eth2` untuk Network 2 dan `eth3` untuk Network 3. Client dari kedua subnet harus berhasil memperoleh lease melalui relay.

**Langkah.** Install `isc-dhcp-relay`, set `SERVERS="10.69.4.10"` dan `INTERFACES="eth2 eth3 eth4"` (`eth4` = sisi server `tengen`, tanpa ini balasan DHCP tak kembali), lalu restart service. Disimpan sebagai script `/root/03-dhcp-relay.sh`:

```sh
cat /root/03-dhcp-relay.sh
```

Isi `/etc/default/isc-dhcp-relay`:

```sh
cat /etc/default/isc-dhcp-relay
```

![](./Attachments/image-15.webp)
> **[Screenshot: `/etc/default/isc-dhcp-relay` pada `jichi`]**

Proses `dhcrelay` aktif pada `eth2`, `eth3`, & `eth4`:

```sh
ps -ef | grep dhcrelay
```

![](./Attachments/image-16.webp)
> **[Screenshot: proses `dhcrelay` berjalan]**

Bukti relay berjalan (client N2 mengirim DISCOVER):

```sh
tcpdump -i eth2 -n port 67 or port 68
```

![](./Attachments/image-17.webp)
> **[Screenshot: `tcpdump` pada `jichi` (eth2) — `DHCPDISCOVER` dari client Network 2]**

Client Network 2 tidak memperoleh lease karena pool DHCP belum dikonfigurasi (akan diisi pada Soal 4–5). Bukti pada client N2 dan N3 saat ini: 

N2:
![](./Attachments/image-20.webp)

N3:
![](./Attachments/image-21.webp)

**Bukti relay berhasil meneruskan ke server DHCP (`10.69.4.10`)**

```sh
tcpdump -i eth0 -n port 67 -vv
```
![]()
> **[Screenshot: `tcpdump` pada `tengen` (eth0) — `DHCPDISCOVER` dari subnet N2/N3 dengan `giaddr` = `10.69.2.1` (N2) dan `10.69.3.1` (N3)]**

Pada sisi `tengen`, terlihat `DHCPDISCOVER` yang diteruskan oleh `dhcrelay` dari `jichi` (`10.69.4.1`), dengan `Gateway-IP` (giaddr) sesuai subnet client. Tanpa pool DHCP yang diaktifkan, dhcpd tidak mengirim `DHCPOFFER`. Oleh karena itu, dapat disimpulkan bahwa **relay telah berjalan sesuai konfigurasi** — hanya `pool` untuk N2 dan N3 yang belum ditambahkan (akan dilakukan pada Soal 4–5).

---

## Soal 4 — DHCP Pool & Class Network 2

**Tujuan.** Membagi pool N2: Pool 1 (`10.69.2.10–10.69.2.35`) untuk `itadori`, `fushiguro`; Pool 2 (`10.69.2.70–10.69.2.95`) untuk `zenin`, `okkotsu`. Rentang `10.69.2.36–10.69.2.69` dilarang. Pisahkan menggunakan **DHCP class** berdasarkan MAC.

Script: `/root/04-dhcp-n2.sh` (disimpan di `script/tengen/04-dhcp-n2.sh`).

Konfigurasi `/etc/dhcp/dhcpd.conf` (bagian N2):

```sh
cat /etc/dhcp/dhcpd.conf
```

![](./Attachments/image-22.webp)
> **[Screenshot: konfigurasi pool & class N2 pada `tengen`]**

Validasi:

```sh
dhcpd -t -cf /etc/dhcp/dhcpd.conf
service isc-dhcp-server restart
service isc-dhcp-server status
```

![](./Attachments/image-23.webp)
> **[Screenshot: validasi + status `isc-dhcp-server` setelah Soal 4]**

Verifikasi client N2 memperoleh lease sesuai pool:

```sh
# itadori & fushiguro -> 10.69.2.10–.35; zenin & okkotsu -> 10.69.2.70–.95
ip -br addr
```

`itadori`
![](./Attachments/image-24.webp)

`fushiguro`
![](./Attachments/image-25.webp)

`zenin`
![](./Attachments/image-26.webp)

`okkotsu`
![](./Attachments/image-27.webp)

> **[Screenshot: `ip -br addr` client N2]**

> **Catatan (perbaikan).** Nilai `subclass` wajib diawali `1:` (tipe hardware Ethernet). Client mengirim DHCP **Client-ID** `ether 02:42:...`, yaitu byte `01:02:42:...`, jadi penulisannya `subclass "pool1-n2" 1:02:42:47:5c:e2:00;`. Tanpa prefix `1:`, kelas tak cocok (`pick-first-value` mengembalikan Client-ID 7-byte), `dhcpd -d` mencatat `network 10.69.2.0/24: no free leases`, dan client tak menerima lease.

---


**Tujuan.** N3: `ino`, `kusakabe` short lease **1800s** (pool `.3.10–.3.89`); `miwa` long lease **43200s** (pool `.3.100–.3.199`). Atur `default-lease-time`/`max-lease-time` per kelas. Tambah DNS `10.69.1.2,10.69.1.3` + `domain-search jujutsu.K11.com`.

Script: `/root/05-dhcp-n3.sh` (`script/tengen/05-dhcp-n3.sh`).

Konfigurasi N3 di `/etc/dhcp/dhcpd.conf`:

```sh
cat /etc/dhcp/dhcpd.conf
```
![]()
> **[Screenshot: konfigurasi N3 (short/long + domain-search) pada `tengen`]**

Verifikasi lease time (contoh):

```sh
cat /var/lib/dhcp/dhcpd.leases | grep -A 20 -B 5 'ino\|kusakabe\|miwa'
```
![]()
> **[Screenshot: `dhcpd.leases` menunjukkan `lease-time` 1800 / 43200]**

---

## Soal 6 — Static Lease Kugisaki `.3.99`

**Tujuan.** `kugisaki` static lease berdasarkan MAC → `10.69.3.99` (di luar seluruh pool).

Bagian `host kugisaki { hardware ethernet ...; fixed-address 10.69.3.99; }` sudah disertakan di script Soal 5.

Verifikasi:

```sh
cat /etc/dhcp/dhcpd.conf | grep -A 10 'host kugisaki'
service isc-dhcp-server restart; dhcpd -t
```
![]()
> **[Screenshot: konfigurasi static lease `kugisaki` + validasi]**

Cek lease di client `kugisaki`:

```sh
ip -br addr
```
![]()
> **[Screenshot: `ip -br addr` `kugisaki` menunjukkan `10.69.3.99/24`]**

Cek di `/var/lib/dhcp/dhcpd.leases`:

```sh
cat /var/lib/dhcp/dhcpd.leases | grep -B 5 -A 15 '02:42:69:c1:4e'
```
![]()
> **[Screenshot: `dhcpd.leases` menandakan fixed address untuk MAC kugisaki]**

---

## Soal 7 — Verifikasi Konfigurasi Per-Client

**Tujuan.** Pastikan setiap client N2–N3 menerima: mask `/24`, gateway & broadcast benar, DNS `10.69.1.2,10.69.1.3`, domain-search sesuai. Cocokkan lease dengan `/var/lib/dhcp/dhcpd.leases` di `tengen`. Tidak ada tabrakan atau IP di luar kebijakan pool.

Verifikasi routing & info (contoh untuk beberapa client):

```sh
for h in itadori fushiguro zenin okkotsu ino kusakabe miwa kugisaki; do
  echo "=== $h ==="; ssh -o StrictHostKeyChecking=no $h 'ip -br addr; ip route; cat /etc/resolv.conf'
done 2>/dev/null
```
![]()
> **[Screenshot: snapshot `ip addr`, `ip route`, `resolv.conf` seluruh client Divisi A & B]**

Cross-check dengan leases:

```sh
cat /var/lib/dhcp/dhcpd.leases
```
![]()
> **[Screenshot: keseluruhan lease aktif di `tengen`]**

---

## Soal 8 — Packet Capture DORA + giaddr

**Tujuan.** Buktikan urutan **DHCPDISCOVER → DHCPOFFER → DHCPREQUEST → DHCPACK** saat client minta lease baru. Tunjukkan `giaddr` sesuai interface `jichi` dari subnet client.

Re-packet capture saat renew:

```sh
# jichi (sisi client ke relay)
tcpdump -i eth2 -n port 67 or port 68 -vv
# atau di tengen (sisi relay ke server)
tcpdump -i eth0 -n port 67 -vv
```
![]()
> **[Screenshot: tcpdump menunjukkan urutan DORA lengkap, field `giaddr` = `10.69.2.1`/`10.69.3.1`]**

Identifikasi: server IP (`10.69.4.10`), IP yang diberikan (sesuai pool/reservasi), lease time, `giaddr`.

---

## Soal 9 — Gangguan Relay

**Tujuan.** Hentikan DHCP Relay di `jichi` → client gagal lease. Hidupkan kembali → lease benar.

Lakukan pada `jichi`:
```sh
service isc-dhcp-relay stop
```

Paksa renew client (contoh Network 2):
```sh
# di client (alpinet) bisa pakai udhcpc -n -q atau restart interface
# atau: dhclient -r eth0; dhclient eth0
```
![]()
> **[Screenshot: gagal memperoleh lease saat relay dihentikan]**

Hidupkan relay:
```sh
service isc-dhcp-relay start
```
Ulangi renew → lease kembali normal:
![]()
> **[Screenshot: berhasil memperoleh lease kembali setelah relay dihidupkan]**

---

## Soal 10 — Autostart + Restart Node

**Tujuan.** Autostart DHCP Server (`tengen`) dan DHCP Relay (`jichi`); restart kedua node; verifikasi semua kebijakan tetap berlaku.

Cek autostart:
```sh
# tengen
systemctl is-enabled isc-dhcp-server 2>/dev/null; update-rc.d -n isc-dhcp-server defaults 2>/dev/null
# jichi
systemctl is-enabled isc-dhcp-relay 2>/dev/null; update-rc.d -n isc-dhcp-relay defaults 2>/dev/null
```
![]()
> **[Screenshot: status autostart DHCP server & relay]**

Restart node (GNS3/CLI). Setelah restart, verifikasi:
```sh
service isc-dhcp-server status; service isc-dhcp-relay status
```
![]()
> **[Screenshot: layanan aktif setelah restart]**

Verifikasi lease client (pool1/pool2, short/long, fixed .3.99), IP/gateway/DNS/domain-search:
![]()
> **[Screenshot: verifikasi akhir Soal 10]**

> **Catatan (persistensi antar-restart).** Setiap node menjalankan `/root/<node>.sh` saat boot melalui baris `up bash /root/<node>.sh` di `/etc/network/interfaces` — `tengen.sh` menjalankan `02`+`04`+`05`, `jichi.sh` menjalankan `01`+`03`. File `/root` tersimpan pada volume node sehingga konfigurasi DHCP otomatis diterapkan ulang setiap restart. Helper `push_configs.py` (root repo) men-deploy ulang script `/root` dan config `/etc` via console node bila perlu.

## Soal 11 — DNS Master `utahime` & DNS Slave `shoko`

**Tujuan.** Membangun sistem penamaan domain `jujutsu.K11.com` agar setiap pos tidak perlu menghafal IP mentah. `utahime` (`10.69.1.2`) menjadi **DNS Master** dan `shoko` (`10.69.1.3`) menjadi **DNS Slave** dengan BIND9. Zona berisi **SOA record**, **NS delegasi** untuk kedua server (`ns1` = utahime, `ns2` = shoko), dan **allow-transfer** dari master hanya ke slave. Saat nomor **serial** di master dinaikkan, file zona harus tersinkronisasi otomatis ke slave.

**Skema.** Kedua node berada di Network 1 (DMZ) dan dijalankan sebagai container `debinet` (tanpa systemd), sehingga `named` dijalankan langsung (`nohup named -f`) alih-alih lewat `service`.

| Host | IP | Peran | NS |
|------|----|-------|----|
| `utahime` | `10.69.1.2` | DNS Master | `ns1.jujutsu.K11.com` |
| `shoko`   | `10.69.1.3` | DNS Slave  | `ns2.jujutsu.K11.com` |

### 11.1 Konfigurasi DNS Master (`utahime`)

Script `/root/11-dns-master.sh` memasang `bind9`, menulis `named.conf.options`, `named.conf.local`, dan file zona, lalu menjalankan `named`. Bagian penting:

```sh
zone "jujutsu.K11.com" {
	type master;
	file "/etc/bind/zones/db.jujutsu.K11.com";
	allow-transfer { 10.69.1.3; };   # hanya slave shoko
	notify yes;
	also-notify { 10.69.1.3; };
};
```

File zona memuat SOA, delegasi NS, dan glue A record kedua NS:

```sh
@       IN      SOA     ns1.jujutsu.K11.com. admin.jujutsu.K11.com. (
			1         ; Serial
			604800    ; Refresh
			86400     ; Retry
			2419200   ; Expire
			604800 )  ; Negative Cache TTL
;
@       IN      NS      ns1.jujutsu.K11.com.
@       IN      NS      ns2.jujutsu.K11.com.
ns1     IN      A       10.69.1.2
ns2     IN      A       10.69.1.3
```

![](./Attachments/image-15.webp)
> **[Screenshot: script `11-dns-master.sh` di `/root` + `named` berjalan pada `utahime`]**

### 11.2 Konfigurasi DNS Slave (`shoko`)

Script `/root/11-dns-slave.sh` mendeklarasikan zona bertipe **slave** yang mengambil salinan dari master (file zona tidak dibuat manual):

```sh
zone "jujutsu.K11.com" {
	type slave;
	file "/var/cache/bind/db.jujutsu.K11.com";
	masters { 10.69.1.2; };
	allow-notify { 10.69.1.2; };
};
```

![](./Attachments/image-16.webp)
> **[Screenshot: script `11-dns-slave.sh` di `/root` + file zona hasil transfer di `shoko`]**

### 11.3 Verifikasi Query `dig` dari Client (`itadori`)

Dari `itadori` (klien Network 2, DHCP `10.69.2.10/24`) dilakukan query ke **kedua** server. SOA dan NS dilayani oleh master maupun slave:

```sh
dig @10.69.1.2 jujutsu.K11.com SOA +short   # dari master
dig @10.69.1.3 jujutsu.K11.com SOA +short   # dari slave
dig @10.69.1.2 jujutsu.K11.com NS +short
```

![](./Attachments/image-17.webp)
> **[Screenshot: `dig` SOA & NS ke master dan slave dari `itadori`]**

### 11.4 Bukti Sinkronisasi Otomatis (Naikkan Serial)

Serial dinaikkan di master (`./11-dns-master.sh bump`, serial `1` → `2`). Notify dikirim ke slave, dan zona tersinkronisasi otomatis — query ke **slave** pun menampilkan serial baru:

```sh
# di utahime
./11-dns-master.sh bump
# di itadori
dig @10.69.1.3 jujutsu.K11.com SOA +short
# -> ns1.jujutsu.K11.com. admin.jujutsu.K11.com. 2 604800 86400 2419200 604800
```

![](./Attachments/image-18.webp)
> **[Screenshot: serial slave ikut naik menjadi 2 setelah bump di master]**

Sebagai bukti tambahan bahwa `allow-transfer` hanya berlaku untuk slave, transfer zona dari client **ditolak**:

```sh
dig @10.69.1.2 jujutsu.K11.com AXFR   # Transfer failed.
```

---

## Soal 12 — A Record, CNAME, Reverse DNS (PTR), dan DNS Forwarder

**Tujuan.** Peta domain harus memetakan pintu masuk utama sekaligus tetap bisa mencari alamat di luar kawasan. Pada `utahime` ditambahkan **A record** `jujutsu.K11.com` yang mengarah ke `gojo`, **CNAME** `www` yang merujuk ke domain utama, **zona PTR** untuk melacak IP `gojo` kembali ke domain resminya, dan **DNS Forwarder** ke gateway internet `192.168.122.1`. Zona PTR ikut disinkronkan ke slave `shoko`.

**Ringkasan record yang ditambahkan:**

| Nama | Tipe | Nilai |
|------|------|-------|
| `jujutsu.K11.com` | A | `10.69.1.4` (gojo) |
| `www.jujutsu.K11.com` | CNAME | `jujutsu.K11.com.` |
| `4.1.69.10.in-addr.arpa` | PTR | `jujutsu.K11.com.` |

### 12.1 Konfigurasi Master (`utahime`)

Script `/root/12-domain-ptr-forwarder.sh` menulis ulang zona forward dan menambah zona reverse, lalu mengaktifkan forwarder:

```sh
options {
	forwarders { 192.168.122.1; };   # gateway internet
	recursion yes;
	dnssec-validation no;
};
```

Isi zona forward (tambahan Soal 12):

```sh
@       IN      A       10.69.1.4          ; pintu masuk utama -> gojo
www     IN      CNAME   jujutsu.K11.com.  ; alias www -> domain utama
```

Zona reverse `1.69.10.in-addr.arpa`:

```sh
@       IN      SOA     ns1.jujutsu.K11.com. admin.jujutsu.K11.com. ( ... )
@       IN      NS      ns1.jujutsu.K11.com.
@       IN      NS      ns2.jujutsu.K11.com.
4       IN      PTR     jujutsu.K11.com.  ; 10.69.1.4 -> jujutsu.K11.com
```

![](./Attachments/image-19.webp)
> **[Screenshot: zona forward + PTR + forwarder pada `utahime`]**

### 12.2 Zona PTR pada Slave (`shoko`)

`shoko` mendeklarasikan **dua** zona slave (forward + reverse) sehingga keduanya ikut tersinkron otomatis dari master:

```sh
zone "1.69.10.in-addr.arpa" {
	type slave;
	file "/var/cache/bind/db.1.69.10";
	masters { 10.69.1.2; };
	allow-notify { 10.69.1.2; };
};
```

![](./Attachments/image-20.webp)
> **[Screenshot: file zona hasil transfer (`db.jujutsu.K11.com` dan `db.1.69.10`) di `shoko`]**

### 12.3 Verifikasi dari Client (`itadori`)

Dari `itadori` diuji A record, CNAME, PTR, dan forwarder di **kedua** server:

```sh
dig @10.69.1.2 jujutsu.K11.com A +short          # -> 10.69.1.4
dig @10.69.1.2 www.jujutsu.K11.com CNAME +short  # -> jujutsu.K11.com.
dig @10.69.1.2 -x 10.69.1.4 +short               # -> jujutsu.K11.com.
dig @10.69.1.2 google.com A +short               # -> (via forwarder)
```

Hasil: A record mengarah ke `10.69.1.4` baik di master maupun slave, `www` menunjuk `jujutsu.K11.com.` lalu resolve ke `10.69.1.4`, dan PTR `10.69.1.4` mengembalikan `jujutsu.K11.com.`.

Client juga tetap dapat menjangkau alamat di luar kawasan: resolusi `google.com` diteruskan forwarder ke `192.168.122.1`, dan ping berhasil.

```sh
ping -c 3 google.com
# 3 packets transmitted, 3 received, 0% packet loss
```

![](./Attachments/image-21.webp)
> **[Screenshot: `dig` A/CNAME/PTR dan `ping google.com` dari `itadori`]**

---
