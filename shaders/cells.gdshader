shader_type canvas_item;
// 惑星のマス目の見た目。1テクセル = 1マスのテクスチャを、立体的なブロックとして描く。
// ・上と左に光、下と右に影（ベベル）
// ・外に面した辺は明るい縁取り、地表の下には柔らかい陰
// ・鉱石のマス（アルファ 0.9 前後）はときどききらめく

uniform vec2 grid = vec2(113.0, 113.0);
uniform float time = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 g = UV * grid;
	ivec2 cell = ivec2(floor(g));
	vec4 c = texelFetch(TEXTURE, cell, 0);
	if (c.a < 0.05) {
		discard;
	}
	vec2 f = fract(g);
	vec3 col = c.rgb;
	// マスごとの細かいむら
	float n = hash(vec2(cell) + floor(f * 4.0) * 0.37);
	col *= 0.94 + 0.08 * n;
	// ベベル
	float e = 0.13;
	float hl = max(step(f.y, e), step(f.x, e));
	float sh = max(step(1.0 - e, f.y), step(1.0 - e, f.x));
	col *= 1.0 + 0.16 * hl - 0.24 * sh;
	// 外に面した辺の縁取りと、その奥の陰
	ivec2 mx = ivec2(grid) - ivec2(1);
	float up = cell.y > 0 ? step(0.05, texelFetch(TEXTURE, cell + ivec2(0, -1), 0).a) : 0.0;
	float dn = cell.y < mx.y ? step(0.05, texelFetch(TEXTURE, cell + ivec2(0, 1), 0).a) : 0.0;
	float lf = cell.x > 0 ? step(0.05, texelFetch(TEXTURE, cell + ivec2(-1, 0), 0).a) : 0.0;
	float rt = cell.x < mx.x ? step(0.05, texelFetch(TEXTURE, cell + ivec2(1, 0), 0).a) : 0.0;
	float rim = 0.0;
	rim = max(rim, (1.0 - up) * smoothstep(0.22, 0.0, f.y));
	rim = max(rim, (1.0 - lf) * smoothstep(0.22, 0.0, f.x));
	rim = max(rim, (1.0 - dn) * smoothstep(0.78, 1.0, f.y));
	rim = max(rim, (1.0 - rt) * smoothstep(0.78, 1.0, f.x));
	col = mix(col, col * 1.35 + vec3(0.06, 0.07, 0.09), rim * 0.8);
	// 鉱石のきらめき
	if (c.a < 0.95) {
		float ph = hash(vec2(cell)) * 6.283;
		float tw = pow(max(0.0, sin(time * 1.7 + ph)), 24.0);
		float d = length(f - vec2(0.3 + 0.4 * hash(vec2(cell) + 1.0), 0.3 + 0.4 * hash(vec2(cell) + 2.0)));
		col += vec3(1.0, 0.95, 0.85) * tw * smoothstep(0.35, 0.0, d) * 0.9;
		col *= 1.08;
	}
	COLOR = vec4(col, 1.0);
}
