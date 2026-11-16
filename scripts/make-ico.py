#!/usr/bin/env python3
"""Assemble un .ico multi-tailles à partir de PNG carrés (entrées PNG, format accepté par Windows depuis Vista).
Usage : python3 -I scripts/make-ico.py <sortie.ico> <png> [<png> ...]   (chaque PNG est lu tel quel ; taille lue dans son en-tête)
Bibliothèque standard seulement, aucun réseau."""
import struct, sys

def png_size(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise SystemExit("pas un PNG valide")
    return struct.unpack(">II", data[16:24])

def main(argv):
    if len(argv) < 3:
        raise SystemExit(__doc__)
    out, pngs = argv[1], argv[2:]
    items = []
    for p in pngs:
        d = open(p, "rb").read()
        w, h = png_size(d)
        if w != h or w < 1 or w > 256:
            raise SystemExit(f"{p} : taille {w}x{h} non permise (carré, 1 à 256)")
        items.append((w, d))
    items.sort(key=lambda t: t[0])
    head = struct.pack("<HHH", 0, 1, len(items))
    offset = 6 + 16 * len(items)
    entries, blobs = b"", b""
    for w, d in items:
        entries += struct.pack("<BBBBHHII", w % 256, w % 256, 0, 0, 1, 32, len(d), offset)  # 256 s'écrit 0
        blobs += d
        offset += len(d)
    open(out, "wb").write(head + entries + blobs)
    print(f"{out} : {len(items)} tailles ({', '.join(str(w) for w, _ in items)}), {offset} octets")

main(sys.argv)
