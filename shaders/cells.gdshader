shader_type canvas_item;
render_mode blend_mix;
// 惑星のマス目の見た目。1テクセル = 1マスのテクスチャを、平らな塗りで描く。
// ・岩は惑星ごとの暗い単色。マスの中の線や質感は付けない。
// ・中身の詰まったマスと空きの境目に、2px の白い階段状の輪郭線を引く。
// ・輪郭線の外側（空き側）に、白のにじみ（約40%から消えていく）を描く。
// ・鉱石（アルファ 0.9 前後）は暗めの鉱石の色で、内側に 1px の明るい縁を付ける。
// 線の太さは画面のピクセルで決める（fwidth でカメラの倍率に合わせる）。

uniform vec2 grid = vec2(113.0, 113.0);
uniform vec4 line_col : source_color = vec4(0.91, 0.925, 0.937, 1.0);
uniform float line_px = 2.0;
uniform float glow_px = 6.0;

void fragment() {
	vec2 g = UV * grid;
	ivec2 cell = ivec2(floor(g));
	vec2 f = fract(g);
	// 1 画面ピクセルが何マスぶんか
	vec2 px = max(fwidth(g), vec2(1e-4));
	vec4 c = texelFetch(TEXTURE, cell, 0);
	ivec2 mx = ivec2(grid) - ivec2(1);
	// 上下左右と斜めのマスが詰まっているか（範囲外は空き）
	float up = cell.y > 0 ? step(0.05, texelFetch(TEXTURE, cell + ivec2(0, -1), 0).a) : 0.0;
	float dn = cell.y < mx.y ? step(0.05, texelFetch(TEXTURE, cell + ivec2(0, 1), 0).a) : 0.0;
	float lf = cell.x > 0 ? step(0.05, texelFetch(TEXTURE, cell + ivec2(-1, 0), 0).a) : 0.0;
	float rt = cell.x < mx.x ? step(0.05, texelFetch(TEXTURE, cell + ivec2(1, 0), 0).a) : 0.0;
	float ul = (cell.x > 0 && cell.y > 0) ? step(0.05, texelFetch(TEXTURE, cell + ivec2(-1, -1), 0).a) : 0.0;
	float ur = (cell.x < mx.x && cell.y > 0) ? step(0.05, texelFetch(TEXTURE, cell + ivec2(1, -1), 0).a) : 0.0;
	float dl = (cell.x > 0 && cell.y < mx.y) ? step(0.05, texelFetch(TEXTURE, cell + ivec2(-1, 1), 0).a) : 0.0;
	float dr = (cell.x < mx.x && cell.y < mx.y) ? step(0.05, texelFetch(TEXTURE, cell + ivec2(1, 1), 0).a) : 0.0;
	// 画面ピクセルでの、各辺までの距離
	float dt = f.y / px.y;
	float db = (1.0 - f.y) / px.y;
	float dlx = f.x / px.x;
	float drx = (1.0 - f.x) / px.x;

	if (c.a < 0.05) {
		// 空き：となりの詰まったマスの縁から、にじみだけを描く
		float d = 1e4;
		if (up > 0.5) d = min(d, dt);
		if (dn > 0.5) d = min(d, db);
		if (lf > 0.5) d = min(d, dlx);
		if (rt > 0.5) d = min(d, drx);
		if (ul > 0.5) d = min(d, length(vec2(dlx, dt)));
		if (ur > 0.5) d = min(d, length(vec2(drx, dt)));
		if (dl > 0.5) d = min(d, length(vec2(dlx, db)));
		if (dr > 0.5) d = min(d, length(vec2(drx, db)));
		float k = clamp(1.0 - d / glow_px, 0.0, 1.0);
		if (k <= 0.0) {
			discard;
		}
		COLOR = vec4(line_col.rgb, 0.4 * k * k);
	} else {
		vec3 col = c.rgb;
		// 鉱石：内側に 1px の明るい縁
		if (c.a < 0.95) {
			float e = min(min(dt, db), min(dlx, drx));
			if (e < 1.0) {
				col = min(col * 1.9 + vec3(0.06), vec3(1.0));
			}
		}
		// 外に面した辺の輪郭線（内側に line_px）。へこんだ角も切れ目なくつなぐ。
		float o = 0.0;
		if (up < 0.5 && dt < line_px) o = 1.0;
		if (dn < 0.5 && db < line_px) o = 1.0;
		if (lf < 0.5 && dlx < line_px) o = 1.0;
		if (rt < 0.5 && drx < line_px) o = 1.0;
		if (ul < 0.5 && dlx < line_px && dt < line_px) o = 1.0;
		if (ur < 0.5 && drx < line_px && dt < line_px) o = 1.0;
		if (dl < 0.5 && dlx < line_px && db < line_px) o = 1.0;
		if (dr < 0.5 && drx < line_px && db < line_px) o = 1.0;
		col = mix(col, line_col.rgb, o);
		COLOR = vec4(col, 1.0);
	}
}
