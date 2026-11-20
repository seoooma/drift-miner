# 素材のクレジット

このゲームで使っている外部の素材は、どれも **CC0 1.0（パブリックドメイン）** です。
商用・非商用を問わず自由に使え、クレジットの表記は必須ではありませんが、感謝を込めて記載します。
CC0 の全文は [`assets/LICENSE-CC0-1.0.txt`](assets/LICENSE-CC0-1.0.txt) にあります。

見た目（機体・アイコン・地形・UI）はコードで線と単色の図形として描いています（下の「自作」）。
画像の素材は、演出に重ねる白い光の画像3枚だけです（下の「光の画像」）。

## 効果音（Kenney / www.kenney.nl、CC0）

| 使い道 | ファイル | 元の素材 |
| --- | --- | --- |
| ブロックを砕く音、鉱石の音、宝箱 | `break_*.ogg`、`ore_*.ogg`、`cache.ogg` | Impact Sounds |
| レーザー、ドリル、爆雷、爆発、移動 | `laser.ogg`、`drill.ogg`、`bomb.ogg`、`blast.ogg`、`move.ogg` | Sci-Fi Sounds |
| ボタン操作（選ぶ・購入・開く・閉じる） | `ui_select.ogg`、`ui_tick.ogg`、`ui_open.ogg`、`ui_close.ogg` | Interface Sounds（`select_001`、`tick_002`、`maximize_003`、`minimize_003`） |
| スキル習得 | `skill_up.ogg` | Digital Audio（`powerUp2`、mp3 から ogg に変換） |
| 船内の低いうなり（環境音のループ） | `ambient_hum.ogg` | Sci-Fi Sounds（`spaceEngineLow_001` を、継ぎ目なくループするようにつなぎ直したもの） |

Interface Sounds・Digital Audio・Sci-Fi Sounds は OpenGameArt.org で Kenney が CC0 で公開しているもの（kenney_interfaceSounds.zip、Digital_SFX_Set.zip、sci-fi_sounds.zip）から取得しました。

## 光の画像（Kenney「Particle Pack」/ www.kenney.nl、CC0）

白一色・濃さだけの画像にして、加算合成で重ねています（`assets/fx/`）。OpenGameArt.org の kenney_particlePack.zip から取得し、縮小しました。

| 使い道 | ファイル | 元の画像 |
| --- | --- | --- |
| 光の広がり・爆発の下に敷く柔らかい光 | `halo.png` | `circle_05` |
| 鉱石・遺物のきらめき、背景の星のきらめき | `glint.png` | `star_07` |
| 爆発で横に走る細い光 | `streak.png` | `flare_01` |

## 音楽

| 使い道 | ファイル | 作者・曲名 | ライセンス |
| --- | --- | --- | --- |
| BGM（ループ） | `assets/audio/bgm_lost_in_space.ogg` | HoliznaCC0「Lost In Space」（Free Music Archive） | CC0 1.0 |
| 遺物を見つけたときのジングル | `assets/audio/relic.ogg` | Beatscribe「treasure」（homebrew_vgm、SNES 風） | CC0 1.0 |
| 惑星を破壊したときのジングル | `assets/audio/clear.ogg` | Beatscribe「victory」（homebrew_vgm、SNES 風） | CC0 1.0 |

## フォント（SIL Open Font License 1.1）

| 使い道 | ファイル | フォント | ライセンス全文 |
| --- | --- | --- | --- |
| 数字と英字（等幅） | `fonts/ShareTechMono-Regular.ttf` | Share Tech Mono（Carrois Type Design） | [`fonts/OFL-ShareTechMono.txt`](fonts/OFL-ShareTechMono.txt) |
| 日本語（等幅、使う文字だけのサブセット） | `fonts/MPLUS1Code-Subset.ttf` | M PLUS 1 Code（The M+ FONTS Project） | [`fonts/OFL-MPLUS1Code.txt`](fonts/OFL-MPLUS1Code.txt) |
| 上の2つにない記号の予備 | `fonts/NotoSansJP-Subset.ttf` | Noto Sans JP（サブセット） | [`fonts/OFL.txt`](fonts/OFL.txt) |

どれも Google Fonts のリポジトリ（github.com/google/fonts）から取得しました。

## 自作

見た目の決まりごと（色・線の太さ・にじみ）は `scripts/neon.gd` に一か所でまとめています。
機体とボタンの線のアイコン、惑星の平らな塗りと階段状の輪郭線（`shaders/cells.gdshader`）、背景の方眼と星、
揺らぐ輪・四角い粒・ビームなどの演出、スキルマップは、すべてコードで描いています。
画面全体のごく弱い走査線と周辺減光（`shaders/screen.gdshader`）も自作です。
