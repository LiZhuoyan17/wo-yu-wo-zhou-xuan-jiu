shader_type canvas_item;
// 主角白圆能量体：径向厚度 + 边缘呼吸光

uniform vec4 core_color : source_color = vec4(1.0, 0.98, 0.95, 1.0);
uniform vec4 rim_color : source_color = vec4(0.75, 0.88, 1.0, 1.0);
uniform vec4 gold_tint : source_color = vec4(1.0, 0.92, 0.7, 1.0);
uniform float rim_width : hint_range(0.05, 0.45) = 0.22;
uniform float breath_strength : hint_range(0.0, 0.5) = 0.12;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv) * 2.0; // 0 中心 → 1 边缘

	// 圆盘 mask
	float alpha = 1.0 - smoothstep(0.82, 1.0, dist);

	// 内部径向：中心偏暖白，外圈淡蓝金
	vec3 mid = mix(core_color.rgb, gold_tint.rgb, smoothstep(0.15, 0.55, dist));
	vec3 col = mix(mid, rim_color.rgb, smoothstep(0.45, 0.9, dist));

	// 边缘发光 + 呼吸
	float rim = smoothstep(1.0 - rim_width, 1.0, dist);
	float breath = 0.65 + 0.35 * sin(TIME * 2.2);
	col += rim_color.rgb * rim * breath_strength * breath * 2.5;

	// 中心轻微高光，增加体积感
	float highlight = exp(-dist * dist * 6.0) * 0.25;
	col += vec3(highlight);

	COLOR = vec4(col, alpha * COLOR.a);
}
