#!/usr/bin/env python3
"""
deploy.py — push script lokal ke /root node GNS3 (via console telnet, base64).
Tidak menjalankan script (kecuali --run diberikan).

Pemakaian:
    python3 deploy.py <node> <path_lokal> [nama_remote] [--run]

Node yang dikenal (nama -> port console):
    jichi 5053, gojo 5103, ino 5104, kusakabe 5105, itadori 5108,
    geto 5112, maki 5113, panda 5114, nanami 5116, todo 5117, kirara 5118,
    tengen 5119, yaga 5120, inumaki 5122, utahime 5101, shoko 5102
"""
import base64
import os
import re
import socket
import sys
import time

HOST = "10.4.89.246"
PORTS = {
    "jichi": 5012, "gojo": 5103, "ino": 5104, "kusakabe": 5105,
    "kugisaki": 5106, "miwa": 5107, "itadori": 5108, "fushiguro": 5109,
    "zenin": 5110, "okkotsu": 5111, "geto": 5112, "maki": 5113,
    "panda": 5114, "nanami": 5116, "todo": 5117, "kirara": 5118,
    "tengen": 5119, "yaga": 5120, "inumaki": 5122,
    "utahime": 5046, "shoko": 5050,
}


def clean(b):
    s = b.decode("utf-8", "replace")
    s = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", s)
    return s.replace("\r", "")


def session(port, lines, settle=0.4, tail=2.5):
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

    drain(1.2)
    for ln in lines:
        if not ln.strip():
            continue
        s.sendall(ln.encode() + b"\n")
        time.sleep(settle)
        drain(0.8)
    time.sleep(settle)
    drain(tail)
    s.close()
    return clean(out)


def push(node, local, remote):
    port = PORTS[node]
    b64 = base64.b64encode(open(local, "rb").read()).decode()
    parts = [b64[i:i + 1400] for i in range(0, len(b64), 1400)]
    lines = [f"rm -f /tmp/{remote}.b64"]
    for p in parts:
        lines.append(f"printf '%s' '{p}' >> /tmp/{remote}.b64")
    lines += [
        f"base64 -d /tmp/{remote}.b64 > /root/{remote}",
        f"chmod +x /root/{remote}",
    ]
    session(port, lines)
    out = session(port, [f"test -s /root/{remote} && md5sum /root/{remote}"])
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    run = "--run" in sys.argv
    if len(args) < 2:
        print(__doc__)
        sys.exit(1)
    node, local = args[0], args[1]
    remote = args[2] if len(args) > 2 else os.path.basename(local)

    if node not in PORTS:
        print(f"[!] node tidak dikenal: {node}. Pilihan: {', '.join(PORTS)}")
        sys.exit(1)
    if not os.path.exists(local):
        print(f"[!] file tidak ada: {local}")
        sys.exit(1)

    local_md5 = os.popen(f"md5sum {local}").read().split()[0]
    print(f"[*] {node}: {local} -> /root/{remote}")
    out = push(node, local, remote)
    print(clean(out.encode()).strip()[-400:])
    print(f"[*] md5 lokal : {local_md5}")

    if run:
        print(f"[*] menjalankan /root/{remote} ...")
        session(PORTS[node], [f"/root/{remote}"], settle=1.0, tail=8.0)


if __name__ == "__main__":
    main()
