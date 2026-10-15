#!/usr/bin/env python3
"""
run_soal14.py — Otomasi deploy + jalankan script Soal 14 pada node GNS3.

Mekanisme: kirim isi script sebagai base64 ke console telnet node, decode ke
/root/<nama>, chmod +x, lalu jalankan. Aman dari masalah quoting shell.

Pemakaian:
    python3 run_soal14.py                 # semua node Soal 14
    python3 run_soal14.py maki            # satu node
    python3 run_soal14.py maki panda      # beberapa node
    python3 run_soal14.py --push-only     # hanya upload, tidak menjalankan
    python3 run_soal14.py --no-push       # hanya menjalankan (script sudah ada di node)

Catatan: script ini memakai console telnet GNS3 (port di bawah). Pastikan tidak
ada sesi console lain yang membuka node yang sama (connection refused).
"""

import base64
import os
import re
import socket
import sys
import time

HOST = "10.4.89.246"

# node -> (console_port, path_script_relatif, argumen_jalan)
NODES = {
    "maki":   (5113, "script/maki/14-web-worker.sh",      ""),
    "panda":  (5114, "script/panda/14-web-worker.sh",     ""),
    "nanami": (5116, "script/nanami/14-api-worker.sh",    ""),
    "todo":   (5117, "script/todo/14-api-worker.sh",      ""),
    "kirara": (5118, "script/kirara/14-api-worker.sh",    ""),
    "geto":   (5112, "script/geto/15-api-lb.sh",          ""),
    "itadori": (5108, "script/itadori/14-test-access.sh", ""),
}

REPO = os.path.dirname(os.path.abspath(__file__))


def clean(b: bytes) -> str:
    s = b.decode("utf-8", "replace")
    s = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", s)
    s = re.sub(r"\x1b\][^\x07]*\x07", "", s)
    return s.replace("\r", "")


def send_lines(port, lines, settle=0.6, tail=3.0, quiet=False):
    """Kirim daftar perintah ke console telnet, kembalikan output bersih."""
    s = socket.create_connection((HOST, port), timeout=10)
    s.settimeout(2)
    out = b""

    def drain(t):
        nonlocal out
        end = time.time() + t
        while time.time() < end:
            try:
                d = s.recv(8192)
                if not d:
                    break
                out += d
            except socket.timeout:
                break

    drain(1.5)
    for ln in lines:
        if ln.strip() == "":
            continue
        s.sendall(ln.encode() + b"\n")
        time.sleep(settle)
        drain(1.0)
        if not quiet:
            print(clean(out)[-2000:], end="", flush=True)
            out = b""
    time.sleep(settle)
    drain(tail)
    if not quiet:
        print(clean(out), end="", flush=True)
    s.close()
    return clean(out)


def push_script(port, local_path, remote_name):
    """Upload script ke /root/<remote_name> via base64, tanpa menjalankan."""
    with open(local_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    # pecah base64 jadi potongan agar tidak melebihi buffer console
    chunk = 1500
    parts = [b64[i:i + chunk] for i in range(0, len(b64), chunk)]
    lines = [f"rm -f /tmp/{remote_name}.b64"]
    for p in parts:
        lines.append(f"printf '%s' '{p}' >> /tmp/{remote_name}.b64")
    lines.append(f"base64 -d /tmp/{remote_name}.b64 > /root/{remote_name}")
    lines.append(f"chmod +x /root/{remote_name}")
    lines.append(f"wc -l /root/{remote_name}")
    send_lines(port, lines, settle=0.4, tail=2.0, quiet=True)
    # verifikasi
    out = send_lines(port, [f"test -s /root/{remote_name} && echo PUSH-OK || echo PUSH-FAIL"],
                     settle=0.5, tail=2.0, quiet=True)
    return "PUSH-OK" in out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    push_only = "--push-only" in flags
    no_push = "--no-push" in flags

    targets = args if args else list(NODES.keys())
    results = {}

    for node in targets:
        if node not in NODES:
            print(f"[!] node tidak dikenal: {node}")
            continue
        port, rel, extra = NODES[node]
        local = os.path.join(REPO, rel)
        remote = os.path.basename(rel)

        print("\n" + "=" * 70)
        print(f" NODE {node}  (console {port})")
        print("=" * 70)

        if not os.path.exists(local):
            print(f"[!] script tidak ada: {local}")
            results[node] = "MISSING"
            continue

        ok = True
        if not no_push:
            print(f"[*] push {rel} -> /root/{remote}")
            ok = push_script(port, local, remote)
            print(f"[*] push: {'OK' if ok else 'FAIL'}")
            if not ok:
                results[node] = "PUSH-FAIL"
                continue

        if push_only:
            results[node] = "PUSHED"
            continue

        print(f"[*] jalankan /root/{remote} {extra} ...")
        send_lines(port, [f"/root/{remote} {extra}".strip()], settle=1.0, tail=6.0)
        results[node] = "RUN"

    print("\n" + "=" * 70)
    print(" RINGKASAN")
    print("=" * 70)
    for node, st in results.items():
        print(f"  {node:10s} {st}")


if __name__ == "__main__":
    main()
