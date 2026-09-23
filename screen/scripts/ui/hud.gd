class_name Hud
extends Control

## 大屏 HUD —— 「长什么样」全在这里；main.gd 只负责把数据算好喂进来。
##
## ## 两屏，互斥显示
##
## **大厅和玩法是两个界面，不是一屏里的两块。**
## 状态机本来就把它们分开了（`GameFlow.State.LOBBY` 是独立状态，`Lobby` 也是纯逻辑类），
## 但视图层曾经没跟上：3D 场地在启动时搭一次就常驻，于是大厅里也画着拔河的绳子和出线柱 ——
## 看着像「游戏已经摆好，就等你按开始」，而且**等第二个玩法进来会直接串味**。
##
##   · **大厅**（`_lobby_root`，整屏）：只回答两件事 —— **有哪些玩法、谁在线**。
##     状态条 / 玩法卡网格 / 选中玩法的自述 / 在座玩家 / 操作提示。**不画任何游戏场地。**
##   · **玩法**（`_play_root`）：**一条顶部细横条 + 一整片全宽舞台**。
##     · 顶部细横条（`_play_bar`）：只放「剩余时间 + 比分」，靠左，细。
##       **不再有左信息栏** —— 它曾经固定占 `UiKit.PANEL_W`(780) 宽，把 3D 场地压到右边
##       一小条、相机还得故意偏左去躲它（见 `tug_field.gd` 的旧注释）。用户明确要求
##       「只要游戏内容，左边那一块去掉」，于是整条左栏连同「玩什么名字 / 在座玩家名单」
##       一起删掉了：对局中玩家盯的是绳子，不是玩法名。
##     · 全宽舞台：整屏留给 3D 场地，四周不放常驻 HUD；
##       只在这一刻才有的东西才浮上来（倒计时 / 答题中），并且**避开顶部横条**。
##
## 「现在显示哪一屏」这件事**只写在一个地方**（`update_view`）。分散到各个分支去写，
## 早晚会有一条分支忘了关，症状是两屏叠在一起。
##
## ## 为什么接口是 `update_view(model)` 而不是让 HUD 直接读 flow / server
##
## 视图只认「给我什么画什么」。玩法换、网络层换成摄像头或专用硬件，HUD 一行不用改；
## 反过来也成立 —— 可以单独喂一组假数据把界面画出来看，不必真的开一局。
## 更要紧的是：**每帧读取的数据在哪算只有一个地方**，不会一半在 main 一半在 HUD。

## 结算牌宽度（居中牌，比信息栏宽一点）
const RESULT_WIDTH := 1350.0

## 对局屏顶部细横条的高度（逻辑 / 1080 基准）。
##
## **故意比大厅状态条矮得多**：大厅那条是主角（那一屏的全部交互都在它下面），
## 对局屏这条是配角 —— 对局中玩家盯的是绳子和两边比分，横条只负责「还剩几秒、几比几」。
## 做成跟大厅一样高会把场地往下压，而且抢注意力。
##
## 数值来源：`FONT_BIG`(54) 的真实行高是 74（`font.get_height`），
## 上下各留 14 的内边距 → 74 + 28 = 102；再叠一点阴影余量，取 100 偏紧、够用。
const PLAY_BAR_H := 96.0

## 大厅详情行的可用文字宽度。右边要留给页点，所以比整行窄一截。
## 理由同 `UiKit.VIEW_W`：给窄了只是多折一行，给宽了会撑破布局。
const LOBBY_DETAIL_W := UiKit.VIEW_W - UiKit.MARGIN * 2.0 - 240.0

## 磁贴封面的最小高度 = **0，封面的高度完全由磁贴决定**。
##
## 曾经写死 180（「免得详情行多出一行字时封面被挤成一条缝」）—— 这个下限在
## **1920x1080 全屏**下是安全的，但项目实际跑的窗口只有 **1280x720**
## （`window_width_override/height_override`，为了让 720p 笔记本和远程桌面放得下）。
## 720 逻辑高度下，状态条(106) + 标题区 + 详情行 + 底栏(84) + 四个间距(96)
## 已经吃掉约 500，网格只剩 ~220。这时一个 180 的**硬下限**会把磁贴撑破：
## 磁贴整体变 ~397 高、溢出网格盒，而上半部分被**裁掉** ——
## 实测封面只剩 73 逻辑像素（截图里量出 89px / 缩放 1.219），
## 而磁贴底部（药丸）也被压出了可视范围。
##
## 所以：**不给下限**。封面的高度 = 磁贴高度 − 文字块，完全由真实可用空间决定。
## 要保证封面够看，该调的是上面那些元素的内边距，不是给封面加地板。
const COVER_MIN_H := 0.0

## 空位磁贴的节点名（自检要把它和真玩法的磁贴分开数）
const NEXT_SLOT_NAME := "next_slot_tile"
## 页点行的节点名（自检验「只有一页时不画页点」）
const PAGER_NAME := "lobby_pager"

# ------------------------------------------------------------------ 节点

## 状态条右端要不要显示「收 N · 丢 N」这套**链路统计**。
##
## 它是真机调试用的：手机连上了大屏却没反应，第一件事就是看丢包数涨不涨。
## 但它是**调试信息**，不该常驻在客厅的大屏上 —— 实拍里那行字和「在线 4 / 8」抢注意力，
## 是这一屏少数几个「不像成品」的地方。
##
## 所以默认由 main.gd 按运行环境决定（无头 / debug 构建打开，成品构建关闭），
## 也可以用 `--link-hud` / `--no-link-hud` 强制。**必须在 `setup()` 之前设好** ——
## 状态条是那时候造的，晚了就只能改可见性、留着一块空白。
var show_link_stats := false

## 状态条上画几个**席位圆点**。
##
## 它是「这一局最多能坐几个人」，**不是**当前人数 —— 空位要画出来，
## 「还剩几个」才说得出口（这正是这套圆点的全部意义）。
##
## 默认 8 = `UdpServer.max_players`（架构硬上限）。这里不复用那个常量，
## 是因为 HUD 不该知道网络层的存在 —— 由 `main.gd` 把权威值传进来（`setup()` 之前）。
var max_seats := 8

## 两屏的根。同时只有一个 visible（见 `update_view`）。
var _lobby_root: Control = null
var _play_root: Control = null

## 状态条：同一个「怎么画」的代码画两份实例（大厅一份、对局一份），
## 因为两个界面的摆放不同（大厅横跨全宽、对局在左栏里）。
var _status_rows: Array = []

## 大厅自己的底。HUD 是透明的一层（`CanvasLayer` 盖在 3D 世界上），
## 对局屏要的正是让场地透出来；但**大厅里没有场地**，直接透出来的是 3D 世界的清屏色
## —— 一圈青灰，看着像界面没搭完。所以大厅单独铺一块 `UiKit.BACKDROP`。
## 它和 `_lobby_root` 一起切可见性，写在同一处（见 `update_view`）。
var _lobby_backdrop: ColorRect = null

## 大厅：玩法网格。整块每次按内容重画（`_update_lobby` 里 clear 后重建），
## 其余骨架只搭一次。
var _lobby_grid_box: VBoxContainer = null
## 大厅：详情行。**横向**分两栏 —— 左边一栏文字（自述 / 「都开不了」/ 操作提示，
## 用一个内层 VBox 竖着摞），右边贴页点。
## 页点本身不落变量：它按页数**可能有、可能没有**，每次重建时是局部量。
var _lobby_detail_box: HBoxContainer = null
## 大厅底栏：在座玩家药丸（一行）
var _lobby_roster_box: HBoxContainer = null

## 玩法：顶部细横条。**只有时间 + 比分两样**，靠左；`status_meta()` 的小字贴在右端。
## 建成一次、之后只改文本（见 `_update_play_bar`）—— 每帧重建节点会一直重绘。
var _play_bar: PanelContainer = null
## 横条里的两个队伍比数 Label。**分开存**是因为两队数字要各自上队色，
## 而且 `status_text()` 是一整行字符串、拆不出两个数字，得单独刷。
var _play_bar_time: Label = null
var _play_bar_left: Label = null
var _play_bar_right: Label = null
## 横条右端的**额度徽标盒**（图标 + 数字，如「❤1 ★1」），不是一整句小字。
## 内容很少、且只在额度变化时才重建（见 `_update_play_bar`），不必逐字段存 Label。
var _play_bar_badges: HBoxContainer = null

## 右舞台：两处浮层，同一时刻只显示一处
##   `_stage_center` —— 倒计时（居中：这一刻舞台上没别的东西可看）
##   `_stage_top`    —— 答题中（靠上：这一刻玩家正盯着绳子，别挡）
var _stage_center: CenterContainer = null
var _stage_center_card: PanelContainer = null
var _stage_center_box: VBoxContainer = null
var _stage_top_card: PanelContainer = null
var _stage_top_box: VBoxContainer = null

## 结算：全屏遮罩 + 居中大牌
var _result_layer: Control = null
var _result_card: PanelContainer = null
var _result_title: Label = null
var _result_detail: Label = null

## 内容指纹：没变就不重建节点。无头帧率远高于手机 60Hz，
## 每帧重建几十个节点既费又把输入抢出闪烁。
##
## 初值用 `NEVER_SIG` 而不是 `""`：**「空指纹」是会真实出现的一种指纹**
## （比如一个玩家都没有时，在座玩家的指纹就是空的），拿 `""` 当初值会让
## 那一次该画的内容被当成「没变」跳过 —— 症状是「在座玩家」那块卡片一直空着。
## 不用 `"\u0000"` 这类控制字符：它会混进源码里的字符串字面量，加载时被报
## 「Unexpected NUL character」。挑一个真实指纹里不可能出现的普通词就够。
const NEVER_SIG := "<没画过>"
var _lobby_sig: String = NEVER_SIG
var _play_bar_sig: String = NEVER_SIG
var _stage_sig: String = NEVER_SIG
var _result_sig: String = NEVER_SIG


# ------------------------------------------------------------------ 骨架

## 建好骨架。内容由 `update_view()` 每帧按状态填。
func setup() -> void:
	# **必须用 `set_anchors_and_offsets_preset`，不能只用 `set_anchors_preset`。**
	# 后者只改锚点、不动 offset（四个 offset 还是 0），在父节点尺寸未知时算出来的矩形是 0×0 ——
	# 那样整个 HUD 的可用高度就是 0：舞台浮层会挤到左上角、「在座玩家」也不会被顶到底部，
	# 而且**不报任何错**，只能靠看图发现。这一条踩过一次，别再改回去。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiKit.make_theme()

	# 大厅的底：**铺在 `page` 之前**（`page` 有 MARGIN 内边距，铺不满屏幕）。
	#
	# 第 3 版按设计稿改成「**奶油纸 + 两层径向微光**」：
	#   · 整屏奶油纸 `BACKDROP`
	#   · 右上角一团极淡的**番茄红**（6% 不透明）—— 和底部的「开始」按钮同色，
	#     视线从标题扫到右下时有一点点颜色呼应，但淡到说不出「那儿有块红的」
	#   · 左下角一团极淡的**青**（7% 不透明）—— 和席位圆点的「已加入」青同色
	#
	# 上一版这里是两块**平色带**（上浅下深），理由是「整个铺同一块色会像没做完的底图」。
	# 那个理由仍然成立，只是解法换了：**微光比重色带更含蓄** ——
	# 色带会在画面上留下一条明确的分界线（实拍里那条线和标题下的 rule 错开过，
	# 看着像画错了），微光没有边界，只有「这块亮一点」。
	#
	# ⚠️ 这两团光**只在大厅状态可见**（跟着 `_lobby_backdrop` 一起切），
	# 所以绝不会盖住对局屏的 3D 场地。
	_lobby_backdrop = ColorRect.new()
	_lobby_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lobby_backdrop.color = UiKit.BACKDROP
	_lobby_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby_backdrop.visible = false
	add_child(_lobby_backdrop)

	# 右上：番茄红微光。位置对设计稿的 `at 80% -10%`（右上角偏外）
	_lobby_backdrop.add_child(_glow(Vector2(0.80, -0.10), UiKit.ACCENT, 0.06))
	# 左下：青微光。设计稿 `at 5% 110%`
	_lobby_backdrop.add_child(_glow(Vector2(0.05, 1.10), UiKit.SEAT_JOINED, 0.07))

	# 底铺完了，再搭页面和三屏（见 `_build_all` 的注释：顺序不能反）。
	_build_all()


## 一团径向微光：从 `center`（**归一化坐标**，允许超出 0..1）向外淡出的圆形柔光。
##
## 用 `GradientTexture2D` 的径向填充 + `TextureRect` 铺开，是 Godot 里做径向渐变最省事的做法
## —— 不用 `_draw()`、不用着色器、不用生成位图。
##
## `modulate.a` 控制**强度**（设计稿那两个 6% / 7%），不是靠改渐变色 ——
## 渐变只负责「从实到虚」这个形状，颜色和浓淡交给 `modulate`，
## 这样同一个函数就能做任意颜色的光斑。
##
## ⚠️ **形状是正圆、不是设计稿的椭圆**（CSS 的 `1200px 500px` 是椭圆）。
## `GradientTexture2D` 的径向填充只支持正圆。接受这个近似 ——
## 6% 不透明的光斑，圆一点扁一点没人看得出来，为它去写着色器不值得。
func _glow(center: Vector2, color: Color, alpha: float) -> TextureRect:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = center
	tex.width = 256
	tex.height = 256
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.modulate = Color(color.r, color.g, color.b, alpha)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## 搭出整块 HUD。
##
## ⚠️ **这个函数里加东西，一律加在最后那三行 `_build_*` 之前** ——
## 它们是视图骨架，漏建一个的症状是「某个 `_xxx` 是 null」，
## 而且报错点会落在**别处**（第一次 set 它的地方），极难反查。
## 构建顺序：底 → 页面容器 → 内容区 → 三屏。
func _build_all() -> void:
	# 页面容器：四边留边距，里面竖向排「状态条 + 内容区」。
	# 「内容区」是一个普通 Control，两屏都锚满它、互相叠着放 ——
	# 这样切屏不用动布局，切一下 visible 就行。
	var page := MarginContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("margin_left", UiKit.MARGIN)
	page.add_theme_constant_override("margin_right", UiKit.MARGIN)
	page.add_theme_constant_override("margin_top", UiKit.MARGIN)
	page.add_theme_constant_override("margin_bottom", UiKit.MARGIN)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)

	var rows := UiKit.vbox(UiKit.GAP)
	page.add_child(rows)

	var content := Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(content)

	_build_lobby(content)
	_build_play(content)
	_build_result()


## 状态条：**全圆角药丸 + 8 个席位圆点 + 右侧网络状态**。
## 每调一次造一份实例，两屏各一份；`_update_status` 统一刷。
##
## 第 3 版按设计稿重做（`.topbar`）：从「浅底无描边的软条」改成
## **`PAPER` 底 + 墨色粗描边 + 全圆角 + 卡片阴影**的药丸横条。
##
## 三处关键变化：
##   1. **全圆角**（`PILL_RADIUS`）—— 「这是个药丸」的观感来自圆角，不是颜色。
##      圆角一改小，它立刻变回「一条横着的卡片」，整个顶部就松掉了。
##   2. **8 个席位圆点**取代原来的「在线 2 / 8」纯数字 —— 谁加入了、谁是房主一眼可见。
##      这是这一版最有价值的结构改动（详见 `UiKit.seat_dot()`）。
##   3. 右端**只留网络状态**（呼吸绿点 + 端口），玩家名字药丸**删掉** ——
##      设计稿的状态条里没有玩家名。理由：席位圆点已经把「谁在线」说清楚了；
##      而且圆点是**固定 8 个**、宽度恒定，名字药丸数随人数变，人一多就会被裁。
func _build_status(parent: Node) -> void:
	var status := PanelContainer.new()
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiKit.flat_box(UiKit.PAPER, UiKit.INK, UiKit.STROKE, UiKit.PILL_RADIUS)
	# 设计稿 `padding:14px 22px`（×1.532 ≈ 上下 21、左右 34）。
	# **上下别超过 22** —— 状态条自己一高，网格就矮（它上面没有可压缩的东西）。
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	sb.shadow_color = UiKit.SHADOW_CARD_COLOR
	sb.shadow_size = UiKit.SHADOW_CARD
	status.add_theme_stylebox_override("panel", sb)
	parent.add_child(status)

	var row := UiKit.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	status.add_child(row)

	var tag := UiKit.label("在线", UiKit.FONT_SMALL, UiKit.INK_SOFT)
	# **垂直居中**，否则在 HBox 里默认顶对齐 —— 「在线」会浮在「4 / 8」的上半部分，
	# 读起来不像一组（实拍里就是这个观感）。
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(tag)
	var online := UiKit.label("", UiKit.FONT_BIG, UiKit.INK)
	online.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(online)

	# ---- 8 个席位圆点。**固定造满 `max_players` 个**，不随人数增减 ——
	# 「还剩几个空位」正是靠这几个空格子说出来的，少了就说不出来。
	# 用 `UdpServer.max_players` 而不是当前人数：那才是「这局最多能坐几个人」的权威答案。
	var seats := UiKit.hbox(9)
	seats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(seats)

	var gap := UiKit.spacer(0.0)
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)

	# ---- 右端：网络状态。**呼吸绿点**表达「链路活着」（设计稿 `.net .beam`）。
	# 它比写「已连接」三个字更快看清 —— 隔客厅只需要知道「亮着还是灭着」。
	var beam := UiKit.dot(UiKit.OK, 12)
	beam.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(beam)
	var net := UiKit.label("", UiKit.FONT_SMALL, UiKit.INK_SOFT)
	net.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(net)

	# 链路统计只有真机调试才看：手机连上了却没反应，先看这里丢包涨不涨。
	# 字号压到最小 —— 常驻但不该抢注意力。
	# **默认不显示**（见 `Hud.show_link_stats`）：它是调试信息，不该出现在客厅的大屏上。
	var link := UiKit.label("", UiKit.FONT_MICRO, UiKit.INK_MUTE)
	link.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	link.visible = show_link_stats
	row.add_child(link)

	var rec := {
		"dot": beam,
		"sb": null,             # 呼吸点是实心圆，不再改底色（见 `_update_status`）
		"online": online,
		"net": net,
		"seats": seats,
		"seat_dots": [] as Array,
		"link": link,
		"on": false,
		"seats_on": -1,         # 上次画过的席位数（-1 = 还没画过）
		"max_seats": max_seats,
	}
	_status_rows.append(rec)
	# **席位圆点在这里就造满**（不等到第一帧刷）—— 它们是「有几个位置」的**静态**陈述，
	# 和人数无关。漏了这一句的症状：自检里数到 0 个圆点、全组断言连锁失败。
	_fill_seats(rec)


## 大厅 = 独立的一屏。**只回答两件事：有哪些玩法、谁在线。**
##
## 布局是一整屏的**网格**，不再是「套在一张白色大卡里的清单」——
## 真实电视主屏不会把整个界面框在一个白框里，磁贴直接压在自己的底色上。
##
## 竖向分配（基准 1920x1080，可用 968）：
##   状态条 86 │ 24 │ 标题区 149 │ 24 │ **网格（唯一 EXPAND_FILL）** │ 24 │ 详情 84
## **只有网格撑开**，其余都是自然高度 —— 这样详情多出一行时挤的是网格（封面矮一点），
## 而不是把别的东西顶出屏幕。
##
## **玩家药丸从底栏搬进了状态条右端。** 原来底栏单独占一行（70 基准高 + 24 间距），
## 而状态条 1206px 宽只用掉了左端 ~200px，右端整片空着 —— 一行空横条加一行药丸，
## 两块的纵向代价换来一件「谁在线」的信息。搬进来之后：省下整行高度（约 94 基准）、
## 状态条右端不再空、「谁在线」和「在线 4 / 8」挨在一起读也更顺。
## 代价是药丸在状态条里高度受限，所以那里不再有「在座玩家」四个字 —— 人数已经写在
## 「4 / 8」上了，药丸再点明是谁，信息就齐了。
func _build_lobby(parent: Control) -> void:
	_lobby_root = MarginContainer.new()
	_lobby_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lobby_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby_root.visible = false
	parent.add_child(_lobby_root)

	# 整列间距压到 10（不是通用 GAP=24）：**大厅是 720 窗口的屏**，三个间隔按 24 走
	# 就是 72px —— 占了网格可用高度的三成多，全是从封面上扣下来的。
	# 大厅要的是「一眼扫过去挑一个」，不需要对局屏那种呼吸感。
	# 10 是个下限：再小，状态条/标题区/网格/详情就粘成一整块，读不出分组。
	var col := UiKit.vbox(10)
	_lobby_root.add_child(col)

	_build_status(col)

	# ---- 标题区（设计稿 `.hero`）：大字标题 + 右下角三个键位胶囊。
	# 键位提示摆标题**右边**而不是下面单独一行 —— 省一整行高度给封面。
	var head := UiKit.vbox(8)
	col.add_child(head)
	var head_row := UiKit.hbox(UiKit.GAP)
	# **底部对齐**（设计稿 `.hero{align-items:flex-end}`）：标题是大字，
	# 键位胶囊是矮条，底对齐才像「同一行里的两组东西」；顶对齐会显得胶囊飘在上面。
	head_row.alignment = BoxContainer.ALIGNMENT_END
	head.add_child(head_row)

	# 标题左半：主标题 + 副标题
	var titles := UiKit.vbox(6)
	head_row.add_child(titles)
	# 「玩什么**？**」—— 那个问号是**番茄红**的（设计稿 `.hero h1 em`）。
	# 整屏唯一的红色动作信号之外，这是第二处红：它把「这一屏在问你一个问题」
	# 这件事点出来，也顺手给标题一个视觉落点。拆成两个 Label 就是为了这个色差。
	var title_row := UiKit.hbox(0)
	titles.add_child(title_row)
	title_row.add_child(UiKit.label("玩什么", UiKit.FONT_TITLE, UiKit.INK))
	title_row.add_child(UiKit.label("？", UiKit.FONT_TITLE, UiKit.ACCENT))
	titles.add_child(UiKit.label("选一个玩法，人齐就能开局", UiKit.FONT_SMALL, UiKit.INK_SOFT))

	var head_pad := UiKit.spacer(0.0)
	head_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(head_pad)
	# 键位提示是**静态的**，搭一次就够（不随内容重画）。四向都要写出来 ——
	# 网格大厅里「左右也在选东西」，只说「上下」会让人以为左右没用。
	# 前两组用**真键位图标**（Kenney 图标字体的字形），后两组用文字：
	# 图标字体里没有「1-9」这种范围键，也不该硬凑。
	# 图标是单色字形，和右边的说明文字同色同高 —— 不会一深一浅。
	var keys := UiKit.key_hint([
		[UiKit.ICON_ARROWS_H, "选择"], [UiKit.ICON_UP, "翻行"],
		["回车", "开始"], ["1-9", "直选"],
	])
	keys.size_flags_vertical = Control.SIZE_SHRINK_END
	head_row.add_child(keys)

	# ---- 网格：内容每次重画，这里只给容器
	# 行间距用 TILE_GAP(22) —— 网格**只有一行**（`LOBBY_COLUMNS=3` 且只画光标所在那页），
	# 所以这个间距在单行时完全不生效，留着是给「将来真改成两行」用的。
	_lobby_grid_box = UiKit.vbox(UiKit.TILE_GAP)
	_lobby_grid_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_lobby_grid_box)

	# ---- 详情条：选中玩法的自述 + 唯一的「开始」按钮（**墨底反白**，设计稿 `.detail`）
	_lobby_detail_box = UiKit.hbox(UiKit.GAP)
	col.add_child(_lobby_detail_box)

	# 玩家药丸整个删掉了 —— 状态条上的 8 个席位圆点已经说清「谁在线」，
	# 再列一遍名字是重复信息，而且名字药丸数随人数变，人一多就被裁。
	# `_lobby_roster_box` 这个**名字**留着当「已废弃」的锚点：自检里还有引用，
	# 指向状态条右侧那个网络状态盒子（不再填人名，断言也跟着改成数席位圆点）。
	_lobby_roster_box = (_status_rows[0]["seats"] as HBoxContainer)


## 玩法那一屏：顶部细横条 + 全宽舞台。
##
## **左信息栏整个删掉了。** 它曾经固定 `UiKit.PANEL_W`(780) 宽，里面塞状态条 / 主卡 / 在座玩家 ——
## 代价是 3D 场地被挤到右边一小条，相机必须故意偏左去躲（见 `TugField.camera_view`）。
## 用户明确要求「游戏开始后只要游戏内容，左边那一块去掉」，理由也成立：
## 对局中玩家盯的是绳子，「玩法叫什么」「谁在这局」都不是这一刻要回答的问题。
## 现在只剩：一条细横条（时间 + 比分）+ 一整片舞台。谁跟谁一边，场地上的队色已经说了。
func _build_play(parent: Control) -> void:
	_play_root = Control.new()
	_play_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_play_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_root.visible = false
	parent.add_child(_play_root)

	_build_play_bar()
	_build_stage()


## 对局屏顶部细横条：**只有「剩余时间 + 比分」两样**。
##
## 摆法：锚在 `_play_root` 顶部，左右各留 `UiKit.MARGIN`，**靠左**。
## **不居中** —— 场地里绳子的远端落在画面上部中间，横条居中会正好压到它。
## 右端留给 `status_meta()` 的小字（额度那种），弹性 spacer 把它顶到最右。
##
## 形态照大厅状态条（药丸 + 阴影）但要**明显更窄**：上下内边距压到 14（大厅是 20），
## 高度锁定 `PLAY_BAR_H`，绝不做成第二条大厅状态条。
func _build_play_bar() -> void:
	var holder := MarginContainer.new()
	holder.anchor_left = 0.0
	holder.anchor_right = 1.0
	holder.anchor_top = 0.0
	holder.anchor_bottom = 0.0
	holder.offset_left = UiKit.MARGIN
	holder.offset_right = -UiKit.MARGIN
	holder.offset_top = UiKit.MARGIN
	holder.offset_bottom = UiKit.MARGIN + PLAY_BAR_H
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_root.add_child(holder)

	# 横条本体：药丸底 + 墨色描边，和状态条同一套语言。
	# `ALIGNMENT_BEGIN` 让内容靠左；`SHRINK_BEGIN` 让药丸**只占内容宽度**，
	# 不铺满整行 —— 细横条铺满会看起来像「一条压住场地的横杠」。
	var row := UiKit.hbox(0)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	holder.add_child(row)

	_play_bar = PanelContainer.new()
	_play_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := UiKit.flat_box(UiKit.PAPER, UiKit.INK, UiKit.STROKE, UiKit.PILL_RADIUS)
	# 上下 14、左右 28 —— 比大厅状态条（上下 20、左右 34）各收一档，才配得上「细」。
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.shadow_color = UiKit.SHADOW_CARD_COLOR
	sb.shadow_size = UiKit.SHADOW_CARD
	_play_bar.add_theme_stylebox_override("panel", sb)
	row.add_child(_play_bar)

	var bar_row := UiKit.hbox(UiKit.GAP)
	bar_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_play_bar.add_child(bar_row)

	# ---- 剩余时间。`FONT_BIG` 墨色，数字要一眼看得见。
	_play_bar_time = UiKit.label("", UiKit.FONT_BIG, UiKit.INK)
	_play_bar_time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_row.add_child(_play_bar_time)

	# ---- 比分：左队 / 右队，两个数字**各自上队色**。
	# 「左队 / 右队」这几个字和间隔号用 `INK` —— 颜色之外再给一条线索，
	# 色弱的人（或队色被地面反光冲淡时）也认得出哪个数字是哪一队。
	bar_row.add_child(UiKit.label("|", UiKit.FONT_SMALL, UiKit.INK_MUTE))
	_play_bar_left = UiKit.label("", UiKit.FONT_BIG, PlayerPalette.color_for_team(0))
	_play_bar_left.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var mid := UiKit.label("·", UiKit.FONT_SMALL, UiKit.INK_MUTE)
	mid.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_play_bar_right = UiKit.label("", UiKit.FONT_BIG, PlayerPalette.color_for_team(1))
	_play_bar_right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_row.add_child(_play_bar_left)
	bar_row.add_child(mid)
	bar_row.add_child(_play_bar_right)

	# ---- 右端：**额度徽标**（图标 + 数字），如「❤1 ★1」。
	# 用户要求「预先说明什么的都去除」——整句「还有 复活 1 次 · 道具 1 次」太长，
	# 改成两枚小徽标。**空/为 0 时不占宽**：徽标盒的内容由 `_update_play_bar` 填，
	# 没内容时它自然宽度为 0；弹性 spacer 保留着，把有内容时的徽标顶到最右。
	var gap := UiKit.spacer(0.0)
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(gap)
	_play_bar_badges = UiKit.hbox(14)
	_play_bar_badges.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(_play_bar_badges)


## 舞台区 = **整个屏幕**（左信息栏没了）。浮层都摆在这块区域里。
##
## `offset_left` 从 `PANEL_W + GAP*2` 改回 **0** —— 没有左栏要躲了，场地铺满整个宽度。
## `offset_top` 留出顶部横条的高度 + 一个 `GAP`：答题浮层（`_stage_top_card`）靠上摆，
## 不留这一截会被横条压住。
func _stage_margins(c: MarginContainer) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	c.anchor_top = 0.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_right = 0.0
	c.offset_top = UiKit.MARGIN + PLAY_BAR_H + UiKit.GAP
	c.offset_bottom = 0.0
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_stage() -> void:
	var center_holder := MarginContainer.new()
	_stage_margins(center_holder)
	_play_root.add_child(center_holder)
	_stage_center = CenterContainer.new()
	_stage_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_holder.add_child(_stage_center)
	_stage_center_card = UiKit.card()
	_stage_center.add_child(_stage_center_card)
	_stage_center_box = UiKit.vbox(UiKit.GAP)
	_stage_center_card.add_child(_stage_center_box)
	_stage_center.visible = false

	# 靠上摆：居中会正好盖住绳子，而答题这一刻玩家盯的就是绳子。
	var top_holder := MarginContainer.new()
	_stage_margins(top_holder)
	_play_root.add_child(top_holder)
	var top_row := UiKit.hbox(UiKit.GAP)
	top_holder.add_child(top_row)
	_stage_top_card = UiKit.card()
	_stage_top_card.visible = false
	top_row.add_child(_stage_top_card)
	_stage_top_box = UiKit.vbox(UiKit.GAP)
	_stage_top_card.add_child(_stage_top_box)
	# 撑开右边的空隙，让牌子自然靠在舞台左侧而不是被拉满整行
	var top_pad := UiKit.spacer(0.0)
	top_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(top_pad)


func _build_result() -> void:
	# 结算遮罩铺满整个 HUD。同样要用带 offset 的那个版本 —— 只设锚点的话
	# 压暗层算出来是 0×0，结算时**整个屏幕毫无变化**，只在日志里有一行字。
	_result_layer = Control.new()
	_result_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.visible = false
	add_child(_result_layer)

	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = UiKit.SCRIM
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.add_child(center)

	_result_card = UiKit.card()
	_result_card.custom_minimum_size = Vector2(RESULT_WIDTH, 0.0)
	center.add_child(_result_card)
	var box := UiKit.vbox(UiKit.GAP * 2)
	_result_card.add_child(box)

	_result_title = UiKit.wrap_label("", RESULT_WIDTH - UiKit.PAD * 2, UiKit.FONT_TITLE, UiKit.INK)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_detail = UiKit.wrap_label("", RESULT_WIDTH - UiKit.PAD * 2, UiKit.FONT_BODY, UiKit.INK_SOFT)
	_result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_title)
	box.add_child(_result_detail)


func clear() -> void:
	# 玩法网格和详情行也是「每次重画」的，一并清掉：
	# 键位提示在标题行、页点在详情行，都不在这里（它们是搭一次就常驻的骨架）。
	for box in [_lobby_grid_box, _lobby_detail_box, _lobby_roster_box,
			_stage_center_box, _stage_top_box]:
		if box == null:
			continue
		_clear_box(box)
	for l in [_result_title, _result_detail]:
		(l as Label).text = ""
	for l in [_play_bar_time, _play_bar_left, _play_bar_right]:
		(l as Label).text = ""
	if _play_bar_badges != null:
		_clear_box(_play_bar_badges)
	for row in _status_rows:
		var d: Dictionary = row
		(d["online"] as Label).text = ""
		(d["link"] as Label).text = ""
		d["on"] = false
		(d["sb"] as StyleBoxFlat).bg_color = UiKit.PILL_MUTE
	_stage_center.visible = false
	_stage_top_card.visible = false
	_result_layer.visible = false
	_lobby_sig = NEVER_SIG
	_play_bar_sig = NEVER_SIG
	_stage_sig = NEVER_SIG
	_result_sig = NEVER_SIG


# ------------------------------------------------------------------ 主入口

## 每帧喂一次。`m` 的键见 main.gd 的 `_hud_model()` —— 那里是唯一一份数据来源。
func update_view(m: Dictionary) -> void:
	_update_status(m)

	var state := int(m.get("state", GameFlow.State.LOBBY))
	if state == GameFlow.State.RESULT:
		_show_result(m)
		return

	# 离开结算就把遮罩收掉。**不靠「RESULT 的下一帧」来收** ——
	# 收尾写在每个分支里，任何一个分支忘了收都会留下一块再也点不掉的灰。
	_result_layer.visible = false
	_result_sig = NEVER_SIG

	# 大厅 / 玩法二选一。**「现在显示哪一屏」只写在这一处** ——
	# 分散到各分支去写，早晚有一条忘了关，症状是两屏叠着显示。
	# 底也在这里跟着切：对局屏必须把它收掉，否则会盖住 3D 场地。
	var in_lobby := state == GameFlow.State.LOBBY
	_lobby_backdrop.visible = in_lobby
	_lobby_root.visible = in_lobby
	_play_root.visible = not in_lobby

	if in_lobby:
		_update_lobby(m)
	else:
		_update_play_bar(m)

	_update_stage(m)


# ------------------------------------------------------------------ 状态条

func _update_status(m: Dictionary) -> void:
	var online := int(m.get("online", 0))
	var on := online > 0
	# 只画数字部分 —— 前面那一小截「在线」是 `_build_status` 里固定的标签，
	# 拆成两个 Label 才做得出「小标签 + 大数字」的层级。
	var text := "%d / %d" % [online, int(m.get("max_players", 0))]
	# 右端「网络状态」：**端口永远报**（真机排查第一眼看的就是它开没开），
	# 后面跟一句连接状态。**链路统计（收/丢包数）是调试信息，只在开关打开时才追加** ——
	# 它是手机连上了却没反应时才要看的数，不该常驻在客厅的大屏上。
	var net_text := "UDP %d · %s" % [int(m.get("port", 0)), "已就绪" if on else "等待手柄"]

	for row in _status_rows:
		var d: Dictionary = row
		(d["online"] as Label).text = text
		(d["net"] as Label).text = net_text
		# 链路统计只在**开关打开**时才写 —— 关掉时留空字符串。
		# ⚠️ 不能「照写不误、靠 `visible` 挡」：那样它虽然不显示，
		# 但**仍然占着 HBox 里那一格的宽度** —— 实拍里状态条右端就多出一段空白，
		# 看着像「那个位置本来该有东西，现在没了」。空字符串才是真的不占。
		(d["link"] as Label).text = (
			"收 %d · 丢 %d" % [int(m.get("recv", 0)), int(m.get("lost", 0))]
			if show_link_stats else ""
		)
		# 席位圆点：谁坐下了、谁是房主，一次画清（见 `_fill_seats`）。
		# 只在人数变化时才重画 —— 每帧重建圆点会一直重绘。
		if online != int(d.get("seats_on", -1)):
			d["seats_on"] = online
			_carve_seats(d, online)
		# 呼吸绿点：有人连上就是 `OK` 绿，没人就退成灰。
		# 比写「已连接 / 未连接」更快看清 —— 隔客厅只要知道「亮着还是灭着」。
		if on != bool(d["on"]):
			d["on"] = on
			_set_dot_color(d["dot"] as Control, UiKit.OK if on else UiKit.INK_MUTE)


## 给一个实心圆点换颜色。`UiKit.dot()` 返回的是 `Panel` + `StyleBoxFlat`，
## 直接改 stylebox 的底色即可（**不能改 `modulate`** —— 那会把描边一起染了）。
static func _set_dot_color(d: Control, color: Color) -> void:
	if d == null:
		return
	var sb := d.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.bg_color = color


## 按 `UdpServer.max_players` 造满一圈席位圆点。**只在建房时调一次** ——
## 圆点个数不随人数变（那正是「还剩几个空位」的表达方式），只有状态会变。
func _fill_seats(rec: Dictionary) -> void:
	var box: HBoxContainer = rec["seats"]
	_clear_box(box)
	var dots: Array = []
	var max_n := maxi(int(rec.get("max_seats", 8)), 1)
	for i in max_n:
		var d := UiKit.seat_dot(i + 1, "empty")
		box.add_child(d)
		dots.append(d)
	rec["seat_dots"] = dots


## 刷新每个席位圆点的状态。`online` 个人坐进第 1..online 号位。
##
## **房主 = 1 号位**（红了那个）。判定依据：`GameFlow` 开局时给 `sessions` 按数组下标
## 分槽位，第 0 个（也就是最早连上的那台手机）自然就是房主。
## 大屏端没有「账号」概念，号位本身是唯一的身份线索 —— 这也正好和槽位配色对上。
func _carve_seats(rec: Dictionary, online: int) -> void:
	var dots: Array = rec.get("seat_dots", [])
	for i in dots.size():
		var d: Control = dots[i]
		var state := "empty"
		if i < online:
			state = "host" if i == 0 else "joined"
		if d.get("state") != state:
			d.set("state", state)
			d.queue_redraw()


## 玩法自述按句号断行。
##
## 中文没有词边界，交给自动换行会在任意位置断开 —— 实测「…奇数位置一队，偶数位置一队。」
## 被断成「…奇数位置一 / 队，…」，一眼就看得出是机器排的。
## 按句号断行既好看又可预期（自述本来就是「一句话说清玩法」的写法），
## 单句仍然交给自动换行兜底。
static func sentence_break(text: String) -> String:
	var lines := PackedStringArray()
	var cur := ""
	for ch in text:
		cur += ch
		if ch == "。" or ch == "！" or ch == "？":
			lines.append(cur)
			cur = ""
	if not cur.is_empty():
		lines.append(cur)
	return "\n".join(lines)


# ------------------------------------------------------------------ 大厅：玩法清单

## 填大厅的内容：**一页玩法磁贴 + 详情行**。
##
## 这里**不谈任何玩法的具体内容** —— 场地、比分、绳子全归 `_play_root` 那一屏，
## 磁贴里的封面也是玩法自己画的（`MiniGame.build_cover`）。
## 大厅回答的问题只有「有哪些玩法」「现在能不能开」。
func _update_lobby(m: Dictionary) -> void:
	var lobby: Lobby = m.get("lobby")
	# 指纹里必须含 `lobby.selected` —— **翻页就靠它**：光标移出本页时 selected 变了，
	# 指纹跟着变，这一帧就重画成新的一页。不需要另写翻页逻辑。
	var sig := "lobby|%s|%s|%s|%s" % [
		lobby.selected_id() if lobby != null else "",
		str(int(m.get("online", 0))),
		str(m.get("hint", "")),
		_registry_fingerprint(lobby),
	]
	if sig == _lobby_sig:
		return
	_lobby_sig = sig
	_clear_box(_lobby_grid_box)
	_clear_box(_lobby_detail_box)

	if lobby == null or lobby.is_empty():
		_lobby_grid_box.add_child(_empty_tile("还没有注册任何玩法"))
		return

	_fill_grid(lobby, m)
	_fill_lobby_detail(lobby, m)


## 画**光标所在的那一页**磁贴（最多 `UiKit.LOBBY_COLUMNS` 张）。
##
## 只画一页，是因为 1080p 基准下留给网格的高度只够一行（见 `UiKit.LOBBY_COLUMNS`）。
func _fill_grid(lobby: Lobby, m: Dictionary) -> void:
	var n := lobby.entries.size()
	var cols := UiKit.LOBBY_COLUMNS
	var first := (lobby.selected / cols) * cols
	var last := mini(first + cols, n)

	var row := UiKit.hbox(UiKit.TILE_GAP)
	# **这一行要吃掉网格盒的全部高度**。不给的话 VBox 只按最小高度摆它，
	# 多出来的空间留在盒子底部空着，而磁贴里的封面是 `EXPAND_FILL` ——
	# 没了可分的空间就退到 `COVER_MIN_H`，封面被压成一条缝（实拍验出来的）。
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lobby_grid_box.add_child(row)
	for i in range(first, last):
		row.add_child(_game_tile(lobby, i))

	# 末尾补**一张**空位磁贴（不是把这一行补满）：玩法少的时候补满，屏幕上会有一半是空框。
	var used := last - first
	if used < cols:
		row.add_child(_next_slot_tile())
		used += 1
	# 剩下的位置用**透明**占位撑住宽度 —— 不给的话这一行的磁贴会被拉宽，
	# 和别的页宽度对不齐，翻页时整屏会横着抽一下。
	#
	# ⚠️ 曾经试过让空位卡吃满剩余宽度（`stretch_ratio = 剩余列数`），
	# 理由是「一行只填了 2/3，右边空着像没排完」。**实拍否掉了那个做法**：
	# 只剩 1 个玩法时，空位卡会变成 1183 宽的一大块虚线 ——
	# 一个「占位提示」占了屏幕的 2/3，比真玩法那张卡大三倍，主次彻底反了。
	# 现在改成：**空位卡只占一格**，剩下的留白就留白。
	# 留白在这套设计里是**喘气**（奶油纸底本来就该透出来），不是「没做完」。
	for _k in range(cols - used):
		var pad := UiKit.spacer(0.0)
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pad)


## 详情条：选中玩法的自述 + 右边**唯一的「开始」按钮**（设计稿 `.detail`）。
##
## ## 第 3 版改成**墨底反白**
##
## 上一版它是「贴在奶油纸底上的一行灰字」。这一版把它做成**一整块墨色面板**：
##   · 墨底上一块纸色的大字，是整屏对比度最高的地方 —— 视线从网格扫下来，
##     最后一定会落在这里（这正是设计稿「开始路径唯一」想要的效果）
##   · 红色「开始」按钮只在墨底上出现时才最跳；压在奶油纸上会和小标题抢注意力
##   · 它同时补上了「底部悬空」—— 上一版我为此加过一条底部色带，那一版是权宜之计，
##     这块墨面板才是真正压得住底部的分量
##
## ## 高度仍然受控
##
## 整列里只有网格是 `EXPAND_FILL`，所以详情每多一行封面就矮一行。
## **hint 是一句话反馈，优先级最低，最多给一行**，超出的交给 `clip_text`。
func _fill_lobby_detail(lobby: Lobby, m: Dictionary) -> void:
	var e := lobby.selected_entry()
	var ready := bool(e.get("ready", false))

	# 墨底面板：整个详情条就是它，内容都在它里面
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiKit.flat_box(UiKit.INK, UiKit.INK, 0, UiKit.RADIUS)
	sb.content_margin_left = 34
	sb.content_margin_right = 30
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	sb.shadow_color = UiKit.SHADOW_CARD_COLOR
	sb.shadow_size = UiKit.SHADOW_CARD
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_detail_box.add_child(panel)

	var row := UiKit.hbox(UiKit.GAP)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)

	# ---- 左：玩法名 + 描述（都是一句话，纸色系）
	var texts := UiKit.vbox(8)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	texts.add_child(UiKit.label(str(e.get("name", "")), UiKit.FONT_BODY, UiKit.PAPER))
	var sub := str(e.get("desc", ""))
	if not sub.is_empty():
		# 墨底上的次要文字：纸色降透明（设计稿 `rgba(247,242,231,.65)`）。
		# **不能用 `INK_SOFT`** —— 深灰压在墨底上等于没有对比度，什么都看不见。
		var dim := UiKit.PAPER
		dim.a = 0.65
		texts.add_child(UiKit.label(sentence_break(sub), UiKit.FONT_SMALL, dim))

	# 「为什么开不了」由 Lobby 统一回答 —— 它跟玩法自己声明的组队规则一致。
	# 只有一个玩法时不重复说：磁贴上的状态徽章已经说过同样的话了。
	if lobby.ready_count() == 0 and lobby.entries.size() > 1:
		texts.add_child(UiKit.label(
			"现在都开不了：" + lobby.blocked_hint(), UiKit.FONT_MICRO, UiKit.WAITING
		))

	if not str(m.get("hint", "")).is_empty():
		var hint := UiKit.wrap_label(
			"⚠ " + str(m["hint"]), LOBBY_DETAIL_W, UiKit.FONT_SMALL, UiKit.WAITING
		)
		# 一行封顶（见函数头的说明）。`clip_text` 在高度受限时会把溢出的那行切掉，
		# **不会**撑高控件 —— 反过来若只给 `max_lines_visible`，
		# 最小高度仍是整段文字的高度，等于没限。
		hint.max_lines_visible = 1
		hint.clip_text = true
		texts.add_child(hint)

	# ---- 右：唯一的「开始」按钮（设计稿 `.btn-start`）
	row.add_child(_start_button(ready))

	# 页点：只有一页就不画（画一个孤零零的点等于告诉人「还有别的」，是误导）。
	var pages := int(ceil(float(lobby.entries.size()) / float(UiKit.LOBBY_COLUMNS)))
	if pages <= 1:
		return
	var pager := UiKit.hbox(10)
	pager.name = PAGER_NAME
	pager.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pager)
	var cur := lobby.selected / UiKit.LOBBY_COLUMNS
	for p in pages:
		var on := p == cur
		# 墨底上的页点：选中 = 纸色实心，未选中 = 半透纸色（**不能用 `LINE`**，
		# 那个浅米压在墨底上几乎看不见）。
		var dim := UiKit.PAPER
		dim.a = 0.45
		var d := UiKit.dot(UiKit.PAPER if on else dim, 15 if on else 12)
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pager.add_child(d)


## 底部那个**唯一的「开始」按钮**（设计稿 `.btn-start`）。
##
## ## 几处刻意为之
##
## · **红底 + 墨描边 + 番茄红下沿的立体阴影** —— 三项一起才是「一枚实体按键」。
##   少了墨描边它像一块色斑，少了立体阴影它像个平面标签。
## · **能开/不能开都画同一个按钮**，只是颜色分两档：能开是番茄红，不能开是灰。
##   不改成「禁用态消失」—— 按钮消失在客厅里意味着「我不知道该干什么」，
##   摆在那里（哪怕灰着）至少说明「这一步是这一步，只是现在还不能按」。
## · **它不接受任何输入**（`mouse_filter = IGNORE`）：大屏走键盘，
##   这个按钮是**指示器**而不是控件 —— 它告诉人「按回车」。设计稿里它可点，
##   是因为 HTML 原型要能演示；真机上按回车走的是 `main.gd` 的输入路径。
func _start_button(ready: bool) -> PanelContainer:
	var bg := UiKit.ACCENT if ready else UiKit.PILL_MUTE
	var ink := Color.WHITE if ready else UiKit.INK_SOFT
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := UiKit.flat_box(bg, UiKit.INK, UiKit.STROKE, 19)
	sb.content_margin_left = 52
	sb.content_margin_right = 52
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	# 立体下沿：能开时才给（灰按钮不需要「厚」）
	if ready:
		sb.shadow_color = UiKit.ACCENT_DEEP
		sb.shadow_size = 5
		sb.shadow_offset = Vector2(0, 5)
	p.add_theme_stylebox_override("panel", sb)
	var row := UiKit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var lbl := UiKit.label("开 始", UiKit.FONT_BODY, ink)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	p.add_child(row)
	return p


## 玩法清单的内容指纹：光标 + 每行「能不能开」。
## 人数一变，同一玩法的 ready/reason 就会变，必须重画。
func _registry_fingerprint(lobby: Lobby) -> String:
	if lobby == null:
		return ""
	var parts := PackedStringArray([str(lobby.selected)])
	for e in lobby.entries:
		parts.append("%s:%s" % [str(e["id"]), str(e["ready"])])
	return "|".join(parts)


## 一张玩法磁贴（设计稿 `.gcard`）：上面是**通栏封面**，下面依次是名字行 / 说明 / 状态徽章。
##
## ## 骨架是对着设计稿重搭的，三处结构变化
##
## 1. **封面是通栏色块，不是「嵌在磁贴里的一幅画」**（设计稿 `.thumb`）：
##    上沿顶到描边内壁、左右不留白、下沿压一条**墨色 2px** 的线（不是淡分隔线）。
##    这条墨线很关键 —— 它把卡片切成「图 / 文」两块，是这套 UI 里最像印刷品的一笔。
##
## 2. **左上角有序号方块**（设计稿 `.num`）：键盘 1-9 直选时，
##    「按 3 是哪张」不用在脑子里数格子 —— 码在卡上。这是「键盘优先」原则的落地。
##
## 3. **状态徽章是描边药丸**（设计稿 `.badge`），绿边=人齐、黄边=还差人。
##    比原来「实心灰底 + 墨字」更轻，也更能一眼分色。
##
## ## 选中态由四样一起说
##
## 加粗一档的墨色描边 + **弹起阴影** + **贴纸位移**（左上挪 5）+ 封面不压暗。
## 位移的实现在 `_tile_wrap()` —— 它不进布局，所以不会把旁边的卡挤动。
##
## **不用某个彩色做选中态** —— PlayerPalette 那 8 个颜色是**玩家身份**，
## 借来做选中态会让人以为「这个玩法是蓝队的」。
func _game_tile(lobby: Lobby, i: int) -> Control:
	var e: Dictionary = lobby.entries[i]
	var selected := i == lobby.selected
	var ready := bool(e.get("ready", false))

	# `i` 一路传进名字里（`game_tile_1`）：同一行多张磁贴同名会被 Godot 改名，
	# 一改名按名字取样就漏（详见 `UiKit.tile` 的注释）。
	var tile := UiKit.tile(selected, i)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col := UiKit.vbox(0)
	# **磁贴里这一竖列必须横向铺满**，否则它按子节点的最小宽度摆，
	# 而封面槽的最小宽度是 0（普通 Control）→ 封面宽 0，画出来一片空白。
	# 症状极具迷惑性：磁贴本身尺寸正常（321x413），只是里面什么都看不见。
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.add_child(col)

	# ① 通栏封面（下面压一条墨线，由 `_cover_slot` 自己画）
	col.add_child(_cover_slot(str(e["id"]), str(e["name"]), selected, i))

	# ② 文字区。**它自己带内边距**（不是靠磁贴的 content_margin）——
	# 因为磁贴的上/左/右内边距都是 0（封面要通栏），文字区得自己把边距补回来。
	#
	# 上边距用 `TILE_PAD_TOP`（25）而不是 `TILE_PAD`（28）—— 设计稿 `.body`
	# 是 `padding:16px 18px 18px`，上面那档本来就小 2px（换算后 25 vs 28）。
	# 这里**曾经写的是 `TILE_INNER_GAP`（14）**，比设计稿少了 11px，
	# 封面墨线到玩法的名字几乎是贴着的。
	var body := UiKit.vbox(UiKit.TILE_INNER_GAP)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body_pad := MarginContainer.new()
	body_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_pad.add_theme_constant_override("margin_left", UiKit.TILE_PAD)
	body_pad.add_theme_constant_override("margin_right", UiKit.TILE_PAD)
	body_pad.add_theme_constant_override("margin_top", UiKit.TILE_PAD_TOP)
	body_pad.add_theme_constant_override("margin_bottom", UiKit.TILE_PAD)
	body_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_pad.add_child(body)
	col.add_child(body_pad)

	var cap := UiKit.hbox(16)
	body.add_child(cap)
	cap.add_child(UiKit.label(str(e["name"]), UiKit.FONT_BIG, UiKit.INK))
	var pad := UiKit.spacer(0.0)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.add_child(pad)
	# 人数范围：**深墨 + 粗**（设计稿 `.players-range{font-weight:700}`）。
	# Godot 默认字体只有一个字重，所以「粗」只能靠**墨色加深**来表达 ——
	# 用 INK 而不是 INK_MUTE，它就从「脚注」升格成「和名字并列的一条信息」。
	cap.add_child(UiKit.label(
		"%d–%d 人" % [int(e["min_players"]), int(e["max_players"])], UiKit.FONT_SMALL, UiKit.INK
	))

	# 状态徽章（设计稿 `.badge`）：描边药丸，绿=可以开始、黄=还差人。
	var strow := UiKit.hbox(UiKit.GAP)
	body.add_child(strow)
	if ready:
		strow.add_child(_badge("可以开始", UiKit.OK, UiKit.OK))
	else:
		# 字色用 `WAITING_INK`（压深的黄）而不是 `WAITING` 本身 —— 见那个常量的说明，
		# 亮黄压在奶油纸上对比度不达标。
		var why := str(e.get("reason", "开不了"))
		strow.add_child(_badge(why, UiKit.WAITING, UiKit.WAITING_INK))
	var stpad := UiKit.spacer(0.0)
	stpad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strow.add_child(stpad)

	return _tile_wrap(tile, selected)


## 状态徽章（设计稿 `.badge`）：**描边药丸** —— 同色细描边 + 极淡同色底 + 一个小圆点。
##
## 和 `UiKit.pill()` 的区别：pill 是**实心**色块（玩家身份用，颜色要跳），
## badge 是**空心的**（状态用，颜色要说得清但别抢戏）。两者不能混用。
func _badge(text: String, border: Color, ink: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiKit.flat_box(Color(border.r, border.g, border.b, 0.10), border, 2, UiKit.PILL_RADIUS)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	var row := UiKit.hbox(9)
	var d := UiKit.dot(ink, 11)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(d)
	row.add_child(UiKit.label(text, UiKit.FONT_MICRO, ink))
	p.add_child(row)
	return p


## 给磁贴外面包一层**普通 Control**，用来做选中态的「贴纸位移」。
##
## ## 为什么不能直接改磁贴自己的 `position`
##
## 磁贴是 `HBoxContainer` 的子节点，**容器每帧都会把 `position` 覆写回去** ——
## 直接设等于没设。而改 `size_flags` / 加 `MarginContainer` 又都会**进布局**，
## 把旁边的卡挤动（那就是上一版禁止位移的原因，担心得对）。
##
## ## 这个包法的关键：**位移只发生在「不参与布局」的那一层**
##
## 外层 `Control` 是容器的直接子节点，负责**占位**（它的尺寸由容器给，永远不动）；
## 内层磁贴用 `PRESET_FULL_RECT` 锚在外层上，再靠 `offset_left/top` 偏移。
## 锚点定位的偏移**不进布局**（容器只看外层的 `custom_minimum_size`），
## 所以：外层占位纹丝不动、内层视觉上挪了 5px、旁边的卡一无所知。
##
## 这正是设计稿 `transform:translate(-3px,-3px)` 的等效做法 ——
## CSS 的 `transform` 本来也不进文档流，两边语义是一致的。
func _tile_wrap(tile: Control, selected: bool) -> Control:
	if not selected:
		return tile
	var wrap := Control.new()
	# ⚠️ **名字绝不能以 `UiKit.TILE_NAME` 开头**。
	# 自检按名字找磁贴，用的是 `begins_with("game_tile")` ——
	# 叫 `game_tile_0_wrap` 就会被当成「第二张磁贴」数进去，
	# 症状是「注册了 2 个玩法，数到 3 张磁贴」，看着像布局重复建了节点。
	# 所以前缀反着来：`wrap_of_` + 原名。
	wrap.name = "wrap_of_" + str(tile.name)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 外层的最小尺寸跟着内层走 —— 否则它最小是 0，容器会给它一个 0 宽的坑。
	wrap.custom_minimum_size = tile.custom_minimum_size
	wrap.add_child(tile)
	tile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tile.offset_left = -UiKit.POP_SHIFT
	tile.offset_top = -UiKit.POP_SHIFT
	# 右下边也往外撑同样多 —— **位移要整体挪，不是「缩小」**。
	# 只给左上负偏移、右下不动的话，磁贴会被拉大 5px，
	# 那既不是位移也会让名字行的高度算错。
	tile.offset_right = UiKit.POP_SHIFT
	tile.offset_bottom = UiKit.POP_SHIFT
	return wrap


## 磁贴的封面区 = 一块给玩法画画的**通栏板** + 序号方块 + 框架的兜底海报。
##
## `plate` **必须是普通 Control（不能是容器）**：玩法靠 `PRESET_FULL_RECT` 锚点铺满它，
## 而容器的子节点由容器摆位、会无视锚点（尺寸算成 0，画出来一片空白，且不报错）。
##
## 「玩法画没画」的判据是**子节点数有没有变多** —— `build_cover()` 是往 `plate` 下挂节点，
## 挂上了就算画了。没挂就摆一张中性海报（玩法名居中），免得磁贴开天窗。
## `index` 是这一页里的第几张，只用来给节点起个不重名的名字（见 `UiKit.cover_slot`）。
func _cover_slot(game_id: String, game_name: String, selected: bool, index: int) -> Control:
	var slot := UiKit.cover_slot(index)
	# **定高**（设计稿 `.thumb{height:150px}`）—— 不再是可伸缩的。
	# 定高让封面比例恒定，「详情行一多封面就被压扁」那个老问题从结构上消失。
	slot.custom_minimum_size = Vector2(0.0, UiKit.THUMB_H)
	slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	# 封面板。**收进描边内壁、自己带同心圆角**（只圆上面两个角）——
	# 这是 CSS `.gcard{border:2px solid ink; border-radius:18px}` 的直译：
	# 内容（封面）画在边框**里面**，圆角处由浏览器的 overflow 裁剪成同心弧。
	#
	# ## 为什么不能让封面直接铺满（走过两次弯路）
	#
	# · **第一版**：方角 `Panel` 铺满 → 封面的方角盖在磁贴圆角外面（「圆角出去了」）。
	# · **第二版**：给磁贴开 `clip_children` → 出界是没了，但**子节点永远画在
	#   父节点描边之上**，玩法铺满封面的色块把墨色描边整个盖住，描边只剩
	#   抗锯齿毛边 —— 圆角处看着像一条糊掉的灰线（用户实拍第二次揪出来）。
	# · **现在**：四边收进描边内壁 `STROKE` px（通栏的「贴边」效果不变，
	#   因为色块紧贴着描边内侧），上面两个角带 `TILE_RADIUS - STROKE` 的
	#   **同心圆角**（外圆角 28 − 描边 3 = 内弧 25），裁剪下放到这一层 ——
	#   玩法画的色块被裁成圆角，而磁贴的描边谁也盖不到了。
	#
	# 底部**不收**：封面下沿由那条墨色收边线（下面 `line`）收口，和设计稿一致。
	var plate_sb := StyleBoxFlat.new()
	plate_sb.bg_color = UiKit.PAPER_ALT
	plate_sb.anti_aliasing = true
	plate_sb.corner_radius_top_left = UiKit.TILE_RADIUS - UiKit.STROKE
	plate_sb.corner_radius_top_right = UiKit.TILE_RADIUS - UiKit.STROKE
	plate_sb.corner_radius_bottom_left = 0
	plate_sb.corner_radius_bottom_right = 0
	var plate := Panel.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.offset_left = UiKit.STROKE
	plate.offset_top = UiKit.STROKE
	plate.offset_right = -UiKit.STROKE
	plate.add_theme_stylebox_override("panel", plate_sb)
	# 裁剪放在**这一层**：玩法画的封面（铺满本面板的色块）沿这里的圆角收边，
	# 而描边在磁贴那一层、没人盖得住它。`AND_DRAW` = 裁子节点且照常画自己的底。
	plate.clip_children = Control.CLIP_CHILDREN_AND_DRAW
	slot.add_child(plate)

	var before := plate.get_child_count()
	var game := GameRegistry.create(game_id)
	if game != null:
		game.build_cover(plate)
		# MiniGame 是 Node，且它只往 plate 下挂节点、不把自己挂进去 —— 用完即可回收。
		# 用法和注册表内部 `_is_game()` 的探针一致。
		game.free()
	if plate.get_child_count() == before:
		var holder := CenterContainer.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(UiKit.label(game_name, UiKit.FONT_TITLE, UiKit.INK_MUTE))
		plate.add_child(holder)

	# 封面下的**墨色收边线**（设计稿 `.thumb{border-bottom:2px solid ink}`）。
	# 上沿给玩法画画时不裁 —— 有些封面（拔河的场地色块）本来就该顶到边。
	var line := ColorRect.new()
	line.color = UiKit.INK
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.anchor_left = 0.0
	line.anchor_right = 1.0
	line.anchor_top = 1.0
	line.anchor_bottom = 1.0
	line.offset_top = -UiKit.STROKE
	line.offset_bottom = 0.0
	slot.add_child(line)

	# 序号方块（设计稿 `.num`）：墨底 + 纸色数字，锚左上角。
	# 它压在封面上，所以**不进任何布局**（锚点定位），也不随封面内容变。
	var num := UiKit.badge(str(index + 1), UiKit.INK, UiKit.PAPER, 34, 12)
	num.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	num.offset_left = 12.0
	num.offset_top = 12.0
	num.modulate = Color(1, 1, 1, 0.85)   # 设计稿 `opacity:.85`
	slot.add_child(num)

	# 未选中的封面压暗一档 —— 焦点态靠**对比**退开（选中那张是满亮的）。
	if not selected:
		plate.modulate = Color(1.0, 1.0, 1.0, UiKit.TILE_DIM_ALPHA)
	return slot


## 末尾那张「这里还能再放一个玩法」的空位磁贴。
## **它不是玩法**：不进注册表、不算 ready、不给 id，也不进内容指纹（否则每次重画）。
##
## ## 它必须和真磁贴**一样高、上边对齐**
##
## 这是实拍验出来的（polish-3）：按「一个 EXPAND 的 ＋ 加一行说明」搭出来，
## 它只有 384 高，而旁边的真磁贴 494 —— **上边低 48、下边高 62**，一行里两张卡
## 高矮不齐，看着像布局坏了。
## 原因是真磁贴的高度由**它自己那套内容**（封面 + rule + 名字行 + 药丸行）撑出来的，
## 空位磁贴少了两行，VBox 就只给它一个小的最小高度。
##
## 所以这里**照抄真磁贴的骨架**：一个 EXPAND 的「封面区」+ rule + 名字行 + 药丸行。
## 撑高度的是那个 EXPAND 的区，它在两种磁贴里都是**唯一**吃剩余高度的东西，
## 于是两张卡自然齐平 —— 不需要写死任何高度。
##
## ## 它必须一眼看出是配角
##
## 实拍里它原来是白底 + 同样的描边 + 同样大的 ＋，388 宽 vs 真磁贴 386 宽，
## 分量完全一样 —— 「以后要加的东西」和「现在能玩的东西」在屏幕上平起平坐。
## 三样一起退下去：
##   · 描边保持 `STROKE_THIN` 但底色**比真磁贴浅一档**（`PAPER_ALT` 的反面：
##     真磁贴是 `PAPER` 白，空位用 `PAPER_ALT`，压在大屏底色上仍看得出是一块，但不跳）
##   · rule 和名字行都**不画**（真磁贴才有名字和人数）
##   · ＋ 从 FONT_TITLE(84) 降到 FONT_BIG(54) —— 它原来是整屏最大的字之一，
##     比真玩法的玩法名还大，一个「占位」不该压过内容
func _next_slot_tile() -> PanelContainer:
	var tile := PanelContainer.new()
	tile.name = NEXT_SLOT_NAME
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# **虚线框**（设计稿 `.gcard.ghost{border:2.5px dashed var(--line)}`）。
	# `StyleBoxFlat` 没有 dashed 填充模式，得自绘（见 `UiKit.dashed_panel`）。
	# 磁贴自己的底色透明、无描边 —— 只当尺寸占位容器，框由那层自绘控件画。
	tile.add_theme_stylebox_override(
		"panel", UiKit.flat_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0)
	)
	# 虚线框**铺满整张卡**（锚点定位，不进布局）—— 它是装饰框，不该和内容抢空间。
	var dash := UiKit.dashed_panel(UiKit.LINE, UiKit.STROKE, UiKit.TILE_RADIUS)
	dash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(dash)

	# **内边距从 0 开始自己给** —— 磁贴底透明，内容自己留边。
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", UiKit.TILE_PAD)
	pad.add_theme_constant_override("margin_right", UiKit.TILE_PAD)
	pad.add_theme_constant_override("margin_top", UiKit.TILE_PAD)
	pad.add_theme_constant_override("margin_bottom", UiKit.TILE_PAD)
	tile.add_child(pad)

	var col := UiKit.vbox(UiKit.TILE_INNER_GAP)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 设计稿 ghost 卡是**整块垂直居中**的（`.gcard.ghost{justify-content:center}`）——
	# 只有「＋ 方块 + 一行说明」两个元素，居中摆着。
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	pad.add_child(col)

	# ＋ 方块：**虚线圆角方块**（设计稿 `.plus`），比裸摆一个「＋」字更像「一个等待被填的位置」。
	# 它自己居中 —— 用 `CenterContainer` 包一层，别让它被 VBox 拉到全宽。
	var wait := CenterContainer.new()
	wait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var plus := UiKit.dashed_panel(UiKit.INK_MUTE, UiKit.STROKE_THIN, 16)
	plus.custom_minimum_size = Vector2(58, 58)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var plus_lbl := UiKit.label("＋", UiKit.FONT_BIG, UiKit.INK_MUTE)
	plus_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plus.add_child(plus_lbl)
	wait.add_child(plus)
	col.add_child(wait)

	# 一行说明。
	#
	# ⚠️ **原来这里还有一条 `rule` 和一行空白 Label**，作用是「把高度占住，
	# 好让 ghost 和真磁贴一样高」。第 3 版**删掉了**，两个原因：
	#   1. 现在高度对齐是**靠磁贴结构本身**保证的（封面定高 `THUMB_H` + 文字区自然高度），
	#      不再需要一个「撑高的空块」—— 真磁贴里已经没有 EXPAND 的东西了
	#   2. 那条 `rule` 是**浅灰色的实线**，横在虚线框中间，实拍里看着像
	#      「虚线框上多画了一笔」/「框没画对」——它把虚线框的完整性破坏了
	var lbl := UiKit.label("下一个玩法排这里", UiKit.FONT_SMALL, UiKit.INK_MUTE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(lbl)
	return tile


## 一个玩法都没有时的整幅提示（注册表是空的，或玩法目录被整个删掉）。
func _empty_tile(text: String) -> PanelContainer:
	var tile := UiKit.card(UiKit.PAPER_ALT, UiKit.LINE, UiKit.STROKE_THIN)
	tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var wait := CenterContainer.new()
	wait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wait.add_child(UiKit.label(text, UiKit.FONT_BODY, UiKit.INK_SOFT))
	tile.add_child(wait)
	return tile


# ------------------------------------------------------------------ 玩法：顶部细横条

## 对局屏顶部细横条。**只刷文本，不重建节点**（照 `_update_status` 的做法）——
## 每帧重建节点既费又把输入抢出闪烁。
##
## ## 为什么是「解析 status_text()」而不是问玩法要结构化的数
##
## 框架有一条铁律：**不许出现任何一个玩法的名字 / id / 路径**（自检有一组专门盯它），
## 所以不能写 `if cur is TugOfWar: 读它的 jumps`。
## 而 `MiniGame` 基类（`scripts/core/`，本轮不许动）只保证 `status_text()` 一行字符串。
## 于是这里对 `status_text()` 做**宽松解析**：从这行里抠出「剩 N 秒」和两个队名后的数字。
## 抠不出来（玩法没按这个格式写）就**整行原样摆进时间那一格** —— 宁可少两处颜色，
## 不能不显示。`status_text()` 的格式由玩法自查守住（见 `tug_selftest`）。
##
## 小字 `status_meta()` 贴在右端。**空串时写空串**，不靠 `visible` 挡 ——
## 藏起来的 Label 仍占 HBox 那格宽度，右端会多出一段空白（状态条那版踩过）。
func _update_play_bar(m: Dictionary) -> void:
	var cur: MiniGame = m.get("game")
	if cur == null:
		return
	var text := cur.status_text()
	var badges := _badge_list(cur)
	var sig := "%s|%s" % [text, str(badges)]
	if sig == _play_bar_sig:
		return
	_play_bar_sig = sig

	# 「剩 39 秒」——数字单独一格，用 `FONT_BIG` 墨色，一眼看得见还剩多久。
	var time_str := _pick_time(text)
	var parsed := _pick_scores(text)
	if parsed.is_empty():
		# 玩法没按约定写这行字：把整行摆进时间格（不丢信息），两队格留空。
		_play_bar_time.text = text
		_play_bar_left.text = ""
		_play_bar_right.text = ""
	else:
		_play_bar_time.text = time_str
		_play_bar_left.text = str(parsed[0])
		_play_bar_right.text = str(parsed[1])

	_fill_bar_badges(badges)


## 收集横条右端的徽标，统一成 `[{"icon": <语义名>, "n": <还剩几次>}]`（兜底句 n=0）。
## **优先用 `status_badges()`**（结构化、能画图标）；
## 玩法没提供就退回 `status_meta()` 那行小字（当作一个无图标徽标显示）。
## 用 `has_method` 鸭子类型，不写 `if cur is TugOfWar` —— 框架不许认识任何玩法。
func _badge_list(cur: MiniGame) -> Array:
	var out: Array = []
	var badges: Array = cur.status_badges()
	if not badges.is_empty():
		for b in badges:
			var d: Dictionary = b
			var n := int(d.get("n", 0))
			if n > 0:
				out.append({"icon": str(d.get("icon", "")), "n": n})
		return out
	var meta := cur.status_meta()
	if not meta.is_empty():
		out.append({"icon": "", "n": 0, "text": meta})
	return out


## 把徽标画进右端那个盒子。**每次全量重建**（最多两项，代价可忽略），
## 空列表就清空 —— 于是「没有额度」时盒子宽度为 0，右端不会多出一段空白。
func _fill_bar_badges(items: Array) -> void:
	_clear_box(_play_bar_badges)
	for it in items:
		_play_bar_badges.add_child(_badge_chip(it as Dictionary))


## 一枚额度徽标：**图标 + 一位数字**（如「❤ 1」「★ 1」）。
##
## 图标不新增字体资源 —— 直接用系统默认字体就能画的字形（`❤` / `★`），
## 配上和语义对应的颜色。认不出的语义名（兜底那行小字）就只画文字、不画图标。
func _badge_chip(b: Dictionary) -> Control:
	var row := UiKit.hbox(6)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon := str(b.get("icon", ""))
	var glyph := ""
	var color := UiKit.INK_MUTE
	match icon:
		"revive":
			glyph = "❤"
			color = UiKit.ACCENT
		"item":
			glyph = "★"
			color = UiKit.OK
	if glyph.is_empty():
		# 兜底：整句小字（没有结构化徽标的玩法走这条）。
		row.add_child(UiKit.label(str(b.get("text", "")), UiKit.FONT_SMALL, UiKit.INK_SOFT))
		return row
	row.add_child(UiKit.label(glyph, UiKit.FONT_BIG, color))
	row.add_child(UiKit.label(str(b.get("n", 1)), UiKit.FONT_SMALL, UiKit.INK_SOFT))
	return row


## 从一行状态文字里抠出「剩 N 秒」里的 N，做成「剩 N 秒」。抠不到就返回空串
## （调用方会退回「整行原样显示」）。
static func _pick_time(text: String) -> String:
	var re := RegEx.new()
	re.compile("剩\\s*(\\d+(?:\\.\\d+)?)\\s*秒")
	var hit := re.search(text)
	if hit == null:
		return ""
	return "剩 %s 秒" % hit.get_string(1)


## 从一行状态文字里抠出两个队的数字。约定形如「…左队 5 · 右队 0…」。
## 返回 `[左, 右]`，任一个抠不到就返回空数组（交给调用方退回整行显示）。
static func _pick_scores(text: String) -> Array:
	var re := RegEx.new()
	re.compile("左队\\s*(\\d+)\\s*[·・]\\s*右队\\s*(\\d+)")
	var hit := re.search(text)
	if hit == null:
		return []
	return [int(hit.get_string(1)), int(hit.get_string(2))]


# ------------------------------------------------------------------ 在座玩家

## 在座玩家名单 —— **第 4 版整个删掉了**（对局屏重构 TUG-02）。
##
## 它曾经有**两份**实例：
##   · 大厅那份 —— 第 3 版就删了，改用状态条上的 8 个席位圆点（见 `_fill_seats`）；
##   · 对局那份 —— 挂在左信息栏底部（竖排、带标题），本轮随左栏一起删。
##
## 为什么对局那份也没了：用户明确要求「对局中只要游戏内容，左边那一块去掉」。
## 而「谁跟谁一边」这件事，**场地上的队色已经说了**（两根出线柱各是队伍色、
## 两块地界各是队伍色的浅色），名单是重复信息。对局中玩家盯的是绳子，不是名单。
## `_fill_roster` 留空壳不删是项目先例：外面可能还有引用，留着它把
## 「这里曾经有什么、为什么没了」记在案上。**不要再往里填名字。**
func _fill_roster(_box: VBoxContainer, _roster: Array) -> void:
	pass


# ------------------------------------------------------------------ 舞台浮层

## 舞台浮层。**只服务对局那一屏** —— 大厅有自己的整屏布局，不往舞台上挂东西
## （连「拿手机当手柄」那条引导也挪到大厅的在座玩家卡里了）。
func _update_stage(m: Dictionary) -> void:
	var state := int(m.get("state", GameFlow.State.LOBBY))

	var kind := ""
	var title := ""
	var body := ""
	var tips: Array = []
	if state == GameFlow.State.COUNTDOWN:
		kind = "countdown"
		title = str(maxi(int(ceil(float(m.get("countdown", 0.0)))), 1))
		body = "拿稳手机，准备往上蹦！"
	elif bool(m.get("awaiting_reward", false)):
		kind = "reward"
		var req: Dictionary = m.get("reward", {})
		var k := str(req.get("kind", ""))
		title = "答 题 中 …"
		body = "答对可得：%s" % ("复活（绳子拉回中线）" if k == "revive" else "道具「%s」" % str(req.get("item_id", "")))
		var reason := str(req.get("reason", ""))
		if not reason.is_empty():
			tips.append(reason)
		tips.append("题目在你自己的手机上，大屏不剧透")

	var sig := "%s|%s|%s|%s" % [kind, title, body, "|".join(tips)]
	if sig == _stage_sig:
		return
	_stage_sig = sig

	_stage_center.visible = false
	_stage_top_card.visible = false
	_clear_box(_stage_center_box)
	_clear_box(_stage_top_box)
	if kind.is_empty():
		return

	# 复用同一个卡片，只换它的底色和内容 —— 不重建节点树，省得每帧造一堆又 free。
	if kind == "countdown":
		_stage_center_card.add_theme_stylebox_override(
			"panel", UiKit.card_box(PlayerPalette.color_for_slot(4), UiKit.INK, UiKit.STROKE)
		)
		var n := UiKit.label(title, UiKit.FONT_HUGE, Color.WHITE)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_stage_center_box.add_child(n)
		var b := UiKit.label(body, UiKit.FONT_BIG, Color.WHITE)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_stage_center_box.add_child(b)
		_stage_center.visible = true
		return

	if kind == "reward":
		# 紫底：和平时任何状态都不撞，一眼就知道「现在不是正常对局」
		_stage_top_card.add_theme_stylebox_override(
			"panel", UiKit.card_box(PlayerPalette.color_for_slot(5), UiKit.INK, UiKit.STROKE)
		)
		_stage_top_box.add_child(UiKit.label(title, UiKit.FONT_TITLE, Color.WHITE))
		_stage_top_box.add_child(UiKit.label(body, UiKit.FONT_BODY, Color.WHITE))
		for t in tips:
			_stage_top_box.add_child(UiKit.wrap_label(str(t), 980.0, UiKit.FONT_SMALL, Color("ffe8c9")))
		_stage_top_card.visible = true
		return

	# 到这里只可能是空 kind（对局中没有浮层要显示），上面已经把两处浮层收掉了。


# ------------------------------------------------------------------ 结算

func _show_result(m: Dictionary) -> void:
	_stage_center.visible = false
	_stage_top_card.visible = false
	_result_layer.visible = true

	var r: Dictionary = m.get("result", {})
	var text := str(r.get("text", "本局结束"))
	var sig := "%s|%d" % [text, int(r.get("winner_team", -1))]
	if sig == _result_sig:
		return
	_result_sig = sig

	# 约定：标题在前，破折号之后是细节。玩法只给一句 text，这里替它分主次。
	var parts := text.split("——", false)
	var head := str(parts[0]).strip_edges()
	var detail := ""
	if parts.size() > 1:
		detail = "——".join(parts.slice(1)).strip_edges()

	# 赢的那一队用什么颜色，结算牌就用什么颜色描边
	var accent: Color = UiKit.INK
	var wt := int(r.get("winner_team", -1))
	if wt == 0 or wt == 1:
		accent = PlayerPalette.color_for_team(wt)

	_result_card.add_theme_stylebox_override("panel", UiKit.card_box(UiKit.PAPER, accent, UiKit.STROKE))
	_result_title.text = head
	_result_title.add_theme_color_override("font_color", accent)
	_result_detail.text = detail
	_result_detail.visible = not detail.is_empty()

	# 无头看不见画面，把结算牌上的字原样打一遍 ——
	# 这是「结算真的上屏了」的唯一证据（历史上它曾只 print 到日志、从没上过屏）。
	print("[main] 结算画面（大屏显示）：%s%s" % [head, " / %s" % detail if not detail.is_empty() else ""])


# ------------------------------------------------------------------ 小工具

## 清空一个容器。收 `Container` 而不是 `VBoxContainer` —— 大厅底栏那排药丸是 HBox。
func _clear_box(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
