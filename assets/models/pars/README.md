# PARS — the coloured figured set

The author's third sculpted set, and the first one that arrives **coloured**:
six GLB files uploaded to `assets/` on 2026-11-06, ~280–500k triangles and
13–21 MB each, every one carrying its own 2048² or 4096² texture atlas.

They were moved out of `assets/` to `tools/sources/incoming/` (the export packs
`assets/` whole into the APK) and imported with:

```bash
python3 tools/prepare_sculpt_set.py --colours tools/sources/incoming assets/models/pars
python3 tools/normalise_set_scale.py
```

## The roles

| kind | sculpture | source |
| --- | --- | --- |
| pawn | a guard: plumed helmet, spear, scale armour | `pawn-104217.179.glb` |
| rook | a battlemented tower with a gilded lion inside | `rook-105358.655.glb` |
| knight | a horse's head in a jewelled collar | `knight-110155.406.glb` |
| bishop | an elephant in a red and gold caparison | `bishop-111346.525.glb` |
| queen | a crowned woman in a long gown | `queen-111935.605.glb` |
| king | a bearded king with a crown and a sceptre | `king-110725.578.glb` |

The set is Indo-Persian in style, and the roles follow that tradition: the
elephant is the bishop, as it is in Persian chess, and the tower carries a lion
the way a stone tower would carry its coat of arms.

## What is here

`pawn` … `king`, `.obj` plus `.tint`.

- **Welded, then decimated** to 10 000 triangles each, with
  `fast-simplification`. Welding first matters: the uploads are triangle soups
  (the horse is 282k triangles in 21 000 disconnected islands), and a
  simplifier will not collapse across an island boundary, so without the weld
  the rook bottomed out at 18k however hard it was pushed.
- **On this project's height ladder and footprint** — `normalise_set_scale.py`
  puts every piece on the classic set's height and foot radius, so all three
  sets are interchangeable on the board.
- **`.tint`** — the sculpture's own colour, sampled from its atlas, one sRGB
  triple per vertex, plus the five header floats that make the ink army
  (`pale ** gamma * gain + lift`). 15 KB a piece, against 1.3 MB for the atlas.
  The grading rules are in `tools/prepare_sculpt_set.py`; the reader is
  `_read_tint()` in `src/main/main.gd`.
- Positions and faces only in the OBJ, four decimals: `_piece_mesh()` welds,
  generates the normals and projects the UVs at load.

## `.tint` and the export

`.tint` has no Godot importer, so `export_filter="all_resources"` alone leaves it
out of the APK. Both presets in `export_presets.cfg` carry
`include_filter="*.tint"`, and `tools/check_export_presets.py` fails the build
when a runtime file is not covered by one of those two rules.

That check exists because this shipped: a build went to the phone without the six
sidecars and every piece drew as bare white geometry, while every CI job was
green - the render job renders from the source tree, where the files are just
files. The mesh cache format was bumped at the same time, because a cache written
by that build holds the white colours and would have survived the fix.

## Why the colours are baked rather than textured

The atlas would have to ship (1.3 MB a piece, 8 MB for the set) and the meshes
have no UVs left after decimation. One colour per vertex is 15 KB, needs no
texture unit and survives the decimation, which is the whole point: the
carving is what the player sees, and the colour only has to say "gold collar,
red plume, silver armour".

The two armies are one bake. The pale army is the atlas with a uniform multiply
so its median lands at 0.70; the ink army is that colour with a gamma and a
gain so its median lands at 0.32, next to the other two sets' charcoal, and its
gold stays the brightest thing on the piece — which is exactly what the
reference image the author supplied shows: the same sculpture in black armour
with the same gold trim.
