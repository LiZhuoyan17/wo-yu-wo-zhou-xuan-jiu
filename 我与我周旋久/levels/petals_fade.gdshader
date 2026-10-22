shader_type canvas_item;
render_mode blend_add, unshaded;

## 世界/视差层坐标下的 Floor 顶边 Y（= horizon / FLOOR_TOP_Y）
uniform float floor_y = 256.0;
## 穿过 Floor 后再过这么多像素完全消失
uniform float fade_band = 80.0;

varying float v_world_y;

void vertex() {
	v_world_y = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y;
}

void fragment() {
	vec4 col = texture(TEXTURE, UV) * COLOR;
	# 高于 Floor：正常；低于 Floor：在 fade_band 内平滑到 0
	float fade = 1.0 - smoothstep(floor_y, floor_y + fade_band, v_world_y);
	col.rgb *= fade;
	col.a *= fade;
	COLOR = col;
}
