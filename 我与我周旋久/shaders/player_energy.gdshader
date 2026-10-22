shader_type canvas_item;
render_mode unshaded, blend_mix;

// 能量白圆：径向渐变 + 边缘 Rim Light
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 mid_color : source_color = vec4(0.82, 0.92, 1.0, 0.85);
uniform vec4 rim_color : source_color = vec4(1.0, 0.98, 0.9, 1.0);
uniform float rim_width : hint_range(0.02, 0.35) = 0.12;
uniform float rim_intensity : hint_range(0.0, 4.0) = 1.8;
uniform float soft_edge : hint_range(0.001, 0.12) = 0.04;
uniform float inner_glow : hint_range(0.0, 2.0) = 0.65;

void fragment() {
	// 以贴图中心为圆：0=中心，1=边缘
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered) * 2.0;

	// 柔边圆形遮罩
	float alpha_mask = 1.0 - smoothstep(1.0 - soft_edge, 1.0, dist);

	// 内部径向渐变（中心亮 → 外圈偏冷白）
	float body_t = smoothstep(0.0, 0.85, dist);
	vec4 body = mix(core_color, mid_color, body_t);

	// 中心额外辉光，增加“厚度”
	float glow = (1.0 - smoothstep(0.0, 0.45, dist)) * inner_glow;
	body.rgb += vec3(glow);

	// Rim Light：靠近边缘时提亮一圈
	float rim = smoothstep(1.0 - rim_width * 2.0, 1.0 - rim_width, dist);
	rim *= (1.0 - smoothstep(1.0 - rim_width, 1.0, dist));
	body.rgb += rim_color.rgb * rim * rim_intensity;
	body.a *= alpha_mask;

	// 保留原贴图亮度信息（白贴图则几乎等于 body）
	vec4 tex = texture(TEXTURE, UV);
	COLOR = body * tex;
}
