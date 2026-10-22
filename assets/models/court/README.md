# Court set

The third set, and the replacement for the old Persian one.

## Why the Persian set went

The Persian set was the same carved-lathe family as the medieval set: same
plinths, same lathe silhouettes, same mitre on the bishop. Once both were on the
board the only difference a player could see was colour, which made two of the
three piece choices look like the same set twice. The style screen exists to
offer three different sets, not three tints.

This set is different in kind. Every piece is a figure:

| piece | figure |
| --- | --- |
| pawn | a guard in a tall hat, spear in one hand and a round shield on the other arm |
| rook | a twin castle tower joined by a lion-masked bridge |
| knight | a rearing horse on a rocky plinth |
| bishop | a war elephant with its trunk raised and a saddle blanket |
| queen | a crowned noblewoman holding a cup |
| king | a bearded king in a robe, holding a sceptre |

All six stand on engraved, scalloped plinths, which is what holds the family
together now that the silhouettes differ.

## How it was made

`tools/sources/figurines/` holds the six uploads: 3.1-3.9 million triangles each,
36 MB in total, geometry only, every piece exactly one unit tall. They are not
usable as they are, and not only for size: at one unit for a pawn and one for a
king, a pawn would stand as tall as the king.

`tools/prepare_sculpt_set.py` does what it does for the other two sets - decimate
to 10 000 triangles, scale onto the same height ladder (pawn 0.91 up to king
1.62), centre in X/Z, stand on y = 0 - and writes OBJ:

```sh
python3 tools/prepare_sculpt_set.py tools/sources/figurines assets/models/court
```

The script accepts the author's file names (`pown1.glb`, `quin1.glb`, …) as they
are; nothing has to be renamed.

## Budget

| | |
| --- | --- |
| source | 36 MB, 2.1 million triangles |
| shipped | 1.75 MB, 60 000 triangles |
| per piece | 291 KB, 10 000 triangles |

10 000 triangles is not a compromise. The pieces are 1.6 units tall on a 1.0
square, so at the closest the camera ever gets a king is about 300 screen pixels
high: the faceting this shows at is the same faceting the medieval set has at
the same count, and it is invisible on the board. The detail that has to survive
- the spear, the shield's boss, the horse's jaw, the elephant's trunk, the
crown, the sceptre - is all silhouette, and silhouette is what decimation keeps.

## Facing

Every figure faces **+Z**, like the medieval set and unlike the turned set, so
`_facing_yaw()` needs no per-set case: it already turns each army's +Z-front
bodies toward the enemy. Verified on the source exports: the guard's shield is
on the -X side and his spear forward, the horse faces +Z, the elephant's trunk
curls forward and up, and the king's sceptre is in front of him.

## Licence

Supplied by the project author for use in this project; see `THIRD_PARTY.md`.
