# Performance

`latest.txt` is written by CI from `tools/bench_perf.gd`, on every push to this
branch. It is the only measured performance record the project has.

## What it is, and what it is not

The benchmark runs on a GitHub runner with the **llvmpipe software rasteriser**,
at 1536x864, in `gl_compatibility`. The frame time it reports is two orders of
magnitude worse than a phone: software rasterisation is slow at exactly the thing
a phone is fast at.

So the frame time is **not** a phone number and must never be quoted as one. What
it is useful for is comparison: same machine, same renderer, same resolution,
same scene, every run. A change that halves this number halves the work the
renderer does, and that is the thing that has to fit in a phone's budget.

The load and bake figures are different: they are pure GDScript and CPU work, and
they are close to what a phone pays.

## The figures

| metric | meaning |
| --- | --- |
| `load_ready_ms` | scene instantiation to interactive, including the first board |
| `mesh_cold_ms` | six bodies built from OBJ: parse, welded normals, UVs, tangents, cavity bake. Since the sculpt-fields rewrite this includes a three-ring patch walk per vertex - the expensive half - and it is paid once per install because the result is cached |
| `mesh_warm_ms` | the same six read back from the mesh cache on disk |
| `bake_fast_ms` | the shipped cavity bake on the king mesh |
| `bake_sculpt_ms` | the full two-field carve on the king, occlusion and gild together |
| `gild_triangles` | how many faces the gild surface covers on the king |
| `frames_avg_ms` | mean frame time over 120 frames, software rendering |
| `draw_calls`, `triangles`, `objects` | what the frame costs the GPU |
| `shadow_casters` | lights that still cast a shadow; this must be 1 |
