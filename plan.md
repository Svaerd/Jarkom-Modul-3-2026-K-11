# plan.md — Modul 3 K-11 (Curtain Protocol: Shibuya Incident)

Rencana pengerjaan Modul 3. Kerjakan berurutan; tiap fase = satu commit + update `README.md`.

## Prasyarat

- Telah dikonfirmasi prefix IP dari Master Sheet = 10.69.x.x
- Telah dikonfirmasi `<xxxx>` = `K11`.
- Buka GNS3 client → remote server `10.4.89.246:80` (user `K-11`). Cek apakah project Modul 3 sudah ada; kalau belum, buat baru (`K11-Modul-3-2026`). Harusnya sudah ada, dengan nama `K-11-MODUL-3`
- Pastikan image `ardhptr21/debinet:latest` + `ardhptr21/alpinet:latest` tersedia di server.

## Dependency — urutan minimal

**1-10 tidak harus kelar semua** sebelum 11-20. Yang mengunci hanya **soal 1**.

```
1 (routing/NAT — gate semua)
├─ 11,12 (DNS utahime/shoko)      ← butuh 1 (host N1 statis)
├─ 13 (DB yaga/inumaki)           ← butuh 1 (host N4 statis)
└─ 14 (worker web+API)            ← butuh 13
   └─ 15 (geto LB)                ← butuh 14
      ├─ 16 (gojo path routing)   ← butuh 14+15 (+11,12 buat domain)
      │  ├─ 17 (X-Forwarded + client_ip) ← butuh 13+16
      │  └─ 19 (cache + rate limit)      ← butuh 16
      └─ 18 (kirara backup)       ← butuh 15
20 (benchmark dari kusakabe)      ← butuh 2,3 (client IP) + 11,12 + 16
```

Independen / bukan prasyarat 11-20: **6, 7, 8, 9, 10**.

| tujuan | minimal dikerjakan |
|---|---|
| mulai 11-13 / kerja infra | **1** |
| test 11-20 lewat client (12,14,17,20) | **1 + 2 + 3** |
| client dapat IP sesuai kebijakan soal | **1 + 2 + 3 + 4 + 5** |

Realistis: kerjakan **1-5** dulu (routing + DHCP lengkap), lalu lompat ke 11. Simpan 6-10 untuk interleave/akhir.

## Fase 0 — Topologi dasar

- Buat 1 router (`jichi`) + 4 network switch, dan semua node sesuai glosarium.
- Pasang link: `jichi` eth0→NAT, eth1..eth4→Network 1..4.
- Verifikasi: semua node hidup, nama sesuai soal.
- Harusnya fase 0 ini sudah selesai

## Fase 1 — Soal 1: routing & IP dasar

- `jichi` eth0 DHCP dari NAT; eth1–eth4 gateway `.N.1` /24.
- Aktifkan `net.ipv4.ip_forward=1` + source NAT (iptables MASQUERADE ke eth0).

```
auto eth0
iface eth0 inet dhcp
	up sysctl -w net.ipv4.ip_forward=1
	up iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
	up iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
	up iptables -A FORWARD -i eth2 -o eth0 -j ACCEPT
	up iptables -A FORWARD -i eth0 -m state --state ESTABLISHED,RELATED -j ACCEPT
```

- Set IP statis semua host infrastruktur.
- Test: ping host→gateway + akses eksternal dari host relevan.
- Script: `script/jichi/setup-routing.sh`.

## Fase 2 — Soal 2–10: DHCP

- **S2** `tengen` (`.4.10`) isc-dhcp-server: Network 4 subnet lokal tanpa pool; scope Network 2 & 3; pastikan service aktif tanpa "No subnet declaration".
- **S3** `jichi` DHCP relay → `tengen`, eth2 (N2), eth3 (N3).
- **S4** 2 pool N2: Pool1 `.2.10–.2.35` (itadori, fushiguro), Pool2 `.2.70–.2.95` (zenin, okkotsu); `.2.36–.2.69` dilarang; pisah pakai `dhcp-class` by MAC/Client-ID.
- **S5** N3 lease: ino+kusakabe short 1800s, miwa long 43200s; pool short `.3.10–.3.89`, long `.3.100–.3.199`; DHCP option DNS `.1.2`+`.1.3`, domain-search `<xxxx>.com`.
- **S6** `kugisaki` static lease by MAC → fixed `.3.99`.
- **S7** cek semua client: mask /24, gateway, broadcast, DNS, domain-search; cocokkan lease dengan `/var/lib/dhcp/dhcpd.leases` di tengen.
- **S8** tcpdump DHCP DORA di `tengen`; tunjukkan `giaddr` = interface jichi di subnet client.
- **S9** matikan relay → client gagal lease → hidupkan → lease kembali benar; catat gejala.
- **S10** autostart DHCP server (tengen) + relay (jichi); restart node; verifikasi semua kebijakan tetap berlaku.
- Script: `script/tengen/`, `script/jichi/` (relay).

> **Catatan audit (diakui, sengaja tidak diperbaiki di Soal 1–10):**
> - BIND9 (`utahime`/`shoko`) memakai `allow-query { any; }` + `recursion yes;` → open resolver. Aman untuk lab GNS3 tertutup; untuk produksi tambahkan `allow-recursion { 127.0.0.1; 10.69.0.0/16; };`. Di luar lingkup Soal 1–10.
> - `subnet` N2/N3 dideklarasikan di Soal 2 lalu diulang di Soal 4–5 → peringatan `overlaps` non-fatal dari `dhcpd`; dipertahankan agar tiap script per-soal tetap terpisah dan Soal 2 tetap sesuai permintaan soal.

## Fase 3 — Soal 11–12: DNS

- **S11** BIND9 `utahime` master + `shoko` slave domain `jujutsu.<xxxx>.com`; SOA, NS, allow-transfer; uji sinkron via naikkan serial + `dig`.
- **S12** A record `jujutsu.<xxxx>.com`→gojo, CNAME `www`; zona PTR reverse gojo; DNS forwarder → `192.168.122.1`; uji `dig` CNAME/PTR + ping `google.com`.
- Script: `script/utahime/`, `script/shoko/`.

## Fase 4 — Soal 13: database

- MariaDB `yaga` = master, `inumaki` = slave.
- DB `db_shibuya_<xxxx>`, tabel `request_logs`; aktifkan log-bin + server-id; `CHANGE MASTER TO`; grant remote semua node N4; uji replikasi.
- Script: `script/yaga/`, `script/inumaki/`.

## Fase 5 — Soal 14: worker web & API

- `maki`, `panda`: Nginx + PHP-FPM, tampilkan hostname; vhost domain layanan.
- `nanami`, `todo`, `kirara`: API yang log request ke DB yaga.
- Batasi akses langsung client; web worker hanya via gojo; worker API hanya via geto. Uji direct ditolak, via proxy OK.

## Fase 6 — Soal 15 & 18: load balancer geto

- Nginx `geto`: upstream `api_cluster` → nanami + todo, Weighted RR **3:1**.
- **S18** `kirara` = backup server; passive health check `max_fails=2 fail_timeout=5s`; simulasikan mati → request dialihkan ke kirara, tanpa 502.

## Fase 7 — Soal 16, 17, 19: gojo reverse proxy

- **S16** nginx `gojo`: domain `jujutsu.<xxxx>.com` + `www.` ; Path-based: `/` → RR maki/panda, `/api` → geto.
- **S17** header `X-Real-IP` + `X-Forwarded-For` di gojo→geto; geto hanya percaya proxy terpercaya; API simpan `client_ip` terverifikasi ke `request_logs`.
- **S19** proxy cache halaman web 10 menit + `X-Cache-Status` (MISS→HIT); rate limit `/api` 10 req/s per IP.

## Fase 8 — Soal 20: benchmark & finalisasi

- Dari `kusakabe`: `ab -n 600 -c 30 http://jujutsu.<xxxx>.com/`; catat RPS/latensi/gagal.
- Uji `/api` + efek rate limiting; bandingkan baseline vs aktif; analisis access log gojo.
- Finalisasi: rapikan `script/`, update README.md (per bagian soal), backup config, export `.gns3project`, submit ke form asisten.

## Deliverable checklist

- [ ] Semua script ada di `script/` dan di `/root` tiap node
- [ ] `K11_gns3_export.gns3project` (atau nama sesuai konvensi) di root repo
- [ ] README.md laporan lengkap (20 soal + screenshot/test)
- [ ] Backup config di luar GNS3 (docs/md/sh)
- [ ] Submit via link form di soal
