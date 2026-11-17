shader_type canvas_item;
render_mode blend_mul;

// 极轻的纸纹颗粒：整个屏幕乘上一层白噪声，避免大色块显得"廉价发糊"。
uniform float grain : hint_range(0.0, 0.12) = 0.035;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 pixel = SCREEN_UV * vec2(1920.0, 1080.0);
	float n = hash(floor(pixel));
	float v = 1.0 - (n - 0.5) * grain * 2.0;
	COLOR = vec4(vec3(v), 1.0);
}
