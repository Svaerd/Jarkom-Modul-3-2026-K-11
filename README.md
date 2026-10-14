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

**Langkah.** Install `isc-dhcp-relay`, set `SERVERS="10.69.4.10"` dan `INTERFACES="eth2 eth3"`, lalu restart service. Disimpan sebagai script `/root/03-dhcp-relay.sh`:

```sh
cat /root/03-dhcp-relay.sh
```

Isi `/etc/default/isc-dhcp-relay`:

```sh
cat /etc/default/isc-dhcp-relay
```

![](./Attachments/image-15.webp)
> **[Screenshot: `/etc/default/isc-dhcp-relay` pada `jichi`]**

Proses `dhcrelay` aktif pada `eth2` & `eth3`:

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
