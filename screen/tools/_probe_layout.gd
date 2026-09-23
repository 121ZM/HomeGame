extends SceneTree

var h: Hud

func _init():
	# 建一个 1920x1080 的根，模拟 viewport 逻辑尺寸
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	get_root().add_child(root)

	h = Hud.new()
	root.add_child(h)
	h.setup()

	var lobby := Lobby.new()
	lobby.rebuild(4)   # 4 人
	var m := {
		"state": GameFlow.State.LOBBY,
		"online": 4, "max_players": 8,
		"recv": 120, "lost": 0, "port": 48000,
		"lobby": lobby,
		"roster": [],
		"hint": "",
	}
	h.update_view(m)

	# 强制一次布局
	root.size = Vector2(1920, 1080)
	await process_frame
	await process_frame

	print("===== 大厅纵向预算 (逻辑 1080 基准) =====")
	var page := h.get_child(2) # backdrop(0) topband 在 backdrop 内; page 是第 3 个 add_child
	# 直接遍历 _lobby_root
	var lr: Control = h.get("_lobby_root")
	if lr == null:
		print("no _lobby_root"); quit(); return
	lr.set_deferred("size", Vector2(1920 - 56*2, 1080 - 56*2))
	await process_frame
	_dump(lr, 0)
	print("lobby_root size=", lr.size)
	quit()

func _dump(n: Node, depth: int):
	var c := n as Control
	if c:
		print("%s%s  h=%.1f  y=%.1f  flags_v=%d" % ["  ".repeat(depth), n.name, c.size.y, c.position.y, c.size_flags_vertical])
	for ch in n.get_children():
		_dump(ch, depth + 1)
