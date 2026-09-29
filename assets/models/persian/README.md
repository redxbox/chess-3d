# Ancient Persian chess sculptures

The six source GLB files were supplied by the project owner on 2026-09-29 and generated for this project from owner-directed concept art. The project owner confirmed the intended use is integration and modification in Chess 3D.

## Runtime assets

`optimized/` contains mobile runtime derivatives produced from the supplied source meshes. All meshes were normalized by their source generator to approximately one unit in height, simplified with quadric-error decimation, stripped of source-only data, assigned regenerated vertex normals, and exported as GLB.

| Role | Source triangles | Runtime triangle budget |
|---|---:|---:|
| Pawn | 390,930 | 6,000 |
| Rook | 315,616 | 12,000 |
| Bishop | 315,108 | 16,000 |
| Knight | 342,122 | 18,000 |
| Queen | 340,408 | 24,000 |
| King | 367,786 | 12,000 |

The source files contain geometry only: no embedded materials, textures, UV coordinates, or vertex colors. Runtime metal materials are therefore supplied by Godot and shared across all instances.
