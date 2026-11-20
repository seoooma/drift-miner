# 素材のクレジット

このゲームで使っている外部の素材は、どれも **CC0 1.0（パブリックドメイン）** です。
商用・非商用を問わず自由に使え、クレジットの表記は必須ではありませんが、感謝を込めて記載します。
CC0 の全文は [`assets/LICENSE-CC0-1.0.txt`](assets/LICENSE-CC0-1.0.txt) にあります。

画像は元の素材を縮小し、一部は色付けや合成をしています（UI の枠は、ガラス部分を暗い色で塗りつぶして不透明にしています）。

## 画像（Kenney / www.kenney.nl、CC0）

| 使い道 | ファイル | 元の素材 |
| --- | --- | --- |
| 機体（ドローン・ドリル・衛星・爆雷・ランス基地・ナノボット・母艦） | `assets/sprites/*.png` | Simple Space |
| 背景の地模様 | `assets/sprites/bg_tile.png` | Space Shooter Remastered（darkPurple） |
| 火花・光・煙・衝撃波などの粒子 | `assets/fx/*.png` | Particle Pack |
| 爆発のアニメーション | `assets/fx/explosion/`、`assets/fx/sonic/` | Explosion Pack |
| ボタン・パネルの枠 | `assets/ui/*.png` | UI Pack - Sci-Fi |

## 効果音（Kenney / www.kenney.nl、CC0）

| 使い道 | ファイル | 元の素材 |
| --- | --- | --- |
| ブロックを砕く音、鉱石の音、宝箱 | `break_*.ogg`、`ore_*.ogg`、`cache.ogg` | Impact Sounds |
| レーザー、ドリル、爆雷、爆発、スキル習得、移動 | `laser.ogg`、`drill.ogg`、`bomb.ogg`、`blast.ogg`、`skill.ogg`、`move.ogg` | Sci-Fi Sounds |
| ボタン操作 | `ui_*.ogg` | UI Audio |

## 音楽

| 使い道 | ファイル | 作者・曲名 | ライセンス |
| --- | --- | --- | --- |
| BGM（ループ） | `assets/audio/bgm_lost_in_space.ogg` | HoliznaCC0「Lost In Space」（Free Music Archive） | CC0 1.0 |
| 遺物を見つけたときのジングル | `assets/audio/relic.ogg` | Beatscribe「treasure」（homebrew_vgm、SNES 風） | CC0 1.0 |
| 惑星を破壊したときのジングル | `assets/audio/clear.ogg` | Beatscribe「victory」（homebrew_vgm、SNES 風） | CC0 1.0 |

## フォント

Noto Sans JP（サブセット）、SIL Open Font License 1.1。全文は [`fonts/OFL.txt`](fonts/OFL.txt)。

## 自作

惑星のブロックの立体表現（`shaders/cells.gdshader`）、スキルマップ、背景の星雲と星、ビームや照準の光は、コードで描いています。
