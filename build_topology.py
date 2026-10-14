#!/usr/bin/env python3
"""
build_topology.py — GNS3 topology builder/reconciler for Jarkom Modul 3 (K-11)
"Curtain Protocol: Shibuya Incident".

Idempotent: ensures every node exists (right image + adapters) and every intended
link exists. Works on an empty project (builds from scratch) or a full one (fixes
drift only). Existing nodes keep their position; coordinates apply on creation.

Topology (prefix 10.69.x.x; addressing is applied by the node init scripts):
  NAT1 -> jichi eth0 (WAN)
  jichi eth1 -> Switch2 -> utahime, shoko, gojo                 Network 1 10.69.1.0/24
  jichi eth2 -> Switch3 -> Switch10 (itadori, fushiguro)
                        -> Switch9  (zenin, okkotsu)            Network 2 10.69.2.0/24
  jichi eth3 -> Switch1 -> Switch6 (kugisaki, miwa)
                        -> Switch5 (ino, kusakabe)             Network 3 10.69.3.0/24
  jichi eth4 -> Switch4 -> Switch7 (geto, maki, panda, nanami, todo, kirara)
                        -> Switch8 (yaga, inumaki, tengen)      Network 4 10.69.4.0/24

Usage:
  python3 build_topology.py                # apply (create missing nodes/links)
  BUILD_DRY=1 python3 build_topology.py    # preview only, no writes
  PUSH_CONFIG=1 python3 build_topology.py  # also write /etc/network/interfaces per node
  PUSH_CONFIG=1 RELOAD=1 python3 build_topology.py  # push then reload nodes

Config push uses the node file API (POST .../nodes/{id}/files/{path}); it only
touches nodes listed in CONFIGS (static infra). Clients stay DHCP.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

# ── Configuration ────────────────────────────────────────────────────────────
BASE = "http://10.4.89.246"  # GNS3 controller (Group A); API also on :3080
PROJECT_NAME = "K-11-MODUL-3"
USERNAME = "K-11"
PASSWORD = "K-11@GNS3"
DEBINET = "ardhptr21/debinet:latest"
ALPINET = "ardhptr21/alpinet:latest"
DRY = os.environ.get("BUILD_DRY") == "1"

# Nodes: (name, template_key, node_type, symbol, x, y, adapters)
# template_key: debinet | alpinet | ethernet_switch | nat
NODES = [
    ("NAT1", "nat", "nat", ":/symbols/nat.svg", 0, -360, None),
    ("jichi", "debinet", "docker", ":/symbols/router.svg", 0, -200, 6),
    # Network 1 — DMZ
    (
        "Switch2",
        "ethernet_switch",
        "ethernet_switch",
        ":/symbols/switch.svg",
        -520,
        -40,
        None,
    ),
    ("utahime", "debinet", "docker", ":/symbols/server.svg", -640, 120, 4),
    ("shoko", "debinet", "docker", ":/symbols/server.svg", -520, 120, 4),
    ("gojo", "debinet", "docker", ":/symbols/server.svg", -400, 120, 4),
    # Network 2 — Division A clients
    (
        "Switch3",
        "ethernet_switch",
        "ethernet_switch",
        ":/symbols/switch.svg",
        520,
        -40,
        None,
    ),
    (
        "Switch10",
        "ethernet_switch",
        "ethernet_switch",
        ":/symbols/switch.svg",
        420,
        120,
        None,
    ),
    (
        "Switch9",
        "ethernet_switch",
        "ethernet_switch",
        ":/symbols/switch.svg",
        680,
        120,
        None,
    ),
    ("itadori", "alpinet", "docker", ":/symbols/computer.svg", 340, 280, 4),
    ("fushiguro", "alpinet", "docker", ":/symbols/computer.svg", 460, 280, 4),
    ("zenin", "alpinet", "docker", ":/symbols/computer.svg", 620, 280, 4),
    ("okkotsu", "alpinet", "docker", ":/symbols/computer.svg", 740, 280, 4),
    # Network 3 — Division B clients
    (
        "Switch1",
        "ethernet_switch",
        "ethernet_switch",
        ":/symbols/switch.svg",
        0,
        40,
        None,
    ),
    (
        "Switch5",
        "ethernet_switch",
        "ethernet_switch",
        ":/symbols/switch.svg",
        -160,
        200,
        None,
    ),
    (
        "Switch6",
        "ethernet_switch",
        "ethernet_switch",
        ":/symbols/switch.svg",
        160,
        200,
        None,
    ),
    ("ino", "alpinet", "docker", ":/symbols/computer.svg", -240, 340, 4),
    ("kusakabe", "alpinet", "docker", ":/symbols/computer.svg", -100, 340, 4),
    ("kugisaki", "alpinet", "docker", ":/symbols/computer.svg", 100, 340, 4),
    ("miwa", "alpinet", "docker", ":/symbols/computer.svg", 240, 340, 4),
    # Network 4 — Data Center
    (
        "Switch4",
        "ethernet_switch",
        "ethernet_switch",
        ":/symbols/switch.svg",
        0,
        360,
        None,
    ),
    (
        "Switch7",
        "ethernet_switch",
        "ethernet_switch",
        ":/symbols/switch.svg",
        -140,
        520,
        None,
    ),
    (
        "Switch8",
        "ethernet_switch",
        "ethernet_switch",
        ":/symbols/switch.svg",
        180,
        520,
        None,
    ),
    ("geto", "debinet", "docker", ":/symbols/server.svg", -320, 660, 4),
    ("maki", "debinet", "docker", ":/symbols/server.svg", -200, 660, 4),
    ("panda", "debinet", "docker", ":/symbols/server.svg", -80, 660, 4),
    ("nanami", "debinet", "docker", ":/symbols/server.svg", 40, 660, 4),
    ("todo", "debinet", "docker", ":/symbols/server.svg", 160, 660, 4),
    ("kirara", "debinet", "docker", ":/symbols/server.svg", 280, 660, 4),
    ("yaga", "debinet", "docker", ":/symbols/server.svg", 80, 800, 4),
    ("inumaki", "debinet", "docker", ":/symbols/server.svg", 200, 800, 4),
    ("tengen", "debinet", "docker", ":/symbols/server.svg", 320, 800, 4),
]

# Links: (nodeA, adapterA, portA, nodeB, adapterB, portB)
LINKS = [
    ("jichi", 0, 0, "NAT1", 0, 0),
    ("jichi", 1, 0, "Switch2", 0, 0),
    ("jichi", 2, 0, "Switch3", 0, 0),
    ("jichi", 3, 0, "Switch1", 0, 0),
    ("jichi", 4, 0, "Switch4", 0, 0),
    # Network 1
    ("Switch2", 0, 1, "utahime", 0, 0),
    ("Switch2", 0, 2, "shoko", 0, 0),
    ("Switch2", 0, 3, "gojo", 0, 0),
    # Network 2
    ("Switch3", 0, 1, "Switch10", 0, 0),
    ("Switch3", 0, 2, "Switch9", 0, 0),
    ("Switch10", 0, 1, "itadori", 0, 0),
    ("Switch10", 0, 2, "fushiguro", 0, 0),
    ("Switch9", 0, 1, "zenin", 0, 0),
    ("Switch9", 0, 2, "okkotsu", 0, 0),
    # Network 3
    ("Switch1", 0, 1, "Switch5", 0, 0),
    ("Switch1", 0, 2, "Switch6", 0, 0),
    ("Switch5", 0, 1, "ino", 0, 0),
    ("Switch5", 0, 2, "kusakabe", 0, 0),
    ("Switch6", 0, 1, "kugisaki", 0, 0),
    ("Switch6", 0, 2, "miwa", 0, 0),
    # Network 4
    ("Switch4", 0, 1, "Switch7", 0, 0),
    ("Switch4", 0, 2, "Switch8", 0, 0),
    ("Switch7", 0, 1, "geto", 0, 0),
    ("Switch7", 0, 2, "maki", 0, 0),
    ("Switch7", 0, 3, "panda", 0, 0),
    ("Switch7", 0, 4, "nanami", 0, 0),
    ("Switch7", 0, 5, "todo", 0, 0),
    ("Switch7", 0, 6, "kirara", 0, 0),
    ("Switch8", 0, 1, "tengen", 0, 0),
    ("Switch8", 0, 2, "yaga", 0, 0),
    ("Switch8", 0, 3, "inumaki", 0, 0),
]

IMAGE = {"debinet": DEBINET, "alpinet": ALPINET}

PUSH = os.environ.get("PUSH_CONFIG") == "1"
RELOAD_AFTER = os.environ.get("RELOAD") == "1"

# Static interface config pushed to infra nodes: name -> (address, gateway).
# SESUAIKAN bila tabel spesifikasi asisten berbeda (lihat AGENTS.md).
# Clients Network 2/3 are DHCP -> not listed.
CONFIGS = {
    "utahime": ("10.69.1.2", "10.69.1.1"),
    "shoko": ("10.69.1.3", "10.69.1.1"),
    "gojo": ("10.69.1.4", "10.69.1.1"),
    "geto": ("10.69.4.2", "10.69.4.1"),
    "maki": ("10.69.4.3", "10.69.4.1"),
    "panda": ("10.69.4.4", "10.69.4.1"),
    "nanami": ("10.69.4.5", "10.69.4.1"),
    "todo": ("10.69.4.6", "10.69.4.1"),
    "kirara": ("10.69.4.7", "10.69.4.1"),
    "yaga": ("10.69.4.8", "10.69.4.1"),
    "inumaki": ("10.69.4.9", "10.69.4.1"),
    "tengen": ("10.69.4.10", "10.69.4.1"),
}


# ── API helpers ──────────────────────────────────────────────────────────────
def req(method, path, body=None, token=None, timeout=30):
    r = urllib.request.Request(BASE + path, method=method)
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        r.add_header("Content-Type", "application/json")
    if token:
        r.add_header("Authorization", "Bearer " + token)
    for attempt in range(3):  # VPN is flaky — retry
        try:
            with urllib.request.urlopen(r, data, timeout=timeout) as resp:
                raw = resp.read().decode()
                return resp.status, (json.loads(raw) if raw.strip() else None)
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode()[:300]
        except Exception as e:
            if attempt == 2:
                return -1, str(e)
            time.sleep(2)


def authenticate():
    st, r = req(
        "POST",
        "/v3/access/users/authenticate",
        {"username": USERNAME, "password": PASSWORD},
    )
    if st != 200:
        sys.exit(f"Authentication failed ({st}): {r}")
    return r["access_token"]


def get_template_ids(token):
    st, templates = req("GET", "/v3/templates", token=token)
    if st != 200:
        sys.exit(f"Cannot list templates ({st}): {templates}")
    ids = {
        (t.get("name") or "").strip().lower(): t["template_id"] for t in templates or []
    }
    for need in ("debinet", "alpinet", "ethernet switch", "nat"):
        if need not in ids:
            sys.exit(f"Required template '{need}' not found on controller")
    return ids


def get_project_id(token, name):
    st, projects = req("GET", "/v3/projects", token=token)
    for p in projects or []:
        if p["name"] == name:
            return p["project_id"]
    sys.exit(f"Project '{name}' not found")


def get_nodes(token, pid):
    st, ns = req("GET", f"/v3/projects/{pid}/nodes", token=token)
    return {n["name"]: n for n in (ns or [])}


def get_link_pairs(token, pid):
    st, ls = req("GET", f"/v3/projects/{pid}/links", token=token)
    pairs = set()
    for l in ls or []:
        a, b = l["nodes"]
        pairs.add(
            frozenset(
                [
                    (a["node_id"], a["adapter_number"], a["port_number"]),
                    (b["node_id"], b["adapter_number"], b["port_number"]),
                ]
            )
        )
    return pairs


def interfaces_text(ip, gw, iface="eth0"):
    return (
        "auto lo\niface lo inet loopback\n\n"
        f"auto {iface}\niface {iface} inet static\n"
        f"\taddress {ip}\n\tnetmask 255.255.255.0\n\tgateway {gw}\n"
    )


def write_file(token, pid, node_id, path, text):
    """POST raw text into the node filesystem via the GNS3 file API."""
    r = urllib.request.Request(
        f"{BASE}/v3/projects/{pid}/nodes/{node_id}/files/{path}",
        method="POST",
        data=text.encode(),
    )
    r.add_header("Content-Type", "text/plain")
    r.add_header("Authorization", "Bearer " + token)
    for attempt in range(3):
        try:
            with urllib.request.urlopen(r, timeout=30) as resp:
                return resp.status, resp.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode()[:200]
        except Exception as e:
            if attempt == 2:
                return -1, str(e)
            time.sleep(2)


def push_configs(token, pid, idmap):
    for name, (ip, gw) in CONFIGS.items():
        if name not in idmap:
            print(f"[!] Config {name}: node missing")
            continue
        nid = idmap[name]
        want = interfaces_text(ip, gw)
        st, cur = req(
            "GET",
            f"/v3/projects/{pid}/nodes/{nid}/files/etc/network/interfaces",
            token=token,
        )
        if st == 200 and cur == want:
            print(f"[=] Config {name}: sudah benar ({ip})")
            continue
        if DRY:
            print(f"[~] Config {name}: would write {ip}/24 gw {gw}")
            continue
        st, r = write_file(token, pid, nid, "etc/network/interfaces", want)
        ok = st in (200, 201)
        print(
            f"[{'+' if ok else '!'}] Config {name}: {ip}/24 gw {gw} "
            f"{'OK' if ok else f'FAILED ({st}): {r}'}"
        )


def reload_nodes(token, pid, idmap):
    for name in CONFIGS:
        if name not in idmap:
            continue
        st, r = req("POST", f"/v3/projects/{pid}/nodes/{idmap[name]}/reload", {}, token)
        print(f"[{'x' if st in (200, 201) else '!'}] Reload {name}: {st}")


# ── Build steps ──────────────────────────────────────────────────────────────
def main():
    token = authenticate()
    print(f"[+] Authenticated{' (DRY RUN)' if DRY else ''}")

    templates = get_template_ids(token)
    pid = get_project_id(token, PROJECT_NAME)
    print(f"[+] Project: {PROJECT_NAME} ({pid})")

    if not DRY:
        req("POST", f"/v3/projects/{pid}/open", {}, token=token)
        time.sleep(1)

    # Nodes: create missing; enforce image + adapter count on existing.
    nodes = get_nodes(token, pid)
    for name, tmpl_key, ntype, symbol, x, y, adapters in NODES:
        if name in nodes:
            existing = nodes[name]
            props = existing.get("properties", {})
            updates = {}
            if ntype == "docker":
                want_img = IMAGE[tmpl_key]
                if props.get("image") != want_img:
                    updates["image"] = want_img
                cur = props.get("adapters")
                if cur is not None and adapters is not None and cur < adapters:
                    updates["adapters"] = adapters
                elif cur is not None and adapters is not None and cur > adapters:
                    print(
                        f"[!] Node {name}: has {cur} adapters (> {adapters}); "
                        f"not shrinking (delete node manually if needed)"
                    )
            if updates:
                if DRY:
                    print(f"[~] Node {name}: would update {', '.join(updates)}")
                else:
                    st, r = req(
                        "PUT",
                        f"/v3/projects/{pid}/nodes/{existing['node_id']}",
                        updates,
                        token,
                    )
                    ok = isinstance(r, dict)
                    print(
                        f"[{'+' if ok else '!'}] Node {name}: update "
                        f"{', '.join(updates)} {'OK' if ok else f'FAILED ({st}): {r}'}"
                    )
            else:
                print(f"[=] Node {name}: exists")
            continue
        body = {
            "template_id": templates[tmpl_key],
            "name": name,
            "node_type": ntype,
            "x": x,
            "y": y,
            "symbol": symbol,
            "compute_id": "local",
        }
        if ntype == "docker":
            body["properties"] = {"image": IMAGE[tmpl_key], "adapters": adapters or 1}
        if DRY:
            print(f"[~] Node {name}: would create")
            continue
        st, r = req("POST", f"/v3/projects/{pid}/nodes", body, token)
        if st in (200, 201):
            got = r.get("name") if isinstance(r, dict) else "?"
            print(f"[+] Node {name}: created")
            if got != name:
                print(
                    f"[!] WARNING: controller named it '{got}' — delete, "
                    f"close+reopen project, rerun."
                )
        else:
            print(f"[!] Node {name}: FAILED ({st}): {r}")

    nodes = get_nodes(token, pid)
    idmap = {n["name"]: n["node_id"] for n in nodes.values()}

    # Links: ensure each intended link exists (idempotent).
    have = get_link_pairs(token, pid)
    added = 0
    for a, aa, ap, b, ba, bp in LINKS:
        if a not in idmap or b not in idmap:
            print(f"[!] Link {a}<->{b}: skipped (node missing)")
            continue
        pair = frozenset([(idmap[a], aa, ap), (idmap[b], ba, bp)])
        if pair in have:
            continue
        if DRY:
            print(f"[~] Link {a}(adp{aa}) <-> {b}(adp{ba}): would create")
            added += 1
            continue
        st, r = req(
            "POST",
            f"/v3/projects/{pid}/links",
            {
                "nodes": [
                    {"node_id": idmap[a], "adapter_number": aa, "port_number": ap},
                    {"node_id": idmap[b], "adapter_number": ba, "port_number": bp},
                ]
            },
            token,
        )
        ok = st in (200, 201)
        added += 1 if ok else 0
        print(
            f"[{'+' if ok else '!'}] Link {a}(adp{aa}) <-> {b}(adp{ba}): "
            f"{'OK' if ok else f'FAILED ({st}): {r}'}"
        )

    # Push static interface configs (opt-in).
    if PUSH:
        print("\n=== PUSH CONFIGS ===")
        push_configs(token, pid, idmap)
        if RELOAD_AFTER and not DRY:
            print("\n=== RELOAD NODES ===")
            reload_nodes(token, pid, idmap)

    # Report.
    st, ls = req("GET", f"/v3/projects/{pid}/links", token=token)
    nm = {n["node_id"]: n["name"] for n in nodes.values()}
    print("\n=== FINAL TOPOLOGY ===")
    print(
        f"nodes: {len(nm)} (expect {len(NODES)}) | "
        f"links: {len(ls or [])} (expect {len(LINKS)}) | new links: {added}"
    )
    if set(nm.values()) != {n[0] for n in NODES}:
        print("!! node name mismatch:")
        print("   missing:", sorted({n[0] for n in NODES} - set(nm.values())))
        print("   extra  :", sorted(set(nm.values()) - {n[0] for n in NODES}))


if __name__ == "__main__":
    main()
