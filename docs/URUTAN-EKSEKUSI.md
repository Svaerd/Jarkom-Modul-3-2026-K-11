# Urutan Eksekusi Manual — Modul 3 K-11

Daftar perintah yang dijalankan **manual lewat console GNS3**, urut per soal.
Setiap baris: **jalankan di node tersebut**.

> Status: semua script sudah ada di `/root` tiap node.
> Node harus dalam keadaan `started` (project dibuka & start all).

---

## Persiapan (jika node baru di-restart)

Setiap kali node hidup kembali dari mati total, jalankan ulang script node
(belum ada systemd; proses tidak auto-start kecuali lewat `*.sh` boot lama).

```sh
# utahime (DNS master)
/root/11-dns-master.sh

# shoko (DNS slave)
/root/11-dns-slave.sh
```

---

## SOAL 11 — DNS Master/Slave

| # | Node | Perintah |
|---|------|----------|
| 1 | **utahime** | `/root/11-dns-master.sh` |
| 2 | **shoko**   | `/root/11-dns-slave.sh` |
| 3 | **itadori** | `/root/11-test-dns.sh serial` |
| 4 | **utahime** | `/root/11-dns-master.sh bump`  ← naikkan serial |
| 5 | **itadori** | `/root/11-test-dns.sh serial`  ← bukti sinkron |

**Bukti**: serial master == serial slave; AXFR dari itadori **ditolak**.

---

## SOAL 12 — A / CNAME / PTR / Forwarder

| # | Node | Perintah |
|---|------|----------|
| 1 | **utahime** | `/root/12-domain-ptr-forwarder.sh` |
| 2 | **shoko**   | `/root/12-domain-ptr.sh` |
| 3 | **itadori** | `/root/12-test-dns.sh` |

**Bukti**: `jujutsu.K11.com` → 10.69.1.4; `www` CNAME; PTR 10.69.1.4 → jujutsu;
`ping google.com` sukses.

---

## SOAL 13 — Database & Replikasi

| # | Node | Perintah |
|---|------|----------|
| 1 | **yaga**    | `/root/13-db-master.sh` |
| 2 | **inumaki** | `/root/13-db-slave.sh` |
| 3 | **kirara**  | `/root/13-test-replikasi.sh` |

**Bukti**: `Slave_IO_Running: Yes`; INSERT di master muncul di slave.

---

## SOAL 14 — Worker Web & API

| # | Node | Perintah |
|---|------|----------|
| 1 | **maki**    | `/root/14-web-worker.sh` |
| 2 | **panda**   | `/root/14-web-worker.sh` |
| 3 | **nanami**  | `/root/14-api-worker.sh` |
| 4 | **todo**    | `/root/14-api-worker.sh` |
| 5 | **kirara**  | `/root/14-api-worker.sh` |
| 6 | **itadori** | `/root/14-test-access.sh` |

**Bukti**: akses langsung ke worker = **403**; lewat gojo/geto = **200**
(bagian proxy baru hijau setelah Soal 15–16 selesai).

> Catatan: node mati → nginx worker mati. Hidupkan lagi:
> `nanami`/`todo`/`kirara`: `nginx` (atau `/root/18-worker-ctl.sh start`).

---

## SOAL 15 — Load Balancer geto

| # | Node | Perintah |
|---|------|----------|
| 1 | **geto** | `/root/15-api-lb.sh` |
| 2 | **geto** | `/root/15-test-lb.sh` |

**Bukti**: distribusi miring ke nanami (weight 3) vs todo (weight 1).

---

## SOAL 16 — Path-Based Routing gojo

| # | Node | Perintah |
|---|------|----------|
| 1 | **jichi**    | `/root/16-inter-network.sh`  ← **prasyarat** (N1↔N4) |
| 2 | **gojo**     | `/root/16-reverse-proxy.sh` |
| 3 | **kusakabe** | `/root/16-test-routing.sh` |

**Bukti**: `/` dilayani maki/panda bergantian; `/api` diteruskan ke geto.

---

## SOAL 17 — Client IP Terverifikasi

| # | Node | Perintah |
|---|------|----------|
| 1 | **geto**    | `/root/17-trusted-proxy.sh` |
| 2 | **itadori** | `/root/17-test-clientip.sh` |

**Bukti**: `client_ip` = IP itadori (10.69.2.10), **bukan** 10.69.1.4/10.69.4.2.

---

## SOAL 18 — Backup & Health Check

| # | Node | Perintah |
|---|------|----------|
| 1 | **geto**   | `/root/18-test-failover.sh normal` |
| 2 | **nanami** | `/root/18-worker-ctl.sh stop` |
| 3 | **todo**   | `/root/18-worker-ctl.sh stop` |
| 4 | **geto**   | `/root/18-test-failover.sh failover` |
| 5 | **nanami** | `/root/18-worker-ctl.sh start` |
| 6 | **todo**   | `/root/18-worker-ctl.sh start` |
| 7 | **geto**   | `/root/18-test-failover.sh normal` |

**Bukti**: saat nanami+todo mati → kirara > 0 dan **502 = 0**.

---

## SOAL 19 — Cache & Rate Limit gojo

| # | Node | Perintah |
|---|------|----------|
| 1 | **gojo**     | `/root/19-cache-ratelimit.sh` |
| 2 | **kusakabe** | `/root/19-test-cache-ratelimit.sh` |

**Bukti**: akses 1 = `X-Cache-Status: MISS`, akses 2+ = `HIT`;
20 request cepat ke `/api` → sebagian **429**.

---

## SOAL 20 — Benchmark

| # | Node | Perintah |
|---|------|----------|
| 1 | **kusakabe** | `/root/20-benchmark.sh` |
| 2 | **kusakabe** | `/root/20-benchmark.sh api` |
| 3 | **gojo**     | `/root/20-log-analysis.sh` |

**Bukti**: catat **RPS**, **Time per request**, **Failed requests**;
perbandingan baseline vs rate limit (429); ringkasan access log gojo.

---

## Ringkasan Cepat (satu blok per node)

```sh
# ---- utahime ----
/root/11-dns-master.sh
/root/12-domain-ptr-forwarder.sh
/root/11-dns-master.sh bump

# ---- shoko ----
/root/11-dns-slave.sh
/root/12-domain-ptr.sh

# ---- itadori ----
/root/11-test-dns.sh serial
/root/12-test-dns.sh
/root/14-test-access.sh
/root/17-test-clientip.sh

# ---- yaga ----
/root/13-db-master.sh

# ---- inumaki ----
/root/13-db-slave.sh

# ---- kirara ----
/root/13-test-replikasi.sh
/root/14-api-worker.sh

# ---- maki / panda ----
/root/14-web-worker.sh

# ---- nanami / todo ----
/root/14-api-worker.sh
/root/18-worker-ctl.sh start

# ---- geto ----
/root/15-api-lb.sh
/root/17-trusted-proxy.sh

# ---- jichi ----
/root/16-inter-network.sh

# ---- gojo ----
/root/16-reverse-proxy.sh
/root/19-cache-ratelimit.sh
/root/20-log-analysis.sh

# ---- kusakabe ----
/root/16-test-routing.sh
/root/19-test-cache-ratelimit.sh
/root/20-benchmark.sh
```

---

## Urutan Ketergantungan (penting)

```
DNS (11-12)  ──┐
DB  (13)     ──┼──> Worker (14) ──> LB geto (15) ──> gojo (16)
               │                          │
               │                          ├──> health check (18)
               │                          └──> trusted proxy (17)
               └──────────────────────────> cache + rate limit (19) ──> bench (20)
```

**Aturan praktis**:

1. **DNS & DB dulu** — worker API butuh yaga (log), DNS dibutuhkan domain.
2. **geto sebelum gojo** — gojo meneruskan `/api` ke geto.
3. **jichi `16-inter-network.sh` sebelum uji gojo** — kalau tidak, gojo (N1)
   tidak bisa menjangkau worker (N4).
4. **19 setelah 16** — cache & rate limit ditulis di config gojo yang sama.
5. **18 terakhir dari sisi LB** — perlu mematikan worker (ganggu trafik).
