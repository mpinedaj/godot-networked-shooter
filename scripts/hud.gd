extends CanvasLayer
## HUD: marcador de kills, ayuda de controles, estado del jugador y panel de red (F3).

var game: Node = null
var debug_visible: bool = false

@onready var debug_panel: Control = $DebugPanel
@onready var debug_label: Label = $DebugPanel/DebugLabel
@onready var kills_label: Label = $KillsLabel
@onready var status_label: Label = $StatusLabel

# Aviso de daño (borde rojo), marca de acierto y registro de eliminaciones.
const KILL_FEED_TIME := 5.0
const KILL_FEED_MAX := 4
var _damage_overlay: TextureRect = null
var _hit_marker: Control = null
var _hit_color: Color = Color.WHITE
var _kill_feed: VBoxContainer = null

# Sala de espera (centro): jugadores conectados y botón "Iniciar" para el host.
var _lobby: PanelContainer = null
var _lobby_players: Label = null
var _start_button: Button = null
# Pantalla de fin de partida (ganador y cuenta atrás).
var _end_label: Label = null
var _end_time: int = 0

# Estado del jugador local (abajo a la derecha): vida, balas y resistencia.
var _stats_label: Label = null
var _stamina_bar: ProgressBar = null

func setup(g: Node) -> void:
	game = g
	debug_panel.visible = false
	update_kills({})
	_build_stats()
	_build_feedback()
	_build_lobby()
	on_state_changed()

func _build_lobby() -> void:
	_lobby = PanelContainer.new()
	_lobby.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_lobby.custom_minimum_size = Vector2(440, 0)
	_lobby.offset_left = -220
	_lobby.offset_top = -170
	add_child(_lobby)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_lobby.add_child(box)
	var title := Label.new()
	title.text = "Sala de espera"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	_lobby_players = Label.new()
	box.add_child(_lobby_players)
	var goal := Label.new()
	goal.text = "Gana quien llegue primero a %d eliminaciones." % game.KILLS_TO_WIN
	goal.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	box.add_child(goal)
	_start_button = Button.new()
	_start_button.text = "Iniciar partida"
	_start_button.pressed.connect(func(): game.start_match())
	box.add_child(_start_button)
	_end_label = Label.new()
	_end_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_end_label.offset_left = -400
	_end_label.offset_right = 400
	_end_label.offset_top = -120
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_label.add_theme_font_size_override("font_size", 48)
	_end_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	_end_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_end_label.add_theme_constant_override("outline_size", 10)
	add_child(_end_label)

func on_state_changed() -> void:
	if _lobby == null:
		return
	_lobby.visible = game.state == game.State.LOBBY
	_start_button.visible = multiplayer.is_server()
	_end_label.visible = game.state == game.State.ENDED
	_end_time = Time.get_ticks_msec() + int(game.END_SCREEN_TIME * 1000)

func _update_lobby() -> void:
	if _end_label.visible:
		var left := ceili(maxf(0.0, _end_time - Time.get_ticks_msec()) / 1000.0)
		_end_label.text = "¡%s gana!\n" % game.winner_name
		_end_label.text += "Nueva partida en %d s" % left
	if not _lobby.visible:
		return
	var names: Array[String] = []
	for p in game.players_node.get_children():
		names.append("  • " + p.get_display_name())
	var txt := "Conectados (%d):\n%s" % [names.size(), "\n".join(names)]
	if not multiplayer.is_server():
		txt += "\n\nEsperando a que el host inicie la partida..."
	_lobby_players.text = txt

func _build_feedback() -> void:
	# Borde rojo: degradado radial transparente en el centro y rojo en los bordes.
	var grad := Gradient.new()
	grad.set_color(0, Color(0.8, 0, 0, 0))
	grad.set_color(1, Color(0.8, 0, 0, 0.75))
	grad.add_point(0.55, Color(0.8, 0, 0, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	_damage_overlay = TextureRect.new()
	_damage_overlay.texture = tex
	_damage_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_damage_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_overlay.modulate.a = 0.0
	add_child(_damage_overlay)
	move_child(_damage_overlay, 0)  # Detrás de los textos.
	# Marca de acierto: cuatro rayitas en diagonal alrededor de la mira.
	_hit_marker = Control.new()
	_hit_marker.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_hit_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_marker.modulate.a = 0.0
	_hit_marker.draw.connect(func():
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_hit_marker.draw_line(d * 7, d * 16, _hit_color, 3.0, true))
	add_child(_hit_marker)
	# Registro de eliminaciones (arriba a la derecha).
	_kill_feed = VBoxContainer.new()
	_kill_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_kill_feed.offset_left = -450
	_kill_feed.offset_top = 46
	_kill_feed.offset_right = -50
	_kill_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_kill_feed)

func show_damage() -> void:
	_damage_overlay.modulate.a = 1.0
	create_tween().tween_property(_damage_overlay, "modulate:a", 0.0, 0.5)

func show_hit_marker(killed: bool) -> void:
	_hit_color = Color(1, 0.2, 0.2) if killed else Color.WHITE
	_hit_marker.queue_redraw()
	_hit_marker.modulate.a = 1.0
	create_tween().tween_property(_hit_marker, "modulate:a", 0.0, 0.35 if killed else 0.2)

func add_kill_feed(killer_name: String, victim_name: String) -> void:
	var l := Label.new()
	l.text = "%s eliminó a %s" % [killer_name, victim_name]
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	_kill_feed.add_child(l)
	if _kill_feed.get_child_count() > KILL_FEED_MAX:
		_kill_feed.get_child(0).queue_free()
	var tw := l.create_tween()
	tw.tween_interval(KILL_FEED_TIME)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)

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
	_update_lobby()
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
