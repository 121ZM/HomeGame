extends Node3D

## 大屏端主场景 —— 也就是「壳」。
##
## 它只干四件事：搭视图、起网络层、起流程状态机、把两者接起来显示。
## 任何游戏规则都在 scripts/minigames/ 里，这里一行都没有。
##
## 代码构建视图，不依赖 .tscn 里手写节点 —— 场景文件只挂这一个脚本，
## 少一处手写 tscn 就少一处格式出错的机会。
##
## 运行方式：
##   正常       godot --path screen
##   自测       godot --headless --path screen res://scenes/main.tscn -- --simulate
##   多人自测   godot --headless --path screen res://scenes/main.tscn -- --simulate --sim-players=2
##   自动开局   godot --headless --path screen res://scenes/main.tscn -- --simulate --sim-players=2 --autostart=tug
##   满员自测   godot --headless --path screen res://scenes/main.tscn -- --simulate --sim-players=5 --max-players=3
##   悬殊对局   godot --headless --path screen res://scenes/main.tscn -- --simulate --sim-players=2 --sim-step=6
##   双进程     godot --headless --path screen res://scenes/main.tscn
##              godot --headless --path screen res://tools/simulator.tscn -- --name=孙悟空 --pid=1
##   自检       godot --headless --path screen res://tools/selfcheck.tscn
##
## 大厅操作（电视 / PC 上用来选玩法开局，方向键和手柄十字键都行）：
##   ↑ ↓       移动光标
##   回车/空格   开始选中的玩法
##   数字 1-9   直接选中并开始第 N 个玩法
##   人不够时大屏会直接说明原因（比如「拔河要均分两队，得 2 人或 4 人」）
##
## 奖励（看广告得道具/复活）：
##   --reward=mock        开发用假网关（默认），--ad-delay= 秒后自动放行
##   --reward=http        接你自己的答题程序，配合 --reward-url=
##   --reward=off         不开奖励，玩法要奖励一律按「拿不到」算
##   --ad-policy=grant    假网关策略：grant 全给 / deny 全拒 / alternate 交替 / timeout 不回答
##   --ad-delay=6         假网关思考时间（秒），0 = 立刻回答（测试用）
##   --reward-url=http://127.0.0.1:8787
##   --reward-timeout=45  等奖励的上限（秒），到点按「拿不到」算
##   --sim-step=0.6       内置模拟器的往上蹦节奏递增步长；调大 = 两队蹦的疏密差距大，
##                        用来逼出「压线 → 复活」这条平时难得一见的分支

const SimulatorScript := preload("res://scripts/sim/simulator.gd")

const DEFAULT_PORT := 8910
## 架构硬上限，见 memory：由资源（颜色/HUD/客厅可视性）决定，不是玩法人数
const MAX_PLAYERS := 8
## 内置模拟器的往上蹦节奏：每人不同，否则双方势均力敌永远平局
const SIM_JUMP_BASE := 1.2
const SIM_JUMP_STEP := 0.6
## --autostart 等「人数稳定」的时长（秒），见 _maybe_autostart()
const AUTOSTART_SETTLE_SEC := 1.5

## 舞台相机的**通用**取景：正对场地中心、略俯视、fov 55。
##
## 这只是个兜底 —— 场地长什么样是玩法自己的事，玩法觉得这个构图不对，
## 就用 `MiniGame.field_camera()` 覆盖掉（拔河就覆盖了：它要相机整体左移，
## 好把左边那条不参与 3D 的信息栏让开）。框架里不留任何玩法的取景数字。
const STAGE_CAM_POS := Vector3(0.0, 3.6, 3.4)
const STAGE_CAM_ROT_DEG := Vector3(-32.0, 0.0, 0.0)
const STAGE_CAM_FOV := 55.0

var server: UdpServer = null
var flow: GameFlow = null
var rewards: RewardService = null
## 大厅：选玩法 + 开局入口。只放逻辑，怎么画全在 scripts/ui/hud.gd。
var lobby: Lobby = null
## 大屏 HUD。视图节点全在那边；这里只负责把数据算好喂给 `update_view()`。
var ui: Hud = null

## 3D 世界（环境 + 相机 + 灯）。大厅里整块 hidden，见 `_update_world`。
var _world: Node3D = null
## 舞台相机。框架持有一台通用相机，玩法可以用 `field_camera()` 改它的取景。
var _stage_cam: Camera3D = null
## 场地挂在哪个挂载点下：换局时整棵 free 掉重搭（场地内容由玩法自己搭）。
var _field_root: Node3D = null
## 当前这套场地是**哪个玩法实例**搭的。
##
## 记实例而不是记 id：同一个玩法连开两局是两个实例，按 id 记的话第二局会复用第一局的
## 场地 ——而新实例手里没有它的引用，绳子就永远不动了。场地和玩法实例同生共死。
var _field_owner: MiniGame = null

var _stats_timer: float = 0.0
var _max_players: int = MAX_PLAYERS
var _autostart: String = ""
## 上次重建大厅列表时的人数（人数没变就不重建，省得光标被打断）
var _lobby_count: int = -1
## 一行操作反馈（比如「这个现在开不了」），显示在信息栏主卡里
var _hint: String = ""
## --autostart 的等待状态：见过的人数 + 人数不变已经持续了多久
var _autostart_seen: int = -1
var _autostart_settle: float = 0.0

## 状态条右端要不要显示「收 N · 丢 N」这套链路统计。
## 默认值在 `_ready()` 里按运行环境定（无头/debug 打开、成品关闭），这里只是兜底。
var _show_link_stats := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var spawn_sims := 0
	var reward_backend := "mock"
	var reward_url := "http://127.0.0.1:8787"
	var ad_policy := "grant"
	var ad_delay := 6.0
	var reward_timeout := 45.0
	var sim_step := SIM_JUMP_STEP
	# 「链路统计」（收包数 / 丢包数）是给真机调试看的：手机连上了却没反应，先看这里丢包涨不涨。
	# 但它是**调试信息**，不该出现在客厅的大屏上 —— 实拍里那个「收 1236 · 丢 0」
	# 就在状态条右端占着一块，和「在线 4 / 8」抢注意力，是这一屏少数几个「不像成品」的地方。
	# 所以默认**只在无头 / 调试构建里显示**：无头跑局正好需要它来验链路。
	# `--link-hud` 强制打开（在真机上想看），`--no-link-hud` 强制关掉（截成品图用）。
	var link_hud := OS.has_feature("debug") or DisplayServer.get_name() == "headless"
	for a in args:
		if a.begins_with("--sim-players="):
			spawn_sims = maxi(0, int(a.get_slice("=", 1)))
		elif a.begins_with("--max-players="):
			_max_players = maxi(1, int(a.get_slice("=", 1)))
		elif a.begins_with("--autostart="):
			_autostart = a.get_slice("=", 1)
		elif a.begins_with("--reward="):
			reward_backend = a.get_slice("=", 1)
		elif a.begins_with("--reward-url="):
			reward_url = a.get_slice("=", 1)
		elif a.begins_with("--ad-policy="):
			ad_policy = a.get_slice("=", 1)
		elif a.begins_with("--ad-delay="):
			ad_delay = float(a.get_slice("=", 1))
		elif a.begins_with("--reward-timeout="):
			reward_timeout = float(a.get_slice("=", 1))
		elif a.begins_with("--sim-step="):
			sim_step = maxf(0.0, float(a.get_slice("=", 1)))
		elif a == "--link-hud":
			link_hud = true
		elif a == "--no-link-hud":
			link_hud = false

	# 显示模式要在搭 UI 之前定好：切全屏会触发一次窗口尺寸变化，
	# 先切再布局可以少一轮重排。
	_setup_display(args)

	# `link_hud` 必须在 `_build_view()` **之前**传到 HUD —— 状态条是在搭视图时造的，
	# 它得在那一刻就知道要不要给自己留出「链路统计」那一格（见 `hud.show_link_stats`）。
	_show_link_stats = link_hud
	_build_view()

	lobby = Lobby.new()
	lobby.refresh(0)

	server = UdpServer.new()
	server.port = DEFAULT_PORT
	server.max_players = _max_players
	server.motion_event.connect(_on_motion_event)
	server.player_joined.connect(_on_player_joined)
	server.player_left.connect(_on_player_left)
	server.room_full.connect(_on_room_full)
	add_child(server)

	rewards = RewardService.new()
	rewards.timeout_sec = reward_timeout
	add_child(rewards)
	_setup_reward_gateway(reward_backend, reward_url, ad_policy, ad_delay)

	flow = GameFlow.new()
	flow.set_reward_service(rewards)
	flow.state_changed.connect(_on_flow_state_changed)
	flow.game_finished.connect(_on_game_finished)
	flow.reward_started.connect(_on_reward_started)
	flow.reward_settled.connect(_on_reward_settled)
	add_child(flow)

	print("[main] 已注册玩法：\n%s" % GameRegistry.describe_all())

	if "--simulate" in args:
		if spawn_sims <= 0:
			spawn_sims = 1
		for i in spawn_sims:
			var sim: Node = SimulatorScript.new()
			sim.target_port = DEFAULT_PORT
			sim.player_id = i + 1
			# 名字池在 PlayerNames 里（和手机端不报名时是同一份）。
			# 这里只是「默认分配」——真机报了自己的名字就用他自己的。
			sim.player_name = PlayerNames.at(i)
			sim.jump_period = SIM_JUMP_BASE + i * sim_step
			add_child(sim)
		print("[main] 已启动 %d 个内置模拟器" % spawn_sims)


## 挑一个奖励网关接上。这是整个「看广告 / 答题」唯一需要改的地方。
func _setup_reward_gateway(backend: String, url: String, policy: String, delay: float) -> void:
	match backend:
		"off":
			print("[main] 奖励网关：关闭（要奖励一律算拿不到）")
			return
		"http":
			var gw := HttpRewardGateway.new()
			gw.base_url = url
			gw.name = "HttpRewardGateway"
			add_child(gw)
			rewards.set_gateway(gw)
			print("[main] 奖励网关：%s" % gw.describe())
		_:
			var mock := MockRewardGateway.new()
			mock.policy = policy
			mock.answer_delay_sec = delay
			mock.name = "MockRewardGateway"
			add_child(mock)
			rewards.set_gateway(mock)
			print("[main] 奖励网关：%s" % mock.describe())


func _process(delta: float) -> void:
	# 顺序要紧：菜单先跟上人数，再决定要不要自动开局。
	# 反过来的话，玩家刚连上那一帧菜单还是旧的（0 人），自动开局会拿「还差 2 人」去拒绝。
	_refresh_lobby()
	_maybe_autostart(delta)

	# 3D 先动、HUD 后画：HUD 里有些东西（比如「压线待救」）要看的就是这一帧的绳子位置。
	if ui != null and server != null:
		var m := _hud_model()
		var cur: MiniGame = m["game"]
		# 世界先对齐状态机：大厅要把它整块藏掉，进玩法才把**该玩法自己的**场地搭出来。
		var world_on := _update_world(int(m["state"]), cur)
		# 场地画面由玩法自己推 —— 框架不认识场地长什么样。反过来说，
		# 框架这边也就不会出现「如果是某个玩法就……」的分支（见 MiniGame.tick_field）。
		if world_on and cur != null:
			cur.tick_field(delta)
		ui.update_view(m)

	_stats_timer += delta
	if _stats_timer >= 1.0:
		_stats_timer = 0.0
		_log_stats()


## 人数一变就重建大厅列表。有人进来、掉线、主动退出都要立刻反映到菜单上。
func _refresh_lobby() -> void:
	if server == null or lobby == null:
		return
	var n := server.sessions.size()
	if n == _lobby_count:
		return
	_lobby_count = n
	lobby.refresh(n)
	_log_lobby(n)


## 菜单是画在 HUD 上的，无头跑的时候看不见 —— 所以人数一变就打一份到日志里，
## 这是无头验证「大厅到底显示什么」的唯一窗口。
func _log_lobby(n: int) -> void:
	if lobby.is_empty():
		print("[main] 大厅清单（%d 人）：还没有注册任何玩法" % n)
		return
	var parts := PackedStringArray()
	for i in lobby.entries.size():
		var e: Dictionary = lobby.entries[i]
		parts.append("%d.%s %d-%d 人 %s" % [
			i + 1, str(e["name"]), int(e["min_players"]), int(e["max_players"]),
			"可开" if bool(e["ready"]) else "开不了：%s" % str(e["reason"]),
		])
	print("[main] 大厅清单（%d 人）：%s" % [n, "；".join(parts)])


# ------------------------------------------------------------------ 大厅操作

## 大厅的键盘 / 遥控器操作。
## 用内置的 ui_* 动作而不是具体键码 —— 方向键、手柄十字键、电视遥控器的方向键
## 都映射在它们上面，写一次全部支持。
func _unhandled_input(event: InputEvent) -> void:
	# F11 手动切全屏/窗口。默认给什么由 `_setup_display()` 定，这里只是留个随时能翻的手动开关
	# ——在电视上想看日志、或在编辑器里想预览真实满屏效果，都靠它。
	# 和流程状态无关，任何时候都该管用，所以放在状态判断前面。
	if event is InputEventKey and event.pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).keycode == KEY_F11:
			_toggle_fullscreen()
			return

	if flow == null or flow.state != GameFlow.State.LOBBY or lobby == null:
		return
	# 这里不需要再标记「菜单脏了」—— HUD 自己按内容指纹判断要不要重画
	# （指纹里含光标位置和每一行的「能不能开」），光标一动下一帧自然就重画了。
	# 四个方向都走 `move_grid`（网格光标）。用内置 `ui_*` 动作，
	# 手柄十字键和电视遥控器发的就是这几个 —— 不自己造按键。
	# 左右在**同一行内**循环、不跨行：电视上按右键，焦点必须还在同一条水平轴上。
	if event.is_action_pressed("ui_left"):
		lobby.move_grid(-1, 0, UiKit.LOBBY_COLUMNS)
		_hint = ""
	elif event.is_action_pressed("ui_right"):
		lobby.move_grid(1, 0, UiKit.LOBBY_COLUMNS)
		_hint = ""
	elif event.is_action_pressed("ui_up"):
		lobby.move_grid(0, -1, UiKit.LOBBY_COLUMNS)
		_hint = ""
	elif event.is_action_pressed("ui_down"):
		lobby.move_grid(0, 1, UiKit.LOBBY_COLUMNS)
		_hint = ""
	elif event.is_action_pressed("ui_accept"):
		_start_selected()
	elif event is InputEventKey and event.pressed and not (event as InputEventKey).echo:
		var n := _digit_pressed(event as InputEventKey)
		if n > 0:
			lobby.select_index(n - 1)
			_start_selected()


## 按下的是哪个数字键（1..9），不是数字键返回 0。
## 看 unicode 而不是键码：小键盘、非英文键盘布局都能拿到正确的数字。
func _digit_pressed(key: InputEventKey) -> int:
	var u := key.unicode
	return u - 0x30 if u >= 0x31 and u <= 0x39 else 0


## 开局该用全屏还是窗口。
##
## 客厅大屏要**开箱即全屏**（没人会拿着遥控器去找窗口的标题栏），但开发时全屏很碍事：
## 日志在终端里、想切窗口看编辑器都做不到，只能 F11 摸回来。
## 所以判据是「跑的是哪个二进制」：
##   1. 命令行 `--fullscreen` / `--windowed` 最高优先（脚本化启动、临时调试都用它）
##   2. 编辑器二进制（`godot --path .`、或编辑器里按 F5）→ 窗口，方便看日志
##   3. 导出后的正式版（导出模板二进制）→ 全屏
##
## 判据用 `OS.has_feature("editor")`。注意它的准确含义是「**运行的是编辑器那个二进制**」——
## 不只是「在编辑器里点运行」：`godot --path .` 直接起、F5 起，都算；导出件用的是导出模板
## 二进制，这个标志为 false。正好就是我们想要的分界，而且它是编译期就定好的特性标志，
## 比去猜命令行参数可靠。
func _setup_display(args: PackedStringArray) -> void:
	var why := ""
	var want_full := false
	if "--windowed" in args:
		why = "命令行指定"
	elif "--fullscreen" in args:
		want_full = true
		why = "命令行指定"
	elif OS.has_feature("editor"):
		why = "编辑器二进制，方便看日志"
	else:
		want_full = true
		why = "正式版，直接占满客厅大屏"
	_set_fullscreen(want_full)
	_report_display(want_full, why)


## 全屏 / 窗口的真正开关。用 `WINDOW_MODE_FULLSCREEN`（无边框全屏，走桌面当前分辨率）
## 而不是 `WINDOW_MODE_EXCLUSIVE_FULLSCREEN` —— 独占全屏会把显示器分辨率也改掉，
## 切出去之后桌面图标全乱，客厅设备上很难受。
func _set_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	)


## 当前是不是全屏。`EXCLUSIVE_FULLSCREEN` 也算 —— 虽然我们自己只用无边框那种，
## 但别处（编辑器、别人的配置）可能设成独占全屏，一起认。
func _is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## 报显示模式。以「切完之后引擎**实际**是什么模式」为准，不照自己想要的报。
##
## 因为全屏请求**会静默失败**：在编辑器里跑的时候游戏窗口是**嵌在编辑器里**的，
## 引擎只留一句 `Embedded window only supports Windowed mode.` 就拒绝。
## 这时候要是报「已全屏」，状态就跟现实分家了，再按一次 F11 会接着骗下去。
func _report_display(want_full: bool, why: String) -> void:
	var got_full := _is_fullscreen()
	if got_full != want_full and want_full:
		print("[main] 显示模式：窗口（%s；切全屏被引擎拒绝：嵌入式游戏视图只支持窗口模式）" % why)
		return
	print("[main] 显示模式：%s（%s）" % ["全屏" if got_full else "窗口", why])


## F11 手动切全屏 ↔ 窗口。
func _toggle_fullscreen() -> void:
	var want_full := not _is_fullscreen()
	_set_fullscreen(want_full)
	_report_display(want_full, "F11")


## 开始光标选中的那个玩法。人数不满足就只提示，不硬开。
func _start_selected() -> void:
	if lobby == null or lobby.is_empty():
		return
	var e := lobby.selected_entry()
	var game_id := str(e.get("id", ""))
	if game_id.is_empty():
		return
	if not bool(e.get("ready", false)):
		_hint = "《%s》现在开不了：%s" % [str(e.get("name", game_id)), str(e.get("reason", ""))]
		print("[main] %s" % _hint)
		return
	_hint = ""
	_autostart = ""  # 手动开了，就不要再自动开一局
	if flow.start_game(game_id, server.sessions.values()):
		print("[main] 大厅开局：%s（%d 人）" % [game_id, server.sessions.size()])


# ------------------------------------------------------------------ 视图

## 搭视图。3D 世界**先藏起来** —— 开局一定是从大厅开始的（见 `_update_world`）。
func _build_view() -> void:
	_build_world()
	_build_hud()
	_world.visible = false


## 3D 世界 = 环境 + 舞台相机 + 灯 + （玩法自己搭的）场地。
##
## **大厅里整块藏起来。** 设计上大厅和玩法是两个界面（`GameFlow.State.LOBBY` 是独立状态，
## `Lobby` 也是纯逻辑类），但视图层曾经没跟上：场地在启动时搭一次就常驻，于是大厅里
## 也画着上一个玩法的绳子和出线柱 —— 看着像「游戏已经摆好，就等你按开始」，
## 而且**第二个玩法一进来就串味**（大厅背景还挂着别人的场地）。
## 现在按状态机走：大厅不显示世界，进玩法才让玩法把**自己的**场地搭出来。
##
## 框架在这里只管「环境 + 相机 + 灯」这三样所有玩法都要的东西，场地内容一概不管。
func _build_world() -> void:
	_world = Node3D.new()
	add_child(_world)
	# 场地挂在这个空节点下：换局时整棵 free 掉重搭（见 `_rebuild_field`）。
	_field_root = Node3D.new()
	_world.add_child(_field_root)

	# 环境：淡色平涂底 + 柔和环境光。
	# 不设的话 Godot 默认是深灰蓝的「虚空」，而且只有平行光 —— 背光面直接黑掉，
	# 平涂卡通风立刻破功。这一条和 UI 的圆角描边是同一套视觉语言的一部分。
	#
	# **能量之和要压在 1.0 附近。** 为什么：平涂风的前提是「写什么颜色就画什么颜色」，
	# 而 PBR 是 albedo × 光。早先环境光 0.6 + 平行光 1.1，朝上的面实测乘了约 1.19 ——
	# 地面 cdd7bd 被顶成 (245,255,226)，和天空 eef1e6 (238,241,230) 几乎同色，
	# **地平线消失、场地看着像浮在虚空里**（只有两块地界还看得见）。
	# 现在 0.45 + 1.0 ≈ 1.0：朝上的面基本就是 albedo 本身，地面重新成为一块看得见的地。
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("eef1e6")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("ffffff")
	env.ambient_light_energy = 0.45
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_world.add_child(world_env)

	# 舞台相机：框架给一套**通用**取景，玩法可以用 `field_camera()` 覆盖它。
	var cam := Camera3D.new()
	cam.fov = STAGE_CAM_FOV
	cam.position = STAGE_CAM_POS
	cam.rotation_degrees = STAGE_CAM_ROT_DEG
	_world.add_child(cam)
	_stage_cam = cam

	# 灯：**必须开阴影**。不开的话场上的方块就像贴纸一样浮在地面上，分不出谁前谁后 ——
	# 而「谁挡着谁」正是 3D 场地唯一比 2D 图形多给的那点信息。
	# 强度 1.0 与上面的环境光 0.45 配对，凑成「亮面 ≈ albedo」（理由见环境那一段）。
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	light.light_energy = 1.0
	light.shadow_enabled = true
	_world.add_child(light)


## 换局时重搭场地。
##
## 框架只做三件事：清掉上一套、给一个新挂载点、把场地交给玩法自己去搭。
## **它不问「你是哪个玩法」** —— 这是整个项目最重要的一条边界：
## 框架里一旦出现「如果是某个玩法就……」，玩法就焊进框架了，删玩法必然连带改框架。
func _rebuild_field(cur: MiniGame) -> void:
	_clear_field()
	_field_owner = cur
	if cur == null or _field_root == null:
		return
	# 对账的基准要在**清场之后**取：清场前 `_field_root` 下还挂着上一套场地。
	var before := _collect_nodes()
	cur.build_field(_field_root)
	_check_field_scoped(before)
	_apply_field_camera(cur)
	# 无头看不见画面，把「场地真的搭出来了」打成日志 —— 这一屏本来只有肉眼能验。
	# 节点数是顺手的一根探针：地面曾经漏挂在主节点上（少一个），这里会立刻看出来。
	print("[main] 搭好场地：%s（%d 个节点）" % [
		str(cur.meta().get("id", "")), _field_root.get_child_count(),
	])


## 场地里的每个节点都必须挂在 `_field_root` 下 —— 每次搭完场地对一次账。
##
## 为什么值得专门写一个检查：漏挂在别处的节点会**同时躲开两件事**，而且**一点错都不报**：
##   1. `_clear_field` 清不到它 ⇒ 换局时上一套场地还留在场上；
##   2. `_world.visible = false` 藏不掉它 ⇒ **回大厅后它还在画**，
##      而大厅那一屏本来只该有底色，于是「页面边距那一圈」露出场地的颜色。
## 这个坑真的踩过：地面的 `PlaneMesh` 当时写成了挂在主节点上，
## 症状是回大厅后整屏泛着草绿；而「搭好场地（7 个节点）」这个数字看着也像个正常数
## （真实是 8 个）—— 少的那一个正是地面。**这种错没有任何别的症状。**
func _check_field_scoped(before: Array) -> void:
	var strays: Array[String] = []
	for n in _collect_nodes():
		if before.has(n):
			continue
		if _field_root != null and _field_root.is_ancestor_of(n):
			continue
		strays.append("%s（%s）" % [n.name, n.get_class()])
	if not strays.is_empty():
		push_error("搭场地时有节点漏挂在 `_field_root` 外面（回大厅会藏不掉、换局会清不掉）：%s"
				% str(strays))


## `root` 子树里的全部节点。场地对账用：搭之前拍一张、搭之后再拍一张，差集就是新节点。
func _collect_nodes(root: Node = self, out: Array = []) -> Array:
	for c in root.get_children():
		out.append(c)
		_collect_nodes(c, out)
	return out


## 把当前场地整棵清掉。
##
## 顺带把 `_field_owner` 也放掉：它可能指向已经 free 的实例（上一局完了被回收），
## 留着只会让「这个场地是谁的」这个问题越来越难回答。
func _clear_field() -> void:
	_field_owner = null
	if _field_root == null:
		return
	for c in _field_root.get_children():
		_field_root.remove_child(c)
		c.queue_free()


## 每帧把 3D 世界对齐到状态机。返回「世界现在开着吗」—— 开着才轮得到玩法推画面。
##
## 大厅 → 整块隐藏（**不 free**：大厅 → 玩几局 → 回大厅，藏一下最省事）。
## 对局 → 显示，且场上必须是**这一局玩法搭的**场地；换了实例就整棵重搭。
func _update_world(state: int, cur: MiniGame) -> bool:
	if _world == null:
		return false
	if state == GameFlow.State.LOBBY:
		_world.visible = false
		return false
	if cur != _field_owner:
		_rebuild_field(cur)
	_world.visible = true
	return true


## 相机取景：框架给通用默认值，玩法**只给要覆盖的键**。
##
## 为什么让玩法管这件事：构图是跟场地绑在一起的（场地不在原点、或者场地有一部分
## 会被左边那条不参与 3D 的信息栏挡掉，都得靠挪相机来解决）。
## 把这些数字留在框架里，等于框架偷偷知道了某个玩法的场地长什么样。
func _apply_field_camera(cur: MiniGame) -> void:
	if _stage_cam == null:
		return
	var v := cur.field_camera() if cur != null else {}
	_stage_cam.position = v.get("position", STAGE_CAM_POS)
	_stage_cam.rotation_degrees = v.get("rotation_deg", STAGE_CAM_ROT_DEG)
	_stage_cam.fov = float(v.get("fov", STAGE_CAM_FOV))


## 大屏 HUD。视图全在 scripts/ui/hud.gd —— 这里只把它挂上去，再把数据喂给它。
##
## 一律用代码搭，不手写 .tscn：场景文件只挂这一个脚本，
## 少一处手写 tscn 就少一处格式出错的机会。
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Hud.new()
	# 状态条是 `setup()` 里造的，所以这两个值都必须在 `setup()` 之前落下去：
	#   · `show_link_stats` —— 状态条要不要留出「收 N · 丢 N」那一格
	#   · `max_seats`       —— 要画几个**席位圆点**（空位也要画出来）
	# HUD 不认识网络层，所以「最多能坐几个人」由这里传（`UdpServer.max_players` 的权威值）。
	ui.show_link_stats = _show_link_stats
	ui.max_seats = _max_players
	layer.add_child(ui)
	ui.setup()


## 每帧把「该显示什么」算成一个纯数据字典，交给 HUD 去画。
##
## 键就是 HUD 认的全部输入 —— 想加一个新显示，先在这里加一个键。
## 好处是读 `server` / `flow` 的地方**只有这一处**，不会一半在 main 一半在 HUD。
func _hud_model() -> Dictionary:
	var online := server.sessions.size()
	var recv := 0
	var lost := 0
	for pid in server.sessions:
		var ps: PlayerSession = server.sessions[pid]
		recv += ps.packets_received
		lost += ps.packets_lost

	var state: int = flow.state if flow != null else GameFlow.State.LOBBY
	return {
		"state": state,
		"state_name": flow.state_name() if flow != null else "?",
		"online": online,
		"max_players": _max_players,
		"recv": recv,
		"lost": lost,
		"port": DEFAULT_PORT,
		"lobby": lobby,
		"hint": _hint,
		"game": flow.current if flow != null else null,
		"countdown": flow.countdown_left() if flow != null else 0.0,
		"awaiting_reward": flow.is_awaiting_reward() if flow != null else false,
		"reward": flow.pending_reward() if flow != null else {},
		"result": flow.last_result if flow != null else {},
		"roster": _roster_model(state),
	}


## 在座玩家。掉线的槽位**显式留一个「空」**，不删 ——
## 抽掉中间一个会让后面所有人的槽位号前移，颜色身份全乱（见 memory）。
func _roster_model(state: int) -> Array:
	var out: Array = []
	if state == GameFlow.State.LOBBY or flow == null or flow.current == null:
		# 大厅里还没分配槽位（槽位是开局那一刻才定的），按连接顺序上色
		var idx := 0
		for pid in server.sessions:
			var ps: PlayerSession = server.sessions[pid]
			out.append({"label": ps.display_name(), "color": PlayerPalette.color_for_slot(idx)})
			idx += 1
		return out

	var cur: MiniGame = flow.current
	for slot in cur.sessions.size():
		var ps := cur.session_for_slot(slot)
		if ps == null:
			out.append({"label": "槽位 %d 空" % slot, "color": UiKit.PILL_MUTE})
			continue
		out.append({
			"label": ps.display_name() + _slot_tag(cur, slot),
			"color": PlayerPalette.color_for_slot(slot),
		})
	return out


## 玩家名后面的标签，由**玩法自己**给（`MiniGame.slot_tag`）：分队玩法返回「左队 / 右队」，
## 颜色之外再给一条线索，色弱的人也认得出谁跟谁一边。
##
## 框架在这里**只负责排版**（前面加一个空格），不判断任何玩法规则 ——
## 早先这里写着「如果是某玩法就取它的队伍」，那正是把玩法焊进框架的样子。
func _slot_tag(cur: MiniGame, slot: int) -> String:
	var tag := cur.slot_tag(slot) if cur != null else ""
	return "" if tag.is_empty() else " " + tag


# ------------------------------------------------------------------ 编排

## 开发期的自动开局：人够了就开，方便无头验证整条流程。
##
## 它**走大厅同一条路**（先选中、再 `_start_selected()`），不另外抄一份人数判据 ——
## 判据只有一处，`--autostart` 顺便就把大厅的「能不能开」也验证了。
## 副作用是：`--autostart=tug --sim-players=3` 现在会被大厅挡住并说明原因（以前是一声不响地失败）。
##
## 为什么还要等「人数稳定」：`--simulate` 下模拟器是逐个上线的，刚连上第一个人时
## 拔河必然「还差 1 人」。这时候就放弃，`--sim-players=4` 也会被误杀。
## 所以人数还在变就继续等，不变了才做决定。
func _maybe_autostart(delta: float) -> void:
	if _autostart.is_empty() or flow == null or server == null or lobby == null:
		return
	if flow.is_busy():
		return
	var n := server.sessions.size()
	if n == 0:
		return  # 一个人都还没连上，接着等
	var e := lobby.entry_for(_autostart)
	if e.is_empty():
		return  # 玩法还没进列表（或 id 写错），等下一帧

	if bool(e.get("ready", false)):
		lobby.select_id(_autostart)
		_start_selected()
		return

	if n != _autostart_seen:
		_autostart_seen = n
		_autostart_settle = 0.0
		return
	_autostart_settle += delta
	if _autostart_settle < AUTOSTART_SETTLE_SEC:
		return
	# 人数定下来了还开不了，那就是真开不了 —— 说清原因收手，
	# 不然这一帧一行的提示会刷满整个日志。
	print("[main] 自动开局放弃：《%s》%s" % [
		str(e.get("name", _autostart)), str(e.get("reason", "人数不合适")),
	])
	_autostart = ""


func _log_stats() -> void:
	if server == null:
		return
	var st := server.stats()
	if int(st["players"]) == 0:
		print("[main] 等待手机连接… 监听 UDP 0.0.0.0:%d" % DEFAULT_PORT)
		return
	print("[main] 在线 %d/%d  流程 %s  收包 %d  丢包 %d  异常包 %d  拒入 %d" % [
		st["players"], st["max_players"], flow.state_name(), st["received"], st["lost"],
		st["bad_packets"], st["rejected"],
	])
	for pid in server.sessions:
		var s: PlayerSession = server.sessions[pid]
		print("         " + s.summary())


func _on_motion_event(_pid: int, _event: Dictionary) -> void:
	pass  # 输入事件由 GameFlow → MiniGame 消费，壳不再自己统计


func _on_player_joined(session: PlayerSession) -> void:
	print("[main] 玩家加入：「%s」(%s:%d)  在线 %d/%d" % [
		session.display_name(), session.address, session.port,
		server.sessions.size(), _max_players,
	])


func _on_player_left(pid: int) -> void:
	print("[main] 玩家 %d 离开  在线 %d/%d" % [pid, server.sessions.size(), _max_players])
	if flow != null:
		flow.drop_player(pid)


func _on_room_full(address: String, port: int) -> void:
	push_warning("[main] 房间已满，已拒绝 %s:%d" % [address, port])


func _on_flow_state_changed(from: int, to: int) -> void:
	print("[main] 流程：%s → %s" % [
		GameFlow.State.keys()[from], GameFlow.State.keys()[to],
	])
	if to == GameFlow.State.LOBBY:
		# 回到大厅：清掉上一次的提示，并强制重算一次菜单 —— 对局中可能有人掉线，
		# 人数没变也值得重来一遍（比如刚好又补进来一个）。
		# 结算牌不需要在这里收：HUD 的 `update_view` 一看到状态不是 RESULT 就自己收，
		# 而且它的内容指纹里带着文案，下次结算会自动重画。
		_hint = ""
		_lobby_count = -1


func _on_game_finished(result: Dictionary) -> void:
	print("[main] 结算：%s" % str(result.get("text", "")))


func _on_reward_started(req: Dictionary) -> void:
	print("[main] 大屏提示：答题中…（%s）" % str(req.get("reason", "")))


func _on_reward_settled(req: Dictionary, granted: bool, data: Dictionary) -> void:
	var detail := str(data.get("detail", ""))
	print("[main] 奖励%s%s" % [
		"到手" if granted else "没拿到",
		"：%s" % detail if not detail.is_empty() else "",
	])
