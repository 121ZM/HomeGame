# 第三方资源

## Kenney Input Prompts（CC0）

- **来源**：https://kenney.nl/assets/input-prompts （v1.5）
- **授权**：Creative Commons CC0 1.0 Universal（公共领域奉献）
  https://creativecommons.org/publicdomain/zero/1.0/
- **要不要署名**：**不要求**。CC0 允许商用、修改、再分发，无需署名。
  这里保留来源说明是出于礼貌与可追溯，不是授权要求。

### 本仓库里用了其中哪些

| 文件 | 来源 | 用途 |
|---|---|---|
| `kenney_input.ttf` | `Keyboard & Mouse/Fonts/kenney_input_keyboard_&_mouse.ttf` | 键位**图标字体**：大厅底部的「← → 选择」这类提示 |
| `kenney_input_map.txt` | 同目录 `..._map.txt` | 图标字形的码位对照表（PUA 区），查码位用 |
| `../assets/icons/ic_key_*.png` | `Keyboard & Mouse/Default/keyboard_*.png` | 同上几个键的位图版本，备而不用 |

### 为什么用字体而不是 PNG

键位图标要**跟着字号缩放、跟着墨色走**。位图做不到「和旁边的文字一样深、一样大」；
图标字体是单色的，改 `font_color` 就跟着变，所以那行提示里的箭头和「选择」两个字
是同色同高的，不会一深一浅。

只挑了真的会用到的几个码位（方向键、一对箭头），没有把 1500 个字形全抄进代码 ——
需要用新的键时，去 `kenney_input_map.txt` 查码位再加一个 `ICON_*` 常量即可
（见 `scripts/core/ui_kit.gd`）。

### 另一个包

`kenney_ui-pack.zip` 也下载过（同 CC0），但**没有采用** —— 那套是位图按钮/面板精灵，
和本项目「StyleBoxFlat 平涂 + 细描边」的做法不兼容（位图缩放会糊，也没法跟着主题变色）。
留在下载缓存里，没进仓库。
