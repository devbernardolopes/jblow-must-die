shader_type canvas_item;
render_mode blend_mix;

// Clips the minimap Control to a circle or a (rounded) rectangle.
// local_position is captured in vertex(), where VERTEX is local space; in
// fragment() VERTEX is screen space and would break under canvas stretch.

uniform vec2 rect_size = vec2(220.0, 220.0);
uniform int map_shape : hint_range(0, 1) = 1; // 0 = rectangle, 1 = circle
uniform float corner_radius : hint_range(0.0, 64.0) = 0.0;

varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec2 half_size = rect_size * 0.5;
	vec2 point = local_position - half_size;
	float distance_to_edge = 0.0;

	if (map_shape == 1) {
		distance_to_edge = length(point) - min(half_size.x, half_size.y);
	} else {
		float radius = min(corner_radius, min(half_size.x, half_size.y));
		vec2 corner = abs(point) - half_size + vec2(radius);
		distance_to_edge = length(max(corner, vec2(0.0))) + min(max(corner.x, corner.y), 0.0) - radius;
	}

	COLOR.a *= 1.0 - smoothstep(-1.0, 0.5, distance_to_edge);
}
