shader_type spatial;
// Bullseye rings, drawn from UV. The Blender script gives every vertex a UV
// equal to its spot on the board's face, so the rings line up across the
// intact board and every shard.

uniform vec4 ring_color : source_color = vec4(0.9, 0.2, 0.18, 1.0);
uniform vec4 base_color : source_color = vec4(0.95, 0.95, 0.92, 1.0);
uniform float board_size = 0.6; // meters across the face
uniform vec3 ring_radii = vec3(0.27, 0.18, 0.09); // ring edges, outside in (meters)

void fragment() {
	float r = length(UV - vec2(0.5)) * board_size;
	vec3 c = base_color.rgb;
	if (r < ring_radii.x) c = ring_color.rgb;
	if (r < ring_radii.y) c = base_color.rgb;
	if (r < ring_radii.z) c = ring_color.rgb;
	ALBEDO = c;
	ROUGHNESS = 0.8;
}
