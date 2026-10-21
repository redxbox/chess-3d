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
python3 tools/prepare_sculpt_set.py /path/to/glb/folder assets/models/persian
```

## Facing

Same as the medieval set: the sculpts face **+Z**, `_facing_yaw()` turns each
army's asymmetric pieces toward the enemy.

## Licence

Supplied by the project author for use in this project; see `THIRD_PARTY.md`.
