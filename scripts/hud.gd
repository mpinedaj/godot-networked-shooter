extends CanvasLayer
## HUD: marcador de kills, ayuda de controles, estado del jugador y panel de red (F3).

var game: Node = null
var debug_visible: bool = false

@onready var debug_panel: Control = $DebugPanel
@onready var debug_label: Label = $DebugPanel/DebugLabel
@onready var kills_label: Label = $KillsLabel
@onready var status_label: Label = $StatusLabel

# Estado del jugador local (abajo a la derecha): vida, balas y resistencia.
var _stats_label: Label = null
var _stamina_bar: ProgressBar = null

func setup(g: Node) -> void:
	game = g
	debug_panel.visible = false
	update_kills({})
	_build_stats()

func _build_stats() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	box.offset_left = -330
	box.offset_top = -110
	box.offset_right = -50
	box.offset_bottom = -40
	add_child(box)
	_stats_label = Label.new()
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats_label.add_theme_font_size_override("font_size", 26)
	_stats_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_stats_label.add_theme_constant_override("outline_size", 6)
	box.add_child(_stats_label)
	_stamina_bar = ProgressBar.new()
	_stamina_bar.custom_minimum_size = Vector2(0, 10)
	_stamina_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.8, 0.25)
	_stamina_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_stamina_bar)

func _update_stats() -> void:
	var me = game.get_local_player() if game else null
	_stats_label.get_parent().visible = me != null
	if me == null:
		return
	var ammo_txt: String = "Recargando..." if me.reloading else "Balas %d / ∞" % me.ammo
	_stats_label.text = "Vida %d    %s" % [me.health, ammo_txt]
	_stamina_bar.max_value = me.MAX_STAMINA
	_stamina_bar.value = me.stamina

func _process(_delta: float) -> void:
	_update_stats()
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
