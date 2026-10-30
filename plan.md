1. **Prepare the New 3D Models:** The user wants to add a new set of 3D models (ebony) which we have already extracted from `.glb` files, decimated, resized to match the board dimensions, and converted to `.obj` format in `assets/models/ebony`.
2. **Register the New Models:**
   - Add a new dictionary `PIECE_MODELS_EBONY` in `src/main/main.gd`.
   - Update `_piece_models()` in `src/main/main.gd` to return `PIECE_MODELS_EBONY` for the "ebony" set.
3. **Add the New Theme to Configuration:**
   - In `src/main/main.gd`, add `"ebony"` to the `PIECE_THEME_ORDER` array.
   - Extend `PIECE_THEMES` dictionary with an `"ebony"` theme configuration, specifying `"model_set": "ebony"` and defining appropriate colors and material properties for the set (likely mimicking dark ebony wood and light contrasting wood like maple, similar to `royal_wood`).
4. **Verification:** Run a godot test or review UI manually to ensure the new piece theme displays.
5. **Pre-commit checks:** Complete pre commit steps to make sure proper testing, verifications, reviews and reflections are done.
6. **Submission:** Submit the changes with branch `feature/ebony-pieces`.
