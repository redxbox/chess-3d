#!/usr/bin/env python3
"""Check that every engine property this project assigns actually exists.

GDScript only resolves a property assignment at run time, and assigning a name
that a class does not have is a SCRIPT ERROR in the log - not a parse error. So
a typo or a property that belongs to a different class passes the parser, passes
`--check-only`, and then fails the startup check minutes later, after the render
and the APK have already been built.

That has now happened twice in one round: `Viewport.shadow_atlas_size` (a project
setting, not a property) and `Environment.dof_blur_far_enabled` (a
CameraAttributes property). Both are in this file's list of assigned names, and
both are caught in under a second here.

The property lists come from Godot's own class reference at the tag this project
builds against - tools/data/godot-4.4.1-properties.json, generated from the
engine repository. StandardMaterial3D inherits everything from BaseMaterial3D, so
one list covers both.

Only the prefixes with a known class are checked. A variable called `state` or
`game` is not in any class, so guessing is not attempted: a false pass is cheap,
a false failure on every commit is not.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "tools" / "data" / "godot-4.4.1-properties.json"

# Every prefix this project assigns engine properties on, and the class (or
# classes) that prefix means. `$KeyLight` and friends are DirectionalLight3D in
# the scene, and Light3D is its parent, so both lists apply.
PREFIX_CLASSES = {
    "environment": ("Environment",),
    "camera_attributes": ("CameraAttributesPractical", "CameraAttributes"),
    "material": ("BaseMaterial3D",),
    "sky_material": (),   # ProceduralSkyMaterial is not in the list; skipped
    "get_viewport()": ("Viewport",),
    "$KeyLight": ("DirectionalLight3D", "Light3D", "Node3D"),
    "$FillLight": ("DirectionalLight3D", "Light3D", "Node3D"),
    "$RimLight": ("DirectionalLight3D", "Light3D", "Node3D"),
    "$BounceLight": ("DirectionalLight3D", "Light3D", "Node3D"),
}

ASSIGNMENT = re.compile(r"^\s*(?P<prefix>[A-Za-z_$()\[\]]+?)\.(?P<prop>[a-z_0-9]+)\s*(?:\+|-|\*|/)?=\s*[^=]")


def load_properties() -> dict[str, set[str]]:
    data = json.loads(DATA.read_text())
    return {name: set(props) for name, props in data["classes"].items()}


def main() -> int:
    props = load_properties()
    problems: list[str] = []
    checked = 0
    for path in sorted((ROOT / "src").rglob("*.gd")):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            match = ASSIGNMENT.match(line)
            if not match:
                continue
            prefix = match.group("prefix")
            prop = match.group("prop")
            classes = PREFIX_CLASSES.get(prefix)
            if not classes:
                continue
            known: set[str] = set()
            for cls in classes:
                known |= props.get(cls, set())
            if not known:
                continue
            checked += 1
            if prop not in known:
                problems.append(
                    f"{path.relative_to(ROOT)}:{number}: {prefix}.{prop} does not exist on "
                    f"{' or '.join(classes)}")
    if problems:
        print("engine property check failed:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1
    print(f"engine property check ok: {checked} assignments resolve against Godot 4.4.1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
