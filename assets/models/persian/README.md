# Ancient Persian chess sculptures

The six source GLB files were supplied by the project owner on 2026-09-29 and generated for this project from owner-directed concept art. The project owner confirmed the intended use is integration and modification in Chess 3D.

## Runtime assets

`optimized/` originally held mobile runtime derivatives of that first supplied set. Those files were **removed from the active project** on 2026-10-17 because nothing in `src/`, `tests/` or `tools/` referenced them: the shipping runtime builds its pieces from `assets/models/staunton/*.obj` plus cached procedural geometry, so the unused set only inflated the APK. They remain recoverable from Git history.

The retained pipeline lives in [`candidate2/`](candidate2/README.md) — the second supplied set, which `tests/material_preview.gd` and `tools/bake_reference_material_masks.py` still exercise.
