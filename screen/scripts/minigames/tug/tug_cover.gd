class_name TugCover
extends Control

## 拔河的**封面画**：大厅磁贴里那块图形区。
##
## 定位：这是玩家在客厅里对这个玩法的**第一眼**。磁贴上只有「拔河 / 2-4 人」两行字是
## 认不出这是个什么游戏的 —— 用户对这一版的反馈原话就是「就几个字太粗糙了」。
##
## 画法：把这块 3D 场地**按同一套配色压成一张 2D 微缩图** ——
## 草地、左右地界、白中线、棕绳、墨色绳结、两根队色出线柱，一个不少。
## 好处有两个：
##   1. 大厅里看到的和点进去看到的是**同一个东西**，不会「点进去怎么变样了」；
##   2. 颜色全部来自同一处（`tug_field.gd` 用的那几支 + `PlayerPalette`），
##      改场地配色时这里跟着一起对，不会各走各的。
##
## **这块归玩法自己**，和 `TugField` 是同一条规矩：框架只给一块画板和生命周期，
## 不认识这里面画的是什么。所以删掉 `scripts/minigames/tug/` 整个目录，框架照常跑。
##
## 坐标全用相对值（按 `size` 算），因为框架那边磁贴高度是 `EXPAND_FILL` 的 ——
## 写死像素的话换一版布局就得回来重算。

## 草地色。和 `tug_field.gd` 的 `_build_ground()` 是同一个值。
const GROUND := Color("cdd7bd")
## 绳子色。和 `tug_field.gd` 的 `_build_rope()` 是同一个值。
const ROPE := Color("a9825a")
## 中线色。
const CENTER_LINE := Color("fffdf5")

## 地平线在画面里的高度比例：上面那条是「远处的天」，下面是场地。
const HORIZON := 0.26
## 场地的远边比近边窄，做出「往里退」的感觉（真场地是 3D 的，这里用梯形代替透视）。
const FIELD_FAR_L := 0.30
const FIELD_FAR_R := 0.70
const FIELD_NEAR_L := 0.02
const FIELD_NEAR_R := 0.98

## 两根出线柱的横向位置。绳就绷在这两根柱子之间 —— 和被拔过它就算赢那条规则对齐。
const POST_L := 0.100
const POST_R := 0.865
const POST_W := 0.035
const POST_TOP := 0.470
const POST_BOTTOM := 0.655

## 绳子：横贯两根柱子，位置略低于画面中线（近处的绳子在透视里更靠下）。
const ROPE_TOP := 0.600
const ROPE_H := 0.055

## 绳结。**故意偏在中线左边一点** —— 静态图也要能一眼看出「绳子是会被拉动的」。
## 恒定用墨色，不跟队色跑（理由见 `tug_field.gd`：位置已经说清楚了，颜色留给两根柱子）。
const KNOT_L := 0.440
const KNOT_W := 0.045
const KNOT_TOP := 0.545
const KNOT_H := 0.165


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 尺寸由框架的磁贴决定，第一次 `_draw` 时可能还是 0 —— 不重画就永远是一片空白。
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	# 还没被摆过位（size 为 0）就直接不画：按 0 尺寸算出来的比例全是 0，
	# `draw_colored_polygon` 收到退化多边形会让人以为「玩法画崩了」。
	if w < 2.0 or h < 2.0:
		return

	# 远景：地平线以上。把草地往纸白插值一档，读作「远处」——
	# 不用渐变（全项目的平涂原则），一块平色就够。
	draw_rect(Rect2(0.0, 0.0, w, h * HORIZON), UiKit.tint(GROUND, 0.45))

	# 地平线以下**先整幅铺草地**：场地是个「近宽远窄」的梯形，只画梯形的话，
	# 远边两侧会露出底下的底色三角，看着像画坏了。先铺满就自然盖住。
	draw_rect(Rect2(0.0, h * HORIZON, w, h * (1.0 - HORIZON)), GROUND)

	# 场地：一个从远边向近边张开的梯形（压在上面只是为了让边界更明确）
	draw_colored_polygon(PackedVector2Array([
		Vector2(w * FIELD_NEAR_L, h),
		Vector2(w * FIELD_FAR_L, h * HORIZON),
		Vector2(w * FIELD_FAR_R, h * HORIZON),
		Vector2(w * FIELD_NEAR_R, h),
	]), GROUND)

	# 左右地界：两块斜过来的梯形，各占场地的一半。
	# 颜色走 `PlayerPalette.color_for_team` + `UiKit.tint(…, 0.6)`，
	# 和 `tug_field.gd` 的 `_build_zones()` 用的是同一个色源和同一个插值比例 ——
	# 大厅里看到的浅红/浅蓝，就是待会儿场地上两队的颜色。
	draw_rect(Rect2(0.0, h * HORIZON, w * 0.5, h * (1.0 - HORIZON)),
		UiKit.tint(PlayerPalette.color_for_team(0), 0.6))
	draw_rect(Rect2(w * 0.5, h * HORIZON, w * 0.5, h * (1.0 - HORIZON)),
		UiKit.tint(PlayerPalette.color_for_team(1), 0.6))

	# 中线：全场最亮的一条，观众判断「现在谁占优」的唯一基准。
	draw_line(
		Vector2(w * 0.5, h * HORIZON), Vector2(w * 0.5, h),
		CENTER_LINE, maxf(2.0, w * 0.012)
	)

	# 绳 + 两根出线柱 + 绳结。顺序不能换：结要骑在绳上，柱要压在绳端。
	draw_rect(Rect2(w * POST_L, h * ROPE_TOP, (POST_R + POST_W - POST_L) * w, h * ROPE_H), ROPE)
	draw_rect(Rect2(w * POST_L, h * POST_TOP, w * POST_W, h * (POST_BOTTOM - POST_TOP)),
		PlayerPalette.color_for_team(0))
	draw_rect(Rect2(w * POST_R, h * POST_TOP, w * POST_W, h * (POST_BOTTOM - POST_TOP)),
		PlayerPalette.color_for_team(1))
	draw_rect(Rect2(w * KNOT_L, h * KNOT_TOP, w * KNOT_W, h * KNOT_H), UiKit.INK)
