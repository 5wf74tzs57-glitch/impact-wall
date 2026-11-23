shader_type spatial;
// A friendly target: a smiley face on a teal board. Hitting it costs points.
// Drawn from UV like bullseye.gdshader, so the face continues across shards.

uniform vec4 board_color : source_color = vec4(0.16, 0.62, 0.66, 1.0);
uniform vec4 face_color : source_color = vec4(1.0, 0.86, 0.25, 1.0);
uniform vec4 ink_color : source_color = vec4(0.12, 0.1, 0.08, 1.0);
uniform float board_size = 0.6; // meters across the face

void fragment() {
	// Position on the face in meters, (0,0) at the center, +y up.
	vec2 p = (UV - vec2(0.5)) * board_size;
	p.y = -p.y;
	vec3 c = board_color.rgb;
	float r = length(p);
	if (r < 0.24) {
		c = face_color.rgb;
		// Eyes.
		if (length(p - vec2(-0.08, 0.06)) < 0.03 || length(p - vec2(0.08, 0.06)) < 0.03) {
			c = ink_color.rgb;
		}
		// Smile: a band of a circle, lower half only.
		vec2 m = p - vec2(0.0, 0.02);
		float d = length(m);
		if (m.y < -0.03 && d > 0.11 && d < 0.145) {
			c = ink_color.rgb;
		}
	}
	if (r > 0.24 && r < 0.255) {
		c = ink_color.rgb; // Outline around the face.
	}
	ALBEDO = c;
	ROUGHNESS = 0.8;
}
