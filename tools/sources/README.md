# Source exports

Raw art that the game is built **from**, never loaded **by** the game.

The export presets exclude `tools/*`, so nothing in this folder costs a single
byte of the APK. That is the whole reason it exists: `assets/` is shipped in
full, and Godot imports a `.glb` rather than ignoring it, so a 36 MB set of
uploads dropped into `assets/models/` becomes a 36 MB package whether or not a
script ever refers to it. `tools/export_budget.py` now fails the build when it
sees one.

| folder | what it holds | used by |
| --- | --- | --- |
| `incoming/` | **the drop zone**: new piece models, exactly as they arrive | `tools/check_incoming_set.py`, then `tools/prepare_sculpt_set.py` - see the README inside it |
| `persian/` | `kinge.glb`, the replacement Persian king | retired with the Persian set; kept for the record |
| `figurines/` | `pown1` `rook1` `knight1` `bishop1` `quin1` `king1` `.glb` - a whole set of court figures | `assets/models/bastani/` |

## Turning a folder of models into a playable set

```sh
python3 tools/check_incoming_set.py          # what is in the drop zone, and is it complete
python3 tools/prepare_sculpt_set.py tools/sources/incoming assets/models/<set>
python3 tools/normalise_set_scale.py
```

`check_incoming_set.py` is the gate: six pieces, one per kind, readable, under
25 MB each. It reads OBJ, GLB, glTF, STL and PLY with nothing but the standard
library, so it runs in CI as well as on a laptop.

`prepare_sculpt_set.py` decides which file is which piece from the piece name
inside the filename (`tools/piece_names.py`, English and Persian names), in any
format `trimesh` opens - so an upload does not have to be renamed first. It
decimates each body towards 10 000 triangles (repeating the pass while the
simplifier is still above budget - a mesh of many disconnected islands will not
collapse across its boundaries in one go), puts it on the height ladder the other
sets use, centres it and writes OBJ. With `--colours` it also bakes the model's
own texture into a per-vertex `.tint` sidecar, about 90 KB a piece. The result is about 230 KB per piece, so a
whole set is 1.4 MB - roughly 25 times smaller than the upload it came from.
