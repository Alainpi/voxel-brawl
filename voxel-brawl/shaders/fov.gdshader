shader_type canvas_item;

const int N = 128;

// Ground-level polygon: shadow boundary follows the floor, covers ground behind obstacles.
uniform vec2 fov_points_lo[N];
// Elevated polygon: keeps wall faces and obstacle tops visible.
uniform vec2 fov_points_hi[N];

uniform bool  fov_active   = false;
uniform vec2  prox_center  = vec2(0.5);
uniform float prox_radius  = 0.0;

// Ray-casting point-in-polygon test (Jordan curve theorem).
bool in_fov_lo(vec2 p) {
	bool inside = false;
	int j = N - 1;
	for (int i = 0; i < N; i++) {
		vec2 a = fov_points_lo[i];
		vec2 b = fov_points_lo[j];
		if (((a.y > p.y) != (b.y > p.y)) &&
				(p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x)) {
			inside = !inside;
		}
		j = i;
	}
	return inside;
}

bool in_fov_hi(vec2 p) {
	bool inside = false;
	int j = N - 1;
	for (int i = 0; i < N; i++) {
		vec2 a = fov_points_hi[i];
		vec2 b = fov_points_hi[j];
		if (((a.y > p.y) != (b.y > p.y)) &&
				(p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x)) {
			inside = !inside;
		}
		j = i;
	}
	return inside;
}

void fragment() {
	// Visible if inside either polygon (union) or within proximity circle.
	// lo polygon handles ground-level occlusion; hi polygon handles elevated surfaces.
	bool visible = !fov_active
		|| in_fov_lo(UV)
		|| in_fov_hi(UV)
		|| length(UV - prox_center) < prox_radius;
	COLOR = visible ? vec4(0.0, 0.0, 0.0, 0.0) : vec4(0.0, 0.0, 0.0, 0.92);
}
