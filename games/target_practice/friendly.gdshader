shader_type spatial;
// A friendly target: Tim's cartoon silhouette in blue, with a smiley face on
// the head and a white star on the chest. Hitting it costs points.
// UV is the position on the face in meters + 0.5 (see
// tools/blender/make_cartoon_shards.py), so these numbers are in meters and
// match RangeTarget.HEAD_CENTER / BULL_CENTER.

uniform vec4 body_color : source_color = vec4(0.16, 0.45, 0.85, 1.0);
uniform vec4 face_color : source_color = vec4(1.0, 0.86, 0.25, 1.0);
uniform vec4 ink_color : source_color = vec4(0.08, 0.08, 0.14, 1.0);

const vec2 HEAD_CENTER = vec2(0.0, 0.314);
const float HEAD_RADIUS = 0.147;
const vec2 CHEST_CENTER = vec2(0.0, -0.157);

void fragment() {
	vec2 p = UV - vec2(0.5);
	p.y = -p.y;
	vec3 c = body_color.rgb;
	vec2 h = p - HEAD_CENTER;
	float hr = length(h);
	if (hr < HEAD_RADIUS - 0.012) {
		c = face_color.rgb;
		if (length(h - vec2(-0.05, 0.035)) < 0.02 || length(h - vec2(0.05, 0.035)) < 0.02) {
			c = ink_color.rgb; // Eyes.
		}
		vec2 m = h - vec2(0.0, 0.01);
		float d = length(m);
		if (m.y < -0.02 && d > 0.07 && d < 0.095) {
			c = ink_color.rgb; // Smile.
		}
	} else if (p.y > 0.173) {
		c = ink_color.rgb; // Outline round the face.
	}
	// A white star on the chest, so friendlies read at a distance.
	vec2 s = p - CHEST_CENTER;
	float a = atan(s.y, s.x);
	if (length(s) < 0.085 + 0.045 * cos(5.0 * (a - 1.5708))) {
		c = vec3(1.0);
	}
	ALBEDO = c;
	ROUGHNESS = 0.8;
}
