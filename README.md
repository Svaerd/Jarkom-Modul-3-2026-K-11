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

