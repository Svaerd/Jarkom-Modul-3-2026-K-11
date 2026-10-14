# AGENTS.md

## Project

Praktikum Komunikasi Data & Jaringan Komputer 2026, **Modul 3**, kelompok **K-11**.
Judul soal: _Curtain Protocol: Shibuya Incident_ — pemulihan jaringan & layanan Jujutsu High.
Deliverable: **GNS3 project + semua script + laporan**, di-submit ke form asisten, laporan berupa link repo GitHub `Jarkom-Modul-3-2026-K-11` (README.md).

Anggota: Hasheemi Rafsanjani (5027251015), Husam Danish (5027251060).

## GNS3 environment

File ini + `plan.md` ditulis setelah inspeksi lokal (13–14 Okt 2026).

- Client GNS3 lokal konek ke **remote server**, bukan local.
- Controller: `host=10.4.89.246`, `port=80`, `protocol=http`, `remote=true`.
- Kredensial controller: user `K-11`, password `K-11@GNS3`.
- Config client: `~/.config/GNS3/3.0/gns3_gui.conf` (section `Controller`).
- Local `gns3server` tidak jalan (port 3080 lokal tutup); `~/GNS3/{projects,images,...}` path lokal tapi project ada di server remote.
- `10.4.89.246` = host Group A (VPN ITS). Group B `.247`, Group C `.250`.
- Host `10.4.89.246:80` menyajikan **GNS3 Web UI** (nginx, `<title>GNS3 Web UI</title>`), redirect `/` → `/static/web-ui/bundled`, bundle: `main.fd9d76d279fa7d5e.js`.
- **API server remote ada di port `3080`**, bukan 80. Web UI (80) tak ekspos API; command API di `http://10.4.89.246:3080/v3/` (nginx/uvicorn, GNS3 **v3.0.6**).

### GNS3 v3 API (dipakai untuk inspeksi topologi/mengelola project)

Auth: `POST /v3/access/users/authenticate` body `{"username":"K-11","password":"K-11@GNS3"}` → `{"access_token":"<jwt>","token_type":"bearer"}`. Sertakan header `Authorization: Bearer <token>` untuk semua request lain.

```sh
B=http://10.4.89.246:3080
TOK=$(curl -s -X POST $B/v3/access/users/authenticate -H 'Content-Type: application/json' \
  -d '{"username":"K-11","password":"K-11@GNS3"}' | sed 's/.*"access_token":"//;s/".*//')
curl -s $B/v3/version
curl -s $B/v3/projects -H "Authorization: Bearer $TOK"
```

Endpoint berguna:
- `GET /v3/version` — tanpa auth; `{"controller_host","version":"3.0.6","local":false}`.
- `GET /v3/projects` — daftar project (`project_id`, `name`, `status`).
- `GET /v3/projects/{project_id}/nodes` — node (`name`, `node_type`, `node_id`, `properties.image`, `ports[]` dengan `adapter_number`/`mac_address`).
- `GET /v3/projects/{project_id}/links` — link (`nodes[]` tiap endpoint: `node_id`, `adapter_number`, `port_number`).
- `POST /v3/projects/{project_id}/nodes/{node_id}` body `{"name":"..."}` — rename node.
- `POST /v3/projects/{project_id}/links` body `{"nodes":[{"node_id":"A","adapter_number":0,"port_number":0},{"node_id":"B","adapter_number":0,"port_number":0}]}` — tambah kabel.
- `GET /v3/projects/{project_id}/nodes/{node_id}/files/{file_path}` — **baca file di dalam node** (mis. `etc/network/interfaces`).
- `POST /v3/projects/{project_id}/nodes/{node_id}/files/{file_path}` body **raw text** (`Content-Type: text/plain`) — **tulis file di dalam node**. Dipakai `build_topology.py` untuk push `/etc/network/interfaces`.
- `POST /v3/projects/{project_id}/nodes/{node_id}/reload` — restart node (memuat ulang `/etc/network/interfaces`).
- `/v2/...` **404** di server ini (versi lama); pakai `/v3/...`.

Project K-11: `project_id=ba86adf6-0731-42c4-bd75-12d8e905361f`, name `K-11-MODUL-3`.
Node `jichi`: `node_id=6c1e973d-6333-42de-ae47-81645c045636`.
Topologi aktual: `jichi` eth0→NAT1, eth1→Switch2 (N1: utahime/shoko/gojo), eth2→Switch3 (N2: itadori/fushiguro/zenin/okkotsu), eth3→Switch1 (N3: ino/kusakabe/kugisaki/miwa, lewat Switch5/Switch6), eth4→Switch4 (N4: geto/maki/panda/nanami/todo/kirara/yaga/inumaki/tengen).

Cara cek/tempat pakai: bisa via API (`curl` di atas) **atau** GNS3 client/web UI.


## Network design (dari soal)

Prefix jaringan internal = **`10.69`** (konfirmasi dari Modul 1–2 K-11; **verifikasi ke Master Sheet asisten**, soal bilang "dua oktet prefix ... pada Master Sheet"). `10.4.89.x` cuma IP host/VPN, **bukan** prefix internal.

- Netmask semua interface: **/24**.
- `jichi` = Router Utama & DHCP Relay. NAT via `eth0`; `eth1`→Network 1 (.1.1), `eth2`→Network 2 (.2.1), `eth3`→Network 3 (.3.1), `eth4`→Network 4 (.4.1). Aktifkan IPv4 forwarding + source NAT.
- Network 1 = DMZ: `utahime` (DNS master), `shoko` (DNS slave), `gojo` (public reverse proxy).
- Network 2 = klien Divisi A (DHCP relay): `itadori`, `fushiguro` (Pool 1); `zenin`, `okkotsu` (Pool 2).
- Network 3 = klien Divisi B: `ino`, `kusakabe` (short lease 1800s), `miwa` (long lease 43200s), `kugisaki` (fixed `.3.99`).
- Network 4 = Data Center: `tengen` (DHCP server, `.4.10`), `geto` (internal LB), worker web `maki`/`panda`, worker API `nanami`/`todo`/`kirara` (cadangan), DB master `yaga`, DB slave `inumaki`.

### Skema IP host infra (usulan K-11 — SESUAIKAN bila tabel spesifikasi asisten berbeda)

Tabel "spesifikasi" soal hilang dari `Soal ...docx.md` (gambar cuma meme). Yang pasti dari teks: `jichi` `.N.1`, `tengen` `.4.10`, DNS `.1.2`/`.1.3`, `kugisaki` `.3.99`. Sisanya usulan:

| network | node | IP | gateway |
|---|---|---|---|
| N1 | utahime (DNS master) | `10.69.1.2` | `10.69.1.1` |
| N1 | shoko (DNS slave) | `10.69.1.3` | `10.69.1.1` |
| N1 | gojo (reverse proxy) | `10.69.1.4` | `10.69.1.1` |
| N2 | itadori/fushiguro/zenin/okkotsu | DHCP | `10.69.2.1` |
| N3 | ino/kusakabe/miwa/kugisaki | DHCP | `10.69.3.1` |
| N4 | geto (internal LB) | `10.69.4.2` | `10.69.4.1` |
| N4 | maki (worker web) | `10.69.4.3` | `10.69.4.1` |
| N4 | panda (worker web) | `10.69.4.4` | `10.69.4.1` |
| N4 | nanami (worker API) | `10.69.4.5` | `10.69.4.1` |
| N4 | todo (worker API) | `10.69.4.6` | `10.69.4.1` |
| N4 | kirara (worker API cadangan) | `10.69.4.7` | `10.69.4.1` |
| N4 | yaga (DB master) | `10.69.4.8` | `10.69.4.1` |
| N4 | inumaki (DB slave) | `10.69.4.9` | `10.69.4.1` |
| N4 | tengen (DHCP server) | `10.69.4.10` | `10.69.4.1` |

Set IP + gateway tiap infra dengan `script/common/01-static-ip.sh` (deteksi dari hostname). Host infra = 1 NIC (`eth0`).

## Rules / conventions (wajib)

- Image docker: `ardhptr21/debinet:latest` untuk `jichi, tengen, utahime, shoko, gojo, geto`, semua worker & DB; `ardhptr21/alpinet:latest` untuk semua client. **Dilarang** pakai image lain.
- Semua script instalasi & konfigurasi ditaruh di **`/root`** pada masing-masing node (shell scripting).
- Saat setup awal pakai `nameserver 192.168.122.1` supaya bisa unduh paket; setelah DNS internal hidup, urutkan resolver (utahime → shoko → 192.168.122.1) kecuali dia sendiri DNS server.
- Domain: `jujutsu.<xxxx>.com`, `<xxxx>` = `K11` (mis. `jujutsu.K11.com`). BIND9, MariaDB, Nginx, isc-dhcp-server.
- Tool selain GNS3 Web/Client/VM tidak boleh.
- Wajib backup config di luar project GNS3 (simpan langkah di `.sh`/`.md`).

## Repo layout

```text
README.md                 laporan resmi (ikut format Modul 1/2 K-11)
AGENTS.md                 konteks teknis untuk AI agent (file ini)
plan.md                   rencana pengerjaan
Soal Modul 3 2026.docx.md  soal mentah (sudah diekstrak dari .docx)
script/                   (buat nanti) script per node
Attachments/              (buat nanti) gambar laporan
*.gns3project             (buat nanti) export project GNS3
```

## Workflow

1. Baca `plan.md` sebelum mulai; kerjakan satu fase/soal pada satu waktu, jangan beberapa soal sekaligus.
2. Semua config disimpan sebagai script di `script/` **dan** di `/root` node bersangkutan. Berikan prefix angka pada nama script, sesuai dengan soal yang ditujukan untuk diselesaikan script tersebut.
3. Lakukan testing setiap selesai melakukan 1 soal.
4. Setelah testing aman, minta `user` untuk screenshot bukti berhasilnya pengerjaan.
5. Tiap selesai fase: update README.md laporan + commit.
6. Sebelum submit: backup config, export `.gns3project`, susun script, isi form. Sertakan semua script + project.
