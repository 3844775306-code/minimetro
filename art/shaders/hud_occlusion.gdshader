shader_type canvas_item;

// Screen-space "ghost" mask for HUD corner groups. Non-interactive pixels
// remain opaque; a group whose rectangle contains a station fades back so the
// station remains visible. Input pass-through is handled by Hud.ui_ghost_at().

uniform vec2 viewport_size = vec2(2400.0, 1200.0);
uniform vec4 tl_rect = vec4(0.0);
uniform vec4 tr_rect = vec4(0.0);
uniform vec4 br_rect = vec4(0.0);
uniform float tl_ghost = 0.0;
uniform float tr_ghost = 0.0;
uniform float br_ghost = 0.0;

float inside_rect(vec2 p, vec4 rect) {
	if (rect.z <= 0.0 || rect.w <= 0.0) {
		return 0.0;
	}
	return step(rect.x, p.x) * step(rect.y, p.y)
		* step(p.x, rect.x + rect.z) * step(p.y, rect.y + rect.w);
}

void fragment() {
	vec2 p = SCREEN_UV * viewport_size;
	float ghost = 0.0;
	ghost = max(ghost, tl_ghost * inside_rect(p, tl_rect));
	ghost = max(ghost, tr_ghost * inside_rect(p, tr_rect));
	ghost = max(ghost, br_ghost * inside_rect(p, br_rect));
	// Keep a faint trace instead of fully removing the HUD.
	float alpha = mix(1.0, 0.20, clamp(ghost, 0.0, 1.0));
	COLOR.a *= alpha;
}
