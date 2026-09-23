class_name GameRegistry
extends RefCounted

## 小游戏注册表。**加新玩法不需要改这个文件** —— 往玩法目录里放脚本就行。
##
## 用法：
##   GameRegistry.ids()             → ["tug", ...]
##   GameRegistry.create("tug")     → 一个新的 MiniGame 实例（未 setup）
##   GameRegistry.find("tug")       → 玩法脚本
##
## 菜单里选游戏、校验人数、HUD 显示名字，全部从 meta() 里读 ——
## 所以新游戏只要 meta() 写对，框架就自动认得它。

## 玩法目录。**一个玩法一个子目录**，目录里所有 `.gd` 都会被试着读一遍：
## 继承 MiniGame 的才算玩法，其余（场地、工具栏、数据脚本）自动忽略 ——
## 所以玩法目录里可以自由放自己的辅助脚本，不用跟框架打招呼。
const GAMES_DIR := "res://scripts/minigames"

## 玩法自带的规则测试的命名约定：`<任何名字>_selftest.gd`，放在玩法自己的目录里。
const SELFTEST_SUFFIX := "_selftest.gd"

static var _cache: Array[Script] = []
static var _cached: bool = false

## 开发期额外挂进来的（框架自带的测试载体，见 register_for_test）。
## **和扫出来的分开存** —— 这样「注册到的玩法都住在玩法目录里」这类断言仍然成立。
static var _extra: Array[Script] = []


## 已注册的玩法脚本。顺序稳定：先按 `meta()["order"]`（不填当 0），再按 id 字母序。
##
## 为什么是**扫目录**，而不是在这里写一串 `preload("res://scripts/minigames/…")`：
## 写 preload 等于让框架在**编译期**点名依赖某个玩法 —— 把那个玩法目录删掉，
## 框架直接编译不过，连大厅都起不来。而玩法在设计上是**可插拔**的：
## 删掉一个玩法，效果只该是「大厅里少一个条目」，框架照常跑。
## 扫目录 + 运行时 `load()` 才是这个关系的正确形状。
static func scripts() -> Array[Script]:
	if _cached:
		return _cache
	_cached = true
	_cache = []
	if not DirAccess.dir_exists_absolute(GAMES_DIR):
		# 一个玩法都没有也照常跑起来，大厅会说「还没有注册任何玩法」
		return _cache
	for dir_name in DirAccess.get_directories_at(GAMES_DIR):
		var dir_path := GAMES_DIR.path_join(dir_name)
		var files := DirAccess.get_files_at(dir_path)
		# 目录顺序在文件系统上不保证，先排一遍：让扫描结果本身可复现
		files.sort()
		for file_name in files:
			if not file_name.ends_with(".gd"):
				continue
			var s := load(dir_path.path_join(file_name)) as Script
			if s != null and _is_game(s):
				_cache.append(s)
	_cache.sort_custom(_ordered)
	return _cache


## 这个脚本是不是一个玩法？**只认「继承 MiniGame」**。
static func _is_game(s: Script) -> bool:
	var probe: Object = s.new()
	if probe == null:
		return false
	var is_game := probe is MiniGame
	# 只 free 得掉 Node 子类；RefCounted 走自己的引用计数，硬 free 会报错
	if probe is Node:
		(probe as Node).free()
	return is_game


## 各玩法**自己带的**规则测试（`<...>_selftest.gd`，继承 MiniGameSelfTest）。
##
## 和玩法脚本用的是同一套办法：扫目录。所以框架自检完全不认识具体玩法 ——
## 删掉一个玩法目录，它带的测试跟着消失，自检照常跑完全部框架那几组。
## 这也正是「玩法和框架分开」在测试上的样子：**测试跟着被测对象走**。
static func selftest_scripts() -> Array[Script]:
	var out: Array[Script] = []
	if not DirAccess.dir_exists_absolute(GAMES_DIR):
		return out
	var dirs := DirAccess.get_directories_at(GAMES_DIR)
	dirs.sort()
	for dir_name in dirs:
		var dir_path := GAMES_DIR.path_join(dir_name)
		var files := DirAccess.get_files_at(dir_path)
		files.sort()
		for file_name in files:
			if not file_name.ends_with(SELFTEST_SUFFIX):
				continue
			var s := load(dir_path.path_join(file_name)) as Script
			if s != null and _is_selftest(s):
				out.append(s)
	return out


static func _is_selftest(s: Script) -> bool:
	var probe: Object = s.new()
	if probe == null:
		return false
	# MiniGameSelfTest 是 RefCounted：走自己的引用计数，不能硬 free
	return probe is MiniGameSelfTest


## 开发期用：把一个**不放在玩法目录里**的脚本塞进注册表。
##
## 框架自检要验「流程状态机」「奖励挂起与恢复」「掉线」这些，必须**有一个玩法在跑**
## 才能验。它用自己带的假玩法（scripts/dev/fake_game.gd）当载体 —— 而那个脚本按设计
## 不该出现在 `scripts/minigames/` 里（它是框架的零件，不想在大厅里露脸）。
## 所以给它开一个显式入口。
##
## 只影响当前进程：正常运行（main.tscn）里没有任何人调它。
static func register_for_test(s: Script) -> void:
	scripts()  # 先把真实目录扫完、把缓存定下来
	if s == null or _cache.has(s):
		return
	_cache.append(s)
	_extra.append(s)
	_cache.sort_custom(_ordered)


## 上面那些额外挂进来的脚本（扫目录扫不到它们）。
static func test_registered() -> Array[Script]:
	return _extra


## 大厅里的先后顺序。**必须定死** —— 菜单第 N 项、数字 1-9 直选、光标记忆
## 全挂在顺序上，顺序随文件系统飘会让「按 2 进第二个玩法」这种操作失效。
static func _ordered(a: Script, b: Script) -> bool:
	var ka := _sort_key(a)
	var kb := _sort_key(b)
	if int(ka[0]) != int(kb[0]):
		return int(ka[0]) < int(kb[0])
	return str(ka[1]) < str(kb[1])


static func _sort_key(s: Script) -> Array:
	var probe: MiniGame = s.new()
	var m := probe.meta()
	probe.free()
	return [int(m.get("order", 0)), str(m.get("id", ""))]


## 全部已注册玩法的 meta 列表（id 去重，先注册的优先）
static func catalog() -> Array:
	var out: Array = []
	var seen := {}
	for s in scripts():
		var probe: MiniGame = s.new()
		var m := probe.meta()
		if m.is_empty():
			push_error("[registry] %s 的 meta() 返回空，已跳过" % s.resource_path)
			probe.free()
			continue
		var id := str(m.get("id", ""))
		if id.is_empty() or seen.has(id):
			push_error("[registry] id 为空或重复：%s（%s）" % [id, s.resource_path])
			probe.free()
			continue
		seen[id] = true
		out.append(m)
		probe.free()
	return out


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for m in catalog():
		out.append(str(m["id"]))
	return out


static func find(game_id: String) -> Script:
	for s in scripts():
		var probe: MiniGame = s.new()
		var m := probe.meta()
		probe.free()
		if str(m.get("id", "")) == game_id:
			return s
	return null


static func create(game_id: String) -> MiniGame:
	var s := find(game_id)
	if s == null:
		push_error("[registry] 没有注册过的玩法：%s" % game_id)
		return null
	return s.new()


## 列出「当前人数能开哪些玩法」。等价于 evaluate() 里 ready 的那些。
## 返回的条目字段见 evaluate()。
static func available_for(player_count: int) -> Array:
	var out: Array = []
	for e in evaluate(player_count):
		if bool(e["ready"]):
			out.append(e)
	return out


## 大厅用：每个玩法在当前人数下**能不能开**、**开不了是为什么**。
##
## 返回形如：
##   {"id": "tug", "name": "拔河", "desc": "...", "min_players": 2, "max_players": 4,
##    "players": 3, "ready": false, "reason": "要均分两队，得 2 人或 4 人"}
##
## 「为什么开不了」由玩法自己回答（MiniGame.why_not），框架不猜 ——
## 像「拔河要均分两队」这种规则只有玩法自己知道。
static func evaluate(player_count: int) -> Array:
	var out: Array = []
	for s in scripts():
		var probe: MiniGame = s.new()
		var m := probe.meta()
		if m.is_empty():
			push_error("[registry] %s 的 meta() 返回空，已跳过" % s.resource_path)
			probe.free()
			continue
		var ready := probe.accepts_count(player_count)
		out.append({
			"id": str(m.get("id", "")),
			"name": str(m.get("name", "")),
			"desc": str(m.get("desc", "")),
			"min_players": probe.min_players(),
			"max_players": probe.max_players(),
			"players": player_count,
			"ready": ready,
			"reason": "" if ready else probe.why_not(player_count),
		})
		probe.free()
	return out


## 一行行打出全部玩法，开发期一眼看完（无头验证用）
static func describe_all() -> String:
	var lines := PackedStringArray()
	for m in catalog():
		lines.append("· %s  《%s》  %d-%d 人  %s" % [
			m["id"], m["name"], m["min_players"], m["max_players"], m["desc"],
		])
	return "\n".join(lines)
