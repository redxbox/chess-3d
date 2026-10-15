# Royal mobile materials

These Godot `StandardMaterial3D` resources target the GLES3 Compatibility
renderer. Board marble uses baked 256×256 albedo maps; generated ornaments use
shared ivory, aged-black-bronze, and polished-gold PBR resources. Imported
Candidate 2 bodies retain their shared lightweight spatial shader because their
source geometry has no UV set or source material slots. Their baked vertex
channels provide curvature, photo-derived gold, and dark-inlay masks without
extra texture fetches.
