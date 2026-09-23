class_name Lobby
extends RefCounted

## 大厅：选玩法 + 开局入口。
##
## 为什么是个独立的类：`GameFlow.start_game()` 是唯一的开局入口，但在它之前必须先
## 回答「玩哪个」—— 这件事在真实的客厅里没人替玩家做，所以它必须是代码的一部分。
## 在此之前，整个平台只能靠 `--autostart` 开发参数开局，等于没法真正玩。
##
## 只做逻辑，不做展示：菜单画成什么样、用什么键操作，都由调用方决定（目前是 main.gd）。
## 数据全部来自 `GameRegistry.evaluate()`，所以**加玩法不用改这里**。
##
## 用法：
##   var lobby := Lobby.new()
##   lobby.refresh(server.sessions.size())   # 人数一变就重建
##   lobby.move_grid(1, 0, UiKit.LOBBY_COLUMNS)  # 网格里往右走一格
##   lobby.selected_id()                     # 拿选中的玩法 id 去 start_game()

## 每个玩法一条，字段见 GameRegistry.evaluate()
var entries: Array = []
## 光标位置（entries 的下标）
var selected: int = 0


## 按当前人数重建列表。
## 光标尽量停在**原来那个玩法**上 —— 有人进出就会重建列表，
## 不让光标乱跳是这种界面的基本功。原来那个要是没了，就落到第一个能开的身上。
func refresh(player_count: int) -> void:
	var keep := selected_id()
	entries = GameRegistry.evaluate(player_count)
	if entries.is_empty():
		selected = 0
		return
	var idx := index_of(keep)
	if idx < 0:
		idx = first_ready_index()
	selected = clampi(idx, 0, entries.size() - 1)


func is_empty() -> bool:
	return entries.is_empty()


func selected_id() -> String:
	return str(selected_entry().get("id", ""))


func selected_entry() -> Dictionary:
	if selected < 0 or selected >= entries.size():
		return {}
	return entries[selected]


## 光标在网格里怎么走。
##
## 左右：**在同一行内循环，不跨行**。理由是 10-foot UI 的硬预期 ——
## 在电视上按右键，焦点必须还留在同一条水平轴上。一跨行，人立刻失去方向感
## （「我按了右，怎么跑到下面去了？」），而遥控器用户没有鼠标可以救回来。
## 上下：整行循环（到顶再按一下回最后一行），行尾不满时落到该行最后一个。
##
## `columns` 由展示层给（`UiKit.LOBBY_COLUMNS`）—— **布局是展示的事，Lobby 不写死列数**，
## 否则改一回排版就要回来改逻辑。
func move_grid(dx: int, dy: int, columns: int) -> void:
	if entries.is_empty() or columns <= 0:
		return
	var n := entries.size()
	var row := selected / columns
	var col := selected % columns
	if dx != 0:
		# 行内循环。行尾不满时用的是**这一行实际的长度**，不是 columns ——
		# 否则最后一行的光标会跑到一个不存在的格子上。
		var row_start := row * columns
		var row_len := mini(columns, n - row_start)
		selected = row_start + wrapi(col + dx, 0, row_len)
		return
	if dy != 0:
		var rows := int(ceil(float(n) / float(columns)))
		# 目标行那一列可能没有项（最后一行不满），夹到最后一个，别落到空处。
		selected = mini(wrapi(row + dy, 0, rows) * columns + col, n - 1)


func select_index(i: int) -> void:
	if i >= 0 and i < entries.size():
		selected = i


## 按玩法 id 把光标挪过去。找不到就原地不动，返回是否挪成功。
## 不用 Array.find()：那是按值比较整个字典，加第二个玩法之后很容易悄悄返回 -1。
func select_id(game_id: String) -> bool:
	var i := index_of(game_id)
	if i < 0:
		return false
	selected = i
	return true


func index_of(game_id: String) -> int:
	for i in entries.size():
		if str(entries[i]["id"]) == game_id:
			return i
	return -1


func entry_for(game_id: String) -> Dictionary:
	for e in entries:
		if str(e["id"]) == game_id:
			return e
	return {}


func ready_entries() -> Array:
	var out: Array = []
	for e in entries:
		if bool(e["ready"]):
			out.append(e)
	return out


func ready_count() -> int:
	var n := 0
	for e in entries:
		if bool(e["ready"]):
			n += 1
	return n


func first_ready_index() -> int:
	for i in entries.size():
		if bool(entries[i]["ready"]):
			return i
	return 0


## 「开不了」的玩法各是什么原因，拼成一句话（HUD 直接显示）。
## 只列开不了的 —— 有个把能玩的混进来，这行字就没意义了。
func blocked_hint() -> String:
	if entries.is_empty():
		return "还没有注册任何玩法"
	var parts := PackedStringArray()
	for e in entries:
		if not bool(e["ready"]):
			parts.append("%s：%s" % [str(e["name"]), str(e["reason"])])
	return "；".join(parts)
