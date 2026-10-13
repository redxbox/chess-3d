# Candidate 2 — Ancient Persian sculptures

The project owner supplied six generated source GLB sculptures on 2026-10-08 for evaluation against the active Persian set. The source meshes were geometry-only and contained no normals, UVs, materials, textures, or vertex colours.

Runtime derivatives in `optimized/` were normalized to one unit in height, simplified with quadric-error decimation, assigned regenerated normals, and given a baked curvature mask in vertex colour. The heavy source files were removed from the Android project after conversion; they remain recoverable from Git history commits `2033107` through `c184842`.

| Role | Runtime triangles |
|---|---:|
| Pawn | 6,000 |
| Rook | 12,000 |
| Bishop | 16,000 |
| Knight | 18,000 |
| Queen | 24,000 |
| King | 26,000 |
