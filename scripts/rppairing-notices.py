"""Reads `cargo metadata` JSON on stdin and prints the licence notices of every crate in the build.

Identical licence texts (the Apache-2.0 text appears in most crates) are printed once, with the
list of crates that carry it."""
import glob
import json
import os
import sys

meta = json.load(sys.stdin)
in_build = {node["id"] for node in meta["resolve"]["nodes"]}
packages = sorted(
    (p for p in meta["packages"] if p["id"] in in_build and p["name"] != "skrppairing"),
    key=lambda p: (p["name"], p["version"]),
)

texts = {}  # text -> [(crate, file)]
without = []
for p in packages:
    root = os.path.dirname(p["manifest_path"])
    files = sorted(
        f for pattern in ("LICENSE*", "LICENCE*", "COPYING*", "NOTICE*", "UNLICENSE*")
        for f in glob.glob(os.path.join(root, pattern)) if os.path.isfile(f)
    )
    if not files:
        without.append(p)
    for f in files:
        text = open(f, encoding="utf-8", errors="replace").read().strip()
        texts.setdefault(text, []).append((f"{p['name']} {p['version']}", os.path.basename(f)))

print("Licences of the Rust crates linked into SKapsule's on-device pairing library.\n")
print("Crates and their declared licences:")
for p in packages:
    print(f"  {p['name']} {p['version']}: {p.get('license') or 'see source'}")
if without:
    print("\nPublished without a licence file (licence as declared above): " + ", ".join(p["name"] for p in without))

for n, (text, users) in enumerate(sorted(texts.items(), key=lambda kv: kv[1][0]), 1):
    print("\n" + "=" * 78)
    print(f"Licence text {n}, from: " + "; ".join(f"{crate} ({name})" for crate, name in users))
    print("=" * 78)
    print(text)
