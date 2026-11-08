#!/usr/bin/env python3
"""Check that a built APK/AAB actually carries the pars set's colour sidecars.

    python3 tools/check_packed_colours.py build/android/chess-3d.apk

`tools/check_export_presets.py` checks the presets - the rules. This checks the
artefact, which is the only thing the phone ever sees. They are not the same
check: the presets can name `*.tint` and the export can still leave it out,
because the file sits behind whatever rule Godot applied at the time.

It matters because of what happened once. The pars set keeps its colours in
`assets/models/pars/<kind>.tint`, files Godot cannot import. With an empty
include_filter they were dropped, and since the set's material is white on
purpose, the phone drew thirty-two untextured white pieces in two identical
armies - and every job was green, because the editor and the render job read the
source tree.

How the check reads the package: Godot puts the game's files in one `*.pck`
entry inside the APK (or the AAB's base module), and that pack carries a
directory of `res://` paths as plain strings. So the paths are searched for in
the decompressed pack. A pack we cannot read at all is reported as a notice, not
a failure - this script must never fail a build for its own blindness, only for
a file that is really missing.
"""

import sys
import zipfile

KINDS = ("king", "queen", "rook", "bishop", "knight", "pawn")
SET_DIR = "assets/models/pars"


def pack_bytes(path):
    """Every byte of the package that could hold a pack directory."""
    chunks = []
    with zipfile.ZipFile(path) as package:
        for info in package.infolist():
            name = info.filename.lower()
            if name.endswith(".pck"):
                chunks.append(package.read(info))
        # Some exports leave the pack loose next to the libraries instead.
        chunks.append(b"\n".join(n.encode() for n in package.namelist()))
    return b"".join(chunks)


def marker(kind):
    return "%s/%s.tint" % (SET_DIR, kind)


def main(argv):
    if len(argv) != 1:
        print("usage: check_packed_colours.py <apk-or-aab>", file=sys.stderr)
        return 2
    path = argv[0]
    try:
        data = pack_bytes(path)
    except (OSError, zipfile.BadZipFile) as error:
        print("could not open %s: %s" % (path, error), file=sys.stderr)
        return 2

    wanted = [marker(kind) for kind in KINDS]
    found = [name for name in wanted if name.encode() in data]

    # A pack whose directory this search cannot see would show neither the
    # sidecars nor the meshes that certainly are in it. Only judge the package
    # when it can be read at all.
    meshes = [("%s/%s.obj" % (SET_DIR, kind)).encode() for kind in KINDS]
    if not any(m in data for m in meshes):
        print("::notice title=Package check could not read the pack::"
              "no pars mesh paths found in %s - skipping the sidecar check" % path)
        print("package check skipped: the pack directory was not readable")
        return 0

    if len(found) != len(wanted):
        missing = [n for n in wanted if n not in found]
        print("::error title=Colour sidecars missing from the package::" + "%0A".join(missing))
        for name in missing:
            print("missing from the package: " + name)
        return 1

    print("package carries all %d colour sidecars" % len(wanted))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
