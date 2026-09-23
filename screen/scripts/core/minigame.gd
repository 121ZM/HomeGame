class_name MiniGame
extends Node

## 小游戏契约。所有玩法都继承它。
##
## 分工：框架（core/）承担所有游戏都躲不掉的公共能力 —— 槽位分配、玩家颜色、
## HUD、倒计时、结算展示、音效、手机振动反馈。小游戏只填自己那部分：
## 规则、每帧推进、胜负判定。加新游戏 = 新写一个继承 MiniGame 的脚本 + 注册进
## GameRegistry，别的地方都不用改。
##
## 生命周期（由 GameFlow 驱动，小游戏自己不要调）：
##   setup()          开局，此时 sessions 已就位、slot 已分配
##   countdown(t)     倒计时期间每帧一次，t 从 COUNTDOWN_SEC 递减到 0
##   tick(delta)      对局中每帧一次
##   is_over()        裁判：这局完了吗
##   result()         结算数据，交给框架展示
##
## 硬规矩：只读输入抽象层的输出（session.tilt() / session.events），
## 永远不碰原始传感器值。换输入源（手机 → 摄像头 → 专用硬件）时玩法层零改动，
## 这条是整个项目的核心设计原则。

## 本局玩家。由 GameFlow 在 setup 前填好，**数组下标 = 槽位号**。
## 注意：session.slot 是玩法层概念，网络层的 player_id 跟它没有任何关系。
var sessions: Array = []


## 玩法自述。子类必须覆盖，键位：
##   id / name / desc / min_players / max_players / inputs
func meta() -> Dictionary:
	push_error("[game] %s 没有实现 meta()" % get_script().resource_path)
	return {}


func min_players() -> int:
	return int(meta().get("min_players", 1))


func max_players() -> int:
	return int(meta().get("max_players", 8))


## 当前人数能不能开这一局。默认只看区间；有额外条件的玩法（比如拔河必须偶数人）
## 覆盖这个函数。
func accepts_count(n: int) -> bool:
	return n >= min_players() and n <= max_players()


## 人数不合适时，用一句话说清**为什么**（大厅会直接显示给人看）。
##
## 默认只解释人数区间；有额外组队规则的玩法覆盖它 ——
## 「拔河要能均分两队」这种规则只有玩法自己知道，框架猜不出来，
## 所以要玩法自己回答，而不是让框架去编一句含糊的提示。
func why_not(n: int) -> String:
	if n < min_players():
		return "还差 %d 人" % (min_players() - n)
	if n > max_players():
		return "人太多，最多 %d 人" % max_players()
	return "人数不合适"


func player_count() -> int:
	return sessions.size()


func session_for_slot(slot: int) -> PlayerSession:
	if slot < 0 or slot >= sessions.size():
		return null
	return sessions[slot]


## 该槽位的玩家颜色。由框架统一分配，保证 8 个人也能一眼分清。
func color_for_slot(slot: int) -> Color:
	return PlayerPalette.color_for_slot(slot)


# ---- 以下是子类要覆盖的钩子，默认什么都不做 ----

## 开局。此时 sessions 已就绪。
func setup() -> void:
	pass


## 倒计时每帧一次。t 是剩余秒数。
func countdown(_t: float) -> void:
	pass


## 对局中每帧一次。
func tick(_delta: float) -> void:
	pass


## 这局结束了吗？返回 true 后框架会调 result() 并进入结算。
func is_over() -> bool:
	return false


## 结算数据。约定至少含 winner（"left"/"right"/"draw" 或槽位号语义由玩法自定），
## 其余字段随玩法自由发挥 —— 框架只负责展示。
func result() -> Dictionary:
	return {}


## 给 HUD 和日志用的一行状态文字。子类覆盖，便于无头验证。
func status_text() -> String:
	return ""


## 可选：状态行下面那一行**小字**。不填就不画。
##
## 存在的理由：`status_text()` 是「现在最该看的一件事」，一屏就一行；
## 额度、统计、累计次数这类次要信息塞进同一行，客厅那头的电视上会折行，
## 而且折在哪儿不受控（实测把「额度 复活1/道具1」折成了「…/道」+「具1」）。
## 想显示次要信息就放这里 —— HUD 用更小更淡的一行接着显示。
##
## **对局屏重构（TUG-02）后 HUD 优先用 `status_badges()`**：顶部细横条太窄，
## 容不下一整句「还有 复活 1 次 · 道具 1 次」。这个方法保留给「没提供 badges 时的兜底」，
## 也是「额度」这件事在人读日志时的写法。
func status_meta() -> String:
	return ""


## 可选：顶部细横条右端的**紧凑徽标**（图标 + 数字），比整句小字省地方。
##
## 返回形如 `[{"icon": "revive", "n": 1}, {"icon": "item", "n": 1}]`：
##   · `icon` —— **语义名**（不是字形），HUD 决定它画成哪个图标。目前认：
##     `"revive"`（复活）、`"item"`（道具）。
##   · `n` —— 还剩几次。**HUD 会跳过 `n <= 0` 的项**，所以可以放心全列出来。
##
## 为什么不直接返回带颜色的字符串：图标怎么画、用哪个字形、上什么颜色，是**视图层的事**，
## 玩法只该说「我现在还剩一次复活」。返回空数组 = 这个玩法没有徽标（默认，什么都不画）。
func status_badges() -> Array:
	return []


## 玩家名字后面跟的一小段标签（比如「左队 / 右队」）。
## 颜色之外再给一条线索，色弱的人也能认出谁跟谁一边；不分组的玩法留空。
func slot_tag(_slot: int) -> String:
	return ""


# ---- 3D 场地（大屏右侧那块舞台）。不画 3D 的玩法全部留空即可 ----
#
# 分工铁律：**场地是玩法的私有财产。**
# 框架只提供三件事 —— 一个挂载点（`parent`）、什么时候显示/隐藏、什么时候整棵清掉。
# 场地长什么样、相机怎么取景，框架一概不知道。
#
# 为什么要这么切：这样把 `scripts/minigames/<某玩法>/` 整个目录删掉，框架照常起、
# 照常跑，只是大厅里少一个玩法。反过来，框架里一旦出现「如果是某个玩法就……」这种分支，
# 玩法就焊进框架了，删玩法必然连带改框架。判断标准很直白：
# **框架文件里不该出现任何一个玩法的名字、id 或路径。**（自检里有一组专门盯着这条）


## 搭自己的 3D 场地，**全部挂在框架给的 `parent` 下**。
##
## 挂到别处（主节点、玩法实例自己身上）会同时躲开「换局清场」和「回大厅整块隐藏」，
## 症状是回大厅后画面里还留着上一个玩法的场地 —— 框架会当场报错（见 main.gd 的场地对账）。
func build_field(_parent: Node3D) -> void:
	pass


## 每帧推一次场地的**画面**（不动玩法状态）：绳子位置、指针角度这类。
##
## 只在场地可见时被调用（大厅里不调）。结算时状态已经不再变，这里推出来的结果
## 就是最终画面 —— 不需要额外写「冻住」。
func tick_field(_delta: float) -> void:
	pass


## 舞台相机的取景。框架有一套通用默认值（正对场地中心、略俯视），
## 玩法**只给要覆盖的键**：
##   {"position": Vector3, "rotation_deg": Vector3, "fov": float}
##
## 什么时候需要覆盖：场地不在世界原点，或者玩法想要自己的构图（拉近 / 俯角 / 视场角）。
## 例：拔河为了「明显放大、铺满全屏」把相机拉近并加大 fov（见 TugField.camera_view）。
func field_camera() -> Dictionary:
	return {}


# ---- 2D 封面画（大厅磁贴里那块图形区）。不画的玩法全部留空即可 ----
#
# 和 `build_field()` 是**同一条规矩**：画面归玩法，框架只给挂载点和生命周期。
# 框架不认识任何一个玩法的封面长什么样，也不去猜 —— 所以加玩法、删玩法都不用动框架。


## 画自己的**封面画**：大厅磁贴里那块图形区。
##
## 框架保证：
##   · `parent` 是一块**普通 Control（不是容器）**，调用时它的矩形已经定好
##   · 往它下面挂自己的 Control（`set_anchors_and_offsets_preset(PRESET_FULL_RECT)` 铺满），
##     在自己的 `_draw()` 里画
##   · **记得 `resized.connect(queue_redraw)`**：磁贴尺寸由容器定，第一次 `_draw` 时
##     `size` 可能还是 0，不重画就永远是空白
##   · 挂上去的东西框架会连整块磁贴一起清掉，玩法不用自己回收
##
## 玩法**不画**（默认空实现）时，框架会摆一张中性的兜底海报（玩法名居中）。
## 判据是「调完之后 `parent` 的子节点有没有变多」——所以封面必须是**挂上去的节点**，
## 不能指望往 `parent` 自己身上画（`_draw()` 只属于节点本身，这里画不了）。
func build_cover(_parent: Control) -> void:
	pass


# ---- 奖励钩子（道具 / 复活），不支持的玩法全部留空即可 ----
#
# 「看广告得道具或复活」在框架里被抽象成一次**奖励请求**：
# 玩法说「现在谁需要一个什么」，框架负责挂起对局、交给网关（答题程序 / 广告 / mock）、
# 拿回一个布尔结果再交给玩法生效。玩法完全不知道奖励是怎么来的。


## 这个玩法提供哪些奖励。返回空字典 = 不支持奖励。
##
## 返回形如：
##   {
##     "revive": {"quota": 1, "left": 1, "reason": "一句话说明"},
##     "items": [{"id": "big_pull", "name": "猛力一拽", "left": 1, "desc": "..."}],
##   }
func reward_catalog() -> Dictionary:
	return {}


## 现在有谁需要奖励吗？返回空字典 = 不需要。
##
## 返回形如（kind 只认 "revive" / "item"）：
##   {"kind": "revive", "slot": 0, "reason": "给人看的一句话"}
##   {"kind": "item", "item_id": "big_pull", "slot": 1, "reason": "..."}
##
## 框架每帧在 tick() 之后问一次；**同一时刻只处理一个请求**，
## 所以正在等奖励结果时这里必须返回空（否则会被反复问）。
func pending_reward_request() -> Dictionary:
	return {}


## 框架决定接下这个请求、挂起对局之前调用。玩法在这里记住「我在等什么」。
func begin_reward(_req: Dictionary) -> void:
	pass


## 奖励结果回来了，玩法在这里生效。
## granted 为 false 时也要调 —— 玩法通常需要因为「没拿到」而推进对局（比如判负）。
func apply_reward(_req: Dictionary, _granted: bool, _data: Dictionary) -> void:
	pass
