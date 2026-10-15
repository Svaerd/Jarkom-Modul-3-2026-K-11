#!/usr/bin/env python3
"""
validate_configs.py — Cek kelengkapan & sintaks script Modul 3 (Soal 11-20).

Melakukan:
  1. `bash -n` untuk SEMUA script di script/
  2. render blok nginx di dalam script (heredoc) lalu `nginx -t` via Docker
     (butuh image `nginx:alpine`; kalau docker tidak ada, langkah ini dilewati)

Tidak melakukan deploy apa pun. Aman dijalankan berulang.

Pemakaian:
    python3 validate_configs.py
"""
import os
import re
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(REPO, "script")

# script -> daftar (nama_konteks, regex_heredoc, variabel_shell)
NGINX_SCRIPTS = {
    "script/geto/15-api-lb.sh": {
        "vars": {"DOMAIN": "jujutsu.K11.com"},
        "blocks": [("server", r"cat > /etc/nginx/sites-available/api-lb\.conf <<EOF\n(.*?)\nEOF\n")],
    },
    "script/gojo/16-reverse-proxy.sh": {
        "vars": {"DOMAIN": "jujutsu.K11.com", "WWW": "www.jujutsu.K11.com",
                 "MAKI": "10.69.4.3", "PANDA": "10.69.4.4", "GETO": "10.69.4.2"},
        "blocks": [("server", r"cat > /etc/nginx/sites-available/reverse-proxy\.conf <<EOF\n(.*?)\nEOF\n")],
    },
    "script/geto/17-trusted-proxy.sh": {
        "vars": {"DOMAIN": "jujutsu.K11.com", "GOJO_IP": "10.69.1.4",
                 "NANAMI": "10.69.4.5", "TODO": "10.69.4.6", "KIRARA": "10.69.4.7"},
        "blocks": [("server", r"cat > /etc/nginx/sites-available/api-lb\.conf <<EOF\n(.*?)\nEOF\n")],
    },
    "script/gojo/19-cache-ratelimit.sh": {
        "vars": {"DOMAIN": "jujutsu.K11.com", "WWW": "www.jujutsu.K11.com",
                 "MAKI": "10.69.4.3", "PANDA": "10.69.4.4", "GETO": "10.69.4.2"},
        # blok conf.d memuat $binary_remote_addr yang harus tetap UTUH (bukan
        # di-expand shell). Heredoc-nya memakai 'EOF' (quoted) sehingga aman.
        "literal": {"http"},
        "blocks": [
            ("http",   r"cat > /etc/nginx/conf\.d/19-cache-ratelimit\.conf <<'EOF'\n(.*?)\nEOF\n"),
            ("server", r"cat > /etc/nginx/sites-available/reverse-proxy\.conf <<EOF\n(.*?)\nEOF\n"),
        ],
    },
}


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, **kw)


def check_bash():
    print("=" * 66)
    print(" 1) bash -n (sintaks semua script)")
    print("=" * 66)
    fails = 0
    files = []
    for root, _, names in os.walk(SCRIPTS):
        for n in names:
            if n.endswith(".sh"):
                files.append(os.path.join(root, n))
    for f in sorted(files):
        rel = os.path.relpath(f, REPO)
        r = sh(f"bash -n '{f}'")
        if r.returncode == 0:
            print(f"  OK   {rel}")
        else:
            fails += 1
            print(f"  FAIL {rel}: {r.stderr.strip()}")
    print(f"\n  total={len(files)} gagal={fails}\n")
    return fails


def have_docker():
    return sh("command -v docker").returncode == 0 and sh("docker info").returncode == 0


def render_block(block, vars_, literal=False):
    """Render blok heredoc. literal=True -> tulis apa adanya (tanpa ekspansi shell),
    dipakai untuk blok yang memuat variabel nginx seperti $binary_remote_addr."""
    if literal:
        return block
    var_lines = "\n".join(f'{k}="{v}"' for k, v in vars_.items())
    tmp = tempfile.mktemp(suffix=".sh")
    with open(tmp, "w") as fh:
        fh.write(var_lines + "\n")
        fh.write("cat > /tmp/_blk.conf <<EOF\n" + block + "\nEOF\n")
    sh(f"bash {tmp}")
    data = open("/tmp/_blk.conf").read() if os.path.exists("/tmp/_blk.conf") else ""
    os.remove(tmp)
    if os.path.exists("/tmp/_blk.conf"):
        os.remove("/tmp/_blk.conf")
    return data


def check_nginx():
    print("=" * 66)
    print(" 2) nginx -t (config hasil render)")
    print("=" * 66)
    if not have_docker():
        print("  (docker tidak tersedia -> dilewati)\n")
        return 0
    fails = 0
    for rel, spec in NGINX_SCRIPTS.items():
        path = os.path.join(REPO, rel)
        if not os.path.exists(path):
            print(f"  SKIP {rel} (tidak ada)")
            continue
        src = open(path).read()
        http_parts, srv_parts = [], []
        literals = spec.get("literal", set())
        for ctx, rx in spec["blocks"]:
            m = re.search(rx, src, re.S)
            if not m:
                print(f"  FAIL {rel}: blok {ctx} tidak ditemukan")
                fails += 1
                continue
            rendered = render_block(m.group(1), spec["vars"], literal=(ctx in literals))
            (http_parts if ctx == "http" else srv_parts).append(rendered)

        d = tempfile.mkdtemp()
        root = "events {}\nhttp {\n"
        for i, c in enumerate(http_parts):
            open(os.path.join(d, f"http{i}.conf"), "w").write(c)
            root += f"  include /etc/nginx/http{i}.conf;\n"
        for i, c in enumerate(srv_parts):
            open(os.path.join(d, f"srv{i}.conf"), "w").write(c)
            root += f"  include /etc/nginx/srv{i}.conf;\n"
        root += "}\n"
        open(os.path.join(d, "nginx.conf"), "w").write(root)

        mounts = " ".join(
            f"-v {os.path.join(d, f)}:/etc/nginx/{f}:ro"
            for f in os.listdir(d)
        )
        cmd = f"docker run --rm {mounts} nginx:alpine nginx -t"
        r = sh(cmd)
        out = (r.stdout + r.stderr).strip().splitlines()
        verdict = [l for l in out if "syntax is ok" in l or "successful" in l or "emerg" in l or "error" in l]
        if r.returncode == 0:
            print(f"  OK   {rel}")
            for v in verdict[-1:]:
                print(f"         {v}")
        else:
            fails += 1
            print(f"  FAIL {rel}")
            for v in out[-3:]:
                print(f"         {v}")
    print(f"\n  gagal={fails}\n")
    return fails


def main():
    f1 = check_bash()
    f2 = check_nginx()
    print("=" * 66)
    print(f" HASIL: bash_fail={f1}  nginx_fail={f2}")
    print("=" * 66)
    sys.exit(1 if (f1 or f2) else 0)


if __name__ == "__main__":
    main()
