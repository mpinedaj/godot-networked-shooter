extends CanvasLayer
## HUD de depuración (F3) y marcador de kills.

var game: Node = null
var debug_visible: bool = false

@onready var debug_panel: Control = $DebugPanel
@onready var debug_label: Label = $DebugPanel/DebugLabel
@onready var kills_label: Label = $KillsLabel

func setup(g: Node) -> void:
	game = g
	debug_panel.visible = false
	update_kills({})

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		pass
	if Input.is_key_pressed(KEY_F3):
		# Toggle con detección de flanco simple usando un flag.
		pass
	# Detectar pulsación de F3.
	if Input.is_action_just_pressed("toggle_debug"):
		debug_visible = !debug_visible
		debug_panel.visible = debug_visible

	if debug_visible:
		var ping := "n/a"
		if multiplayer.multiplayer_peer:
			ping = "%d ms (aprox)" % Engine.get_frames_per_second()  # placeholder
		var txt := ""
		txt += "Rol: %s\n" % NetworkManager.get_role()
		txt += "IP local: %s\n" % NetworkManager.get_local_ip()
		txt += "Jugadores: %d\n" % NetworkManager.get_player_count()
		txt += "FPS: %d\n" % Engine.get_frames_per_second()
		txt += "Ping: %s\n" % ping
		debug_label.text = txt

func update_kills(km: Dictionary) -> void:
	var lines: Array[String] = []
	for k in km.keys():
		lines.append("Peer %d: %d kills" % [k, km[k]])
	kills_label.text = "Marcador:\n" + "\n".join(lines)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		debug_visible = !debug_visible
		debug_panel.visible = debug_visible
		get_viewport().set_input_as_handled()
