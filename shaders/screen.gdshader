shader_type canvas_item;
render_mode blend_mul, unshaded;
// 画面の質感（自作）。画面全体に乗算で重ねる、ごく弱い走査線と周辺減光。
// 色は足さず暗くするだけなので、黒地と線の見た目は変わらない。

uniform float scan_strength = 0.07;  // 走査線で暗くする量
uniform float scan_period = 3.0;     // 走査線の間隔（画面のピクセル）
uniform float vignette = 0.32;       // 四隅を暗くする量

void fragment() {
	float line = step(scan_period - 1.0, mod(FRAGCOORD.y, scan_period));
	float s = 1.0 - scan_strength * line;
	vec2 d = SCREEN_UV - 0.5;
	float v = 1.0 - vignette * smoothstep(0.45, 0.85, length(d * vec2(1.0, 0.85)) * 1.3);
	COLOR = vec4(vec3(s * v), 1.0);
}
