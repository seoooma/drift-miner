shader_type canvas_item;
render_mode unshaded;
// 衝撃の画面効果（自作）。大きな出来事の一瞬だけ表示する（ふだんは描かないので負担はない）。
// ・衝撃波：画面の一点から広がる輪の所だけ、画面を外へ押し出すように歪める
// ・色ずれ：中心から外へ、赤と青を少しずらす（色収差）
// ・閃光：画面の明るい所をさらに明るくする（黒地はほぼ黒のまま）
// 惑星と演出の上、HUD の下に描くので、文字や枠は歪まない。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec4 waves[4];        // xy = 中心（画面の UV）, z = 半径（画面の短い辺に対する割合）, w = 強さ（0 で無効）
uniform float aspect = 1.0;   // 画面の横 / 縦
uniform float aberration = 0.0;  // 色ずれの量（0〜1）
uniform vec4 flash_col = vec4(0.0);  // rgb と、a = 足す量

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 asp = aspect >= 1.0 ? vec2(aspect, 1.0) : vec2(1.0, 1.0 / aspect);
	vec2 push = vec2(0.0);
	float ringlight = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 w = waves[i];
		if (w.w <= 0.0) {
			continue;
		}
		vec2 d = (uv - w.xy) * asp;
		float dist = length(d);
		float width = 0.025 + w.z * 0.18;
		float x = (dist - w.z) / width;
		float f = exp(-x * x * 2.0) * w.w;
		push += (d / max(dist, 1e-4)) * f * 0.018 / asp;
		ringlight += f;
	}
	uv -= push;
	vec2 ca = (uv - 0.5) * aberration * 0.006 + push * 0.25;
	vec3 c;
	c.r = texture(screen_tex, uv + ca).r;
	c.g = texture(screen_tex, uv).g;
	c.b = texture(screen_tex, uv - ca).b;
	c += vec3(0.04) * ringlight;
	// 閃光は明るい所ほど強く足す（黒い宇宙は黒いまま）
	c = c * (1.0 + flash_col.a * 1.5) + flash_col.rgb * flash_col.a * 0.05;
	COLOR = vec4(c, 1.0);
}
