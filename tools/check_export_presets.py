#!/usr/bin/env python3
"""Fail when a file the game reads at runtime would not be in the package.

WHAT THIS CATCHES
-----------------
Godot's `export_filter="all_resources"` ships resources it can import or load as
a resource. A file with no importer of its own - a `.tint` sidecar, say
sidecars are the current example, and any future `.json`, `.bin` or `.csv` table
would be the next - is only packed when `include_filter` matches it.

Nothing in an editor run or in the visual-preview job notices, because both read
the project directory directly. The exported APK is the first place the file is
missing, and the symptom is not an error dialog: the colour sidecars were absent
from the package once and the whole set drew as bare white geometry on a phone,
with every CI job green, because the render job renders from the source tree.

So this check reads `export_presets.cfg` and every file under `assets/`, and
fails when a file has neither of:

  * an extension Godot imports (`.obj`, `.png`, `.wav`, ...), which makes it a
    resource the export packs by itself;
  * a match in the preset's `include_filter`.

Run it from the workflow before the export:

    python3 tools/check_export_presets.py
"""

from __future__ import annotations

import configparser
import fnmatch
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRESETS = os.path.join(ROOT, "export_presets.cfg")
ASSETS = os.path.join(ROOT, "assets")

# Extensions Godot has an importer for, so `all_resources` packs them without
# being named anywhere. Kept to what this project actually uses or is likely to:
# a missing one shows up here as a false failure, which is cheap to fix, where a
# missing include is a broken build.
IMPORTED = {
    ".obj", ".glb", ".gltf", ".fbx", ".dae", ".blend",
    ".png", ".jpg", ".jpeg", ".webp", ".svg", ".tga", ".exr", ".hdr",
    ".wav", ".ogg", ".mp3",
    ".ttf", ".otf", ".fnt",
    ".gd", ".tscn", ".tres", ".res", ".gdshader", ".theme", ".anim",
}
# Documentation and the like: never read at runtime, never shipped.
IGNORED = {".md", ".txt"}

# Godot writes these next to a source file when it imports it, and they are
# editor bookkeeping rather than content: `foo.obj.import` describes how `foo.obj`
# is imported, and the export packs the imported resource, not the sidecar. They
# are not in the repository, so they only show up where the project has actually
# been imported - which is every CI run, and how this check failed the first time
# it ran: twelve `.obj.import` files, freshly written by the import step above.
EDITOR_SIDECARS = (".import", ".uid", ".remap")


def read_presets() -> list[dict[str, str]]:
    """The export presets, as `{name, include_filter, exclude_filter}` dicts.

    Parsed by hand rather than with configparser: the file uses `[preset.0]`
    sections with keys like `export_filter`, and `configparser` would also choke
    on the `;` comment lines Godot writes when it saves the file itself. The
    format is one `key="value"` per line and is not going to surprise anyone.
    """
    presets: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    with open(PRESETS, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if line.startswith("[preset.") and line.endswith("]"):
                current = {"section": line.strip("[]")}
                presets.append(current)
                continue
            if current is None or line.startswith("[") or not line.strip():
                continue
            if "=" not in line:
                continue
            key, _, value = line.partition("=")
            value = value.strip()
            if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
                value = value[1:-1]
            current[key.strip()] = value
    return presets


def unmatched(relative: str, filters: str) -> bool:
    """Whether no pattern in a comma-separated Godot filter matches `relative`."""
    patterns = [pattern.strip() for pattern in filters.split(",") if pattern.strip()]
    name = os.path.basename(relative)
    for pattern in patterns:
        # Godot matches against the path and against the bare file name, and
        # `**` is not special to it - so `*.tint` and `assets/**/*.tint` both
        # have to work here, which fnmatch covers.
        if fnmatch.fnmatch(relative, pattern) or fnmatch.fnmatch(name, pattern):
            return False
    return True


def main() -> int:
    if not os.path.exists(PRESETS):
        print("no export_presets.cfg", file=sys.stderr)
        return 1
    presets = [preset for preset in read_presets() if preset.get("platform")]
    if not presets:
        print("export_presets.cfg has no presets", file=sys.stderr)
        return 1

    wanted: list[str] = []
    for directory, _, files in os.walk(ASSETS):
        for name in files:
            extension = os.path.splitext(name)[1].lower()
            if extension in IGNORED or extension in IMPORTED:
                continue
            if name.endswith(EDITOR_SIDECARS) or name.startswith("."):
                continue
            relative = os.path.relpath(os.path.join(directory, name), ROOT).replace(os.sep, "/")
            wanted.append(relative)
    wanted.sort()

    problems: list[str] = []
    for preset in presets:
        label = preset.get("name", preset["section"])
        include = preset.get("include_filter", "")
        exclude = preset.get("exclude_filter", "")
        for relative in wanted:
            if not unmatched(relative, exclude):
                problems.append(f"{label}: {relative} is excluded from the package but the game reads it")
                continue
            if unmatched(relative, include):
                problems.append(
                    f"{label}: {relative} has no Godot importer and include_filter is "
                    f"'{include}' - it will not be in the APK")
    if problems:
        # A step annotation, because the job log is not always readable from
        # the API and "exit code 1" says nothing about which file is missing.
        print("::error title=Runtime file would miss the package::"
              + "%0A".join(problems[:6]))
        print("export packaging check failed:", file=sys.stderr)
        for problem in problems:
            print("  - " + problem, file=sys.stderr)
        print("\nAdd the extension to include_filter in export_presets.cfg for every preset.",
              file=sys.stderr)
        return 1

    if wanted:
        print(f"export packaging ok: {len(wanted)} non-imported files, all covered by "
              f"{len(presets)} preset(s)")
        for relative in wanted:
            print("  " + relative)
    else:
        print("export packaging ok: every asset file has an importer")
    return 0


if __name__ == "__main__":
    sys.exit(main())
