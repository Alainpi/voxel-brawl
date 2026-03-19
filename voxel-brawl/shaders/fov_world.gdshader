shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix, skip_vertex_transform;

const int N = 128;
uniform vec2  fov_points[N];
uniform vec2  prox_center = vec2(0.0);
uniform float prox_radius = 3.0;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

bool in_fov(vec2 p) {
	bool inside = false;
	int j = N - 1;
	for (int i = 0; i < N; i++) {
		vec2 a = fov_points[i];
		vec2 b = fov_points[j];
		if (((a.y > p.y) != (b.y > p.y)) &&
				(p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x)) {
			inside = !inside;
		}
		j = i;
	}
	return inside;
}

void fragment() {
	float depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;

	if (depth >= 0.9999) {
		// Sky / empty — always fog
		ALBEDO = vec3(0.0);
		ALPHA  = 0.85;
	} else {
		// Godot 4 depth reconstruction.
		// depth is already [0,1] on D3D12/Vulkan — no * 2 - 1 needed.
		// INV_PROJECTION_MATRIX is built to match Godot's SCREEN_UV convention.
		vec4 ndc      = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		vec4 view_pos = INV_PROJECTION_MATRIX * ndc;
		view_pos.xyz /= view_pos.w;
		vec3 world    = (INV_VIEW_MATRIX * vec4(view_pos.xyz, 1.0)).xyz;

		vec2 xz      = world.xz;
		bool visible = in_fov(xz) || length(xz - prox_center) < prox_radius;

		ALBEDO = vec3(0.0);
		ALPHA  = visible ? 0.0 : 0.85;
	}
}
