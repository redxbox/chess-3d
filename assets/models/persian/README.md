# Persian chess set

The earlier of the two sculpted sets supplied by the project author, recovered
from `assets/models/persian/candidate2/optimized/` on the pre-audit branch,
where it had been committed as six GLBs and then dropped during the 0.12.0
asset audit because nothing loaded it. It is loaded now.

## What is here

`pawn.obj` … `king.obj`, converted by `tools/prepare_sculpt_set.py`:

- The uploads were already mobile derivatives (6k–26k triangles each, normals
  and a curvature mask baked in, every piece exactly 1.0 unit tall), so they are
  not re-simplified — only the two pieces over budget are trimmed to 10 000
  triangles.
- **Scaled onto this project's height ladder**: pawn 0.91, rook 1.18,
  knight 1.33, bishop 1.34, queen 1.49, king 1.62, matching the Staunton and
  medieval sets so all three can be swapped on the same board.
- **Standing on y = 0**, centred in X/Z, +Y up.

Total: 1.6 MB for the six bodies; 60 000 triangles for the whole set (the
cheapest of the three).

## Regenerating

```sh
python3 tools/prepare_sculpt_set.py tools/sources/persian assets/models/persian
```

The raw GLB exports live in `tools/sources/persian/`, not here: `tools/` is
excluded from the export presets, so the source files cost nothing in the app
package, while anything under `assets/` is shipped. Only the decimated OBJs
belong in the game.

### The king

`king.obj` was rebuilt from `kinge.glb`, the replacement export supplied for
this set, which is why that file has an `e` in its name. The whole-directory run
above needs a GLB for all six pieces and cannot be used on this folder, so a
single piece is rebuilt by importing the pipeline directly:

```sh
python3 - <<'EOF'
import sys; sys.path.insert(0, "tools")
import prepare_sculpt_set as p
v, f = p.prepare("king", "tools/sources/persian/kinge.glb")
p.write_obj("assets/models/persian/king.obj", "king", v, f)
EOF
```

## Facing

Same as the medieval set: the sculpts face **+Z** while the Staunton bodies face
**-Z**, which is the one fact `_facing_yaw()` needs to point both armies at each
other rather than at their own player.

## Licence

Supplied by the project author for use in this project; see `THIRD_PARTY.md`.
