shader_type spatial;
render_mode blend_mix, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform vec3 marble_colour : source_color;
uniform vec3 marble_shadow : source_color;
uniform vec3 bronze_colour : source_color;
uniform vec3 inlay_colour : source_color;
uniform vec3 gold_colour : source_color;
uniform float is_ivory = 1.0;
uniform float role_mode = 0.0;
uniform float readability_lift = 0.0;
varying vec3 sculpt_pos;

void vertex() {
    sculpt_pos = VERTEX;
}

void fragment() {
    float y = sculpt_pos.y;
    float relief = COLOR.r;
    float facing = clamp(0.58 + NORMAL.y * 0.16 + NORMAL.x * 0.05, 0.0, 1.0);

    // Curvature is already baked in COLOR.r; avoid procedural fragment noise.
    vec3 marble = mix(marble_shadow, marble_colour, 0.76 + facing * 0.20);
    marble *= mix(0.98, 1.02, relief);

    vec3 bronze = bronze_colour * (0.72 + facing * 0.25);
    vec3 body = mix(bronze, marble, is_ivory);

    // The six supplied photographs are sampled offline onto each role. Green
    // carries polished-gold coverage and blue carries dark engraved coverage;
    // red remains the original geometric-relief bake.
    float reference_gold = smoothstep(0.65, 0.75, COLOR.g);
    float reference_dark = clamp(smoothstep(0.65, 0.75, COLOR.b), 0.0, 0.72);
    body = mix(body, inlay_colour, reference_dark * 0.24 * is_ivory);

    // Physical rings remain crisp at gameplay distance. Photo-derived gold adds
    // role-specific crown, harness, panel, and ornament placement without UVs.
    float lower_ring = smoothstep(-0.465, -0.448, y) * (1.0 - smoothstep(-0.420, -0.397, y));
    float plinth_ring = smoothstep(-0.335, -0.317, y) * (1.0 - smoothstep(-0.292, -0.270, y));
    float collar_ring = smoothstep(0.165, 0.185, y) * (1.0 - smoothstep(0.212, 0.235, y));
    float crown_ring = smoothstep(0.425, 0.445, y) * (1.0 - smoothstep(0.468, 0.487, y));
    float gold = clamp(max(reference_gold * 0.90, lower_ring + plinth_ring * 0.72 + collar_ring * 0.66 + crown_ring * 0.45), 0.0, 1.0);
    vec3 colour = mix(body, gold_colour, gold);

    float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 2.0);
    ALBEDO = colour;
    METALLIC = mix(0.0, 0.65, gold);
    METALLIC = mix(METALLIC, 0.60, (1.0 - is_ivory) * (1.0 - gold));
    ROUGHNESS = mix(mix(0.35, 0.25, 1.0 - is_ivory), 0.22, gold);
    // Compatibility renderer has no custom-shader clearcoat outputs. Low
    // roughness plus strong dielectric specular provides the mobile-safe glaze.
    SPECULAR = 0.50;
    vec3 ivory_rim = vec3(0.96, 0.82, 0.58) * rim * 0.055 * is_ivory;
    vec3 gold_glow = vec3(0.83, 0.68, 0.21) * gold * 0.12;
    EMISSION = colour * readability_lift + ivory_rim + gold_glow;
}
