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
| `persian/` | `kinge.glb`, the replacement Persian king | retired with the Persian set; kept for the record |
| `figurines/` | `pown1` `rook1` `knight1` `bishop1` `quin1` `king1` `.glb` - a whole set of court figures | `assets/models/court/` |

## Turning a folder of GLBs into a playable set

```sh
python3 tools/prepare_sculpt_set.py tools/sources/figurines assets/models/<set>
```

`prepare_sculpt_set.py` accepts `<kind>.glb`, `<kind>e.glb` and `<kind>1.glb`
(the author's naming), decimates each body to 10 000 triangles, scales it onto
the height ladder the other sets use, centres it and writes OBJ with normals.
The result is about 230 KB per piece, so a whole set is 1.4 MB - roughly 25
times smaller than the upload it came from.
