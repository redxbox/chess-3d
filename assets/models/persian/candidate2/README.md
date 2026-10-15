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

## Reference-guided finish masks

Beta 22.28 samples the six user-supplied colored role references offline. The
bake preserves curvature in `COLOR_0.r`, stores polished-gold coverage in
`COLOR_0.g`, and dark engraved/inlay coverage in `COLOR_0.b`. Runtime rendering
therefore needs no bundled photographs, UV texture fetches, or added draw calls.
The reproducible baker is `tools/bake_reference_material_masks.py`; reference
photographs remain external user inputs and are not redistributed in the APK.
