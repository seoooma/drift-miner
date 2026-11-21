shader_type canvas_item;
// 画面の衝撃波。GDQuest「Godot Shaders」の shockwave.gdshader（MIT License, Copyright (c) 2020-present GDQuest）を元にしたもの。
// https://github.com/gdquest-demos/godot-shaders/blob/master/godot/Shaders/shockwave.gdshader
// 元は「マスク画像の濃さだけ画面をずらす」。ここでは輪の画像（Kenney Particle Pack の circle_04）をマスクにして、
// その下の画面を輪の中心から外へずらす（画面テクスチャを読む形に直した）。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float displacement_amount = 0.0;

void fragment() {
	float mask = texture(TEXTURE, UV).a;

	// Displace by the torus mask（輪の中心から外へ）
	vec2 dir = normalize(UV - 0.5 + 1e-5);
	vec2 displacement_uv = SCREEN_UV - dir * mask * displacement_amount;

	COLOR = vec4(texture(screen_tex, displacement_uv).rgb, mask > 0.01 ? 1.0 : 0.0);
}
