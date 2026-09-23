class_name TugField
extends Node3D

## 拔河的 3D 场地：地面、两侧地界、中线、两根出线柱、绳子、绳结。
##
## **这块归玩法自己。** 框架只做三件事：给一个挂载点（`MiniGame.build_field(parent)`）、
## 决定什么时候显示 / 隐藏（大厅里整块藏掉）、换局时整棵清掉。
## 场地长什么样、相机怎么取景，框架一概不知道 ——
## 这样把 `scripts/minigames/tug/` 整个目录删掉，框架照常起、照常跑，只是大厅里少一个玩法。
##
## 反过来看这条规矩：框架里一旦出现「如果是某个玩法就……」这种分支，就是把玩法焊进了框架，
## 删玩法必然连带改框架。判断标准很直白：**框架文件里不该出现任何一个玩法的名字、id 或路径。**
##
## 关于取景：场地坐标全是世界坐标原样，相机由 `TugOfWar.field_camera()` 声明覆盖项。
##
## 「绳结偏到哪边」是这一局唯一的读数，所以场地上所有的取舍都是为了让这一眼可见。


## 绳子在地面上的可视长度（米）。±1 的归一化位置映射到 ±ROPE_HALF ——
## 也就是两端出线柱站的地方。
##
## **这是纯视觉量**：玩法规则（±1 出线、40 秒、每次蹦拉多少）全在 `tug_of_war.gd`，
## 和这里无关。左信息栏删掉后（TUG-02）场地要铺满全宽，所以从 1.6 放大到 2.6，
## 绳子在屏幕上更长、更醒目。
const ROPE_HALF := 2.6
## 出线柱高度（米），纯视觉。绳子被拔过它就算赢。
## 场地放大后柱子也跟着高一点，否则相对场地会显得矮扁。
const POST_H := 0.62
## 地面尺寸（米）。相机看得远，小地面会露出「世界边缘」那条硬边；
## 大到边缘落在屏幕外，剩下的就是一条干净的地平线。
const GROUND_SIZE := 34.0
## 两侧地界块的半宽（米）。场地放大后跟着放宽，让红蓝两块**横向铺满**画面。
const ZONE_HALF := 3.6
## 地界块的纵深（米）与向远处的偏移（米）。
## 太浅的话地界的远边会在画面上划出一条斜边，看着像「场地中途断了」；
## 放大后加深一点，红蓝两块在画面上更「实」。
const ZONE_DEPTH := 7.0
const ZONE_SHIFT_Z := -0.8

var _board: MeshInstance3D = null
var _rope: MeshInstance3D = null
## 绳结。只挪位置、不改颜色，所以不需要留材质引用（见 `set_rope`）。
var _marker: MeshInstance3D = null


## 搭出来。**所有节点一律挂在 self 下** —— 框架清场时整棵 free，
## 漏挂到别处（主节点、玩法实例自己身上）会同时躲开「清场」和「回大厅隐藏」，
## 症状是回大厅后画面里还留着这套场地，框架那边会当场报错。
func build() -> void:
	_build_ground()
	_build_zones()
	_build_rope()


## 绳子归一化位置（-1..1）→ 绳结挪到哪。这套映射是玩法自己的事，框架不认识它。
func set_rope(normalized: float) -> void:
	if _marker != null:
		_marker.position.x = normalized * ROPE_HALF


# ------------------------------------------------------------------ 搭

func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color("cdd7bd")
	ground.material_override = ground_mat
	add_child(ground)


func _build_zones() -> void:
	# 两侧地界：把队色往纸白插值得到浅色块（`UiKit.tint`）。
	# 用平涂而不是半透明 —— 半透明会和地面色叠成第三种颜色，两边的色差反而糊掉。
	# 插值比例不能太狠（0.78 那版几乎看不出左右之分），0.6 还能看出是「两块场地」，
	# 又不至于抢走绳子的注意力。
	_add_box(
		Vector3(ZONE_HALF, 0.01, ZONE_DEPTH),
		Vector3(-ZONE_HALF * 0.5, 0.006, ZONE_SHIFT_Z),
		UiKit.tint(PlayerPalette.color_for_team(0), 0.6)
	)
	_add_box(
		Vector3(ZONE_HALF, 0.01, ZONE_DEPTH),
		Vector3(ZONE_HALF * 0.5, 0.006, ZONE_SHIFT_Z),
		UiKit.tint(PlayerPalette.color_for_team(1), 0.6)
	)

	# 中线：横跨整个场地纵深的白条。它是观众判断「现在谁占优」的唯一基准，
	# 所以全场就它最亮。
	_board = _add_box(
		Vector3(0.08, 0.03, ZONE_DEPTH), Vector3(0.0, 0.015, ZONE_SHIFT_Z), Color("fffdf5")
	)


func _build_rope() -> void:
	# 两侧出线柱：绳子被拔过它就算赢。**做矮不做高**，理由见 POST_H。
	_add_box(
		Vector3(0.26, POST_H, 0.26), Vector3(-ROPE_HALF, POST_H * 0.5, 0.0),
		PlayerPalette.color_for_team(0)
	)
	_add_box(
		Vector3(0.26, POST_H, 0.26), Vector3(ROPE_HALF, POST_H * 0.5, 0.0),
		PlayerPalette.color_for_team(1)
	)

	# 绳子：0.09 高、0.22 深。前一版是 0.06 x 0.14，隔着 4 米看就是一条灰线，
	# 分不清是在动还是没动 —— 而「绳子在动」正是这个玩法的全部反馈。
	_rope = _add_box(
		Vector3(ROPE_HALF * 2.0, 0.09, 0.22), Vector3(0.0, 0.10, 0.0), Color("a9825a")
	)

	# 绳结：胜负就看它偏到哪边。骑在绳子上（不是埋进去，也不是浮在上方）。
	#
	# **恒定用调色板的墨色，不跟着队色跑。** 早先的实现是「对局中把绳结染成占优那一边的
	# 队色，一眼看出谁在赢」，截图一看就废了：
	#   1. 大厅里绳结取的是第一个玩家的**槽位色**，槽位 0 恰好是红，和左队出线柱撞成
	#      同一个颜色，看上去像左队那根柱子被拖到了中间；
	#   2. 对局中绳结压在绳子上，一染红就变成左柱投下来的一道影子。
	# 位置已经说清楚了，颜色留给「左柱 / 右柱」两个人用就行，别三个人抢。
	_marker = _add_box(Vector3(0.24, 0.32, 0.32), Vector3(0.0, 0.20, 0.0), UiKit.INK)


## 造一块平涂的方盒子。场地里除了地面全是盒子，抽出来省样板。
func _add_box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	add_child(mi)
	return mi


# ------------------------------------------------------------------ 取景

## 舞台取景。框架有一套通用默认值（正对场地中心、略俯视），拔河要的不是那个：
##
## **相机在正中（x = 0）**。左信息栏已经删掉（TUG-02），整屏都是舞台，
## 不需要再为躲开那条栏而左移。历史上 `position.x` 是 -1.35，因为栏占屏幕左侧 824px、
## 会把绳子的左端藏进去 —— 那个补偿随栏一起撤了。
##
## **拉近 + 略降 + 加大 fov**，让红蓝场地**上下顶到大半屏**：
## 用户实拍反馈「分区只占中间一块、上下留白太多、绳子显得细」，要求「明显放大、铺满」。
## 相机从 (-1.35, 3.80, 3.08) 移到 (0, 2.9, 2.35)，俯角 -34°→-38°，fov 55→62。
## 场地（`ROPE_HALF`/`ZONE_HALF`）同步放大，两者一起把场地撑满画面。
##
## fov 不用回到 75：那是广角，画面两侧的竖直物体会明显往一边倒（出线柱会像斜插的板子）。
## 62 是「够宽 + 畸变还能接受」的折中。
##
## 俯角保持 35° 以上：绳子仍有厚度和阴影，不至于看成一条线。
static func camera_view() -> Dictionary:
	return {
		"position": Vector3(0.0, 2.90, 2.35),
		"rotation_deg": Vector3(-38.0, 0.0, 0.0),
		"fov": 62.0,
	}
