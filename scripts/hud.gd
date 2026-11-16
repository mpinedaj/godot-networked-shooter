extends CanvasLayer
## HUD: marcador de kills, ayuda de controles y panel de red (F3).

var game: Node = null
var debug_visible: bool = false

@onready var debug_panel: Control = $DebugPanel
@onready var debug_label: Label = $DebugPanel/DebugLabel
@onready var kills_label: Label = $KillsLabel
@onready var status_label: Label = $StatusLabel

func setup(g: Node) -> void:
	game = g
	debug_panel.visible = false
	update_kills({})

func _process(_delta: float) -> void:
	# Aviso mientras el cliente aún no recibe su jugador del servidor.
	var waiting: bool = game != null and not NetworkManager.is_host and not game.has_local_player()
	status_label.visible = waiting
	if waiting:
		status_label.text = "Conectando a %s ..." % NetworkManager.get_server_text()
	if not debug_visible:
		return
	var txt := ""
	txt += "Rol: %s\n" % NetworkManager.get_role()
	txt += "Mi peer id: %d\n" % multiplayer.get_unique_id()
	txt += "IP local: %s\n" % NetworkManager.get_local_ip()
	txt += "Servidor: %s (UDP)\n" % NetworkManager.get_server_text()
	txt += "Jugadores: %d\n" % NetworkManager.get_player_count()
	txt += "Ping (RTT): %s\n" % NetworkManager.get_ping_text()
	txt += NetworkManager.get_traffic_text() + "\n"
	txt += "FPS: %d" % Engine.get_frames_per_second()
	debug_label.text = txt

func update_kills(km: Dictionary) -> void:
	var lines: Array[String] = []
	for k in km.keys():
		var n: String = game.get_player_name(k) if game else "Peer %d" % k
		lines.append("%s: %d kills" % [n, km[k]])
	kills_label.text = "Marcador:\n" + "\n".join(lines)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		debug_visible = not debug_visible
		debug_panel.visible = debug_visible
		get_viewport().set_input_as_handled()
