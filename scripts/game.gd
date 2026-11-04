extends Node2D
## Escena de juego. El servidor spawnea jugadores, gestiona el mapa y el marcador.
## Los clientes reconstruyen el mismo mapa localmente (semilla fija) y reciben
## jugadores/balas por los MultiplayerSpawner.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const MENU_SCENE := "res://scenes/main_menu.tscn"
const MAP_SIZE := Vector2(1280, 720)
const WALL := 40.0

var kills_map: Dictionary = {}  # peer_id -> kills (autoritativo en el servidor)
var _bullet_counter: int = 0
var spawn_points: Array[Vector2] = [
	Vector2(200, 200), Vector2(1080, 520), Vector2(1080, 200), Vector2(200, 520),
	Vector2(640, 360), Vector2(640, 140), Vector2(640, 580), Vector2(400, 360),
]

@onready var players_node: Node2D = $Players
@onready var bullets_node: Node2D = $Bullets
@onready var spawner_players: MultiplayerSpawner = $SpawnerPlayers
@onready var hud: CanvasLayer = $HUD
@onready var map_node: Node2D = $Map

func _ready() -> void:
	_build_map()
	# Spawner de jugadores con función propia: los datos de spawn son [peer_id, slot].
	spawner_players.spawn_function = _spawn_player_custom
	# Balas: cualquier bullet.tscn añadida bajo Bullets en el servidor se replica sola.
	$SpawnerBullets.add_spawnable_scene("res://scenes/bullet.tscn")
	NetworkManager.peer_joined.connect(_on_peer_joined)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.server_disconnected_sig.connect(_on_lost_connection.bind("El servidor se desconectó."))
	NetworkManager.connection_failed_sig.connect(_on_lost_connection.bind("No se pudo conectar. Verifica IP, puerto y firewall."))
	hud.setup(self)
	if multiplayer.is_server():
		# El host también juega: spawnea su propio jugador.
		_server_spawn_player(1)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_leave("Saliste de la partida.")

# ---------------- Mapa (determinista: igual en todos los peers) ----------------
func _build_map() -> void:
	var floor_rect := ColorRect.new()
	floor_rect.size = MAP_SIZE
	floor_rect.color = Color(0.16, 0.18, 0.16)
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_rect.z_index = -10
	map_node.add_child(floor_rect)

	var walls := Node2D.new()
	walls.name = "Walls"
	map_node.add_child(walls)
	# Bordes.
	for r in [
		Rect2(0, 0, MAP_SIZE.x, WALL),
		Rect2(0, MAP_SIZE.y - WALL, MAP_SIZE.x, WALL),
		Rect2(0, 0, WALL, MAP_SIZE.y),
		Rect2(MAP_SIZE.x - WALL, 0, WALL, MAP_SIZE.y),
	]:
		walls.add_child(_make_block(r.position + r.size / 2, r.size, Color(0.3, 0.3, 0.35)))

	# Obstáculos con semilla fija: todos los peers generan exactamente los mismos.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var placed := 0
	while placed < 12:
		var pos := Vector2(rng.randf_range(100, 1180), rng.randf_range(100, 620))
		if _near_spawn(pos):
			continue  # Sigue usando el mismo rng: el resultado sigue siendo determinista.
		walls.add_child(_make_block(pos, Vector2(48, 48), Color(0.45, 0.35, 0.25)))
		placed += 1

func _near_spawn(pos: Vector2) -> bool:
	for sp in spawn_points:
		if pos.distance_to(sp) < 80:
			return true
	return false

func _make_block(center: Vector2, size: Vector2, color: Color) -> StaticBody2D:
	var sb := StaticBody2D.new()
	sb.position = center
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = size
	cs.shape = rs
	sb.add_child(cs)
	var vis := ColorRect.new()
	vis.size = size
	vis.position = -size / 2
	vis.color = color
	vis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sb.add_child(vis)
	return sb

func next_bullet_id() -> int:
	_bullet_counter += 1
	return _bullet_counter

func random_spawn_point() -> Vector2:
	return spawn_points[randi() % spawn_points.size()]

# ---------------- Jugadores ----------------
func _server_spawn_player(peer_id: int) -> void:
	# Ranura libre más baja (define color/nombre y punto de aparición inicial).
	var used: Array = []
	for p in players_node.get_children():
		used.append(p.slot)
	var slot := 0
	while slot in used:
		slot += 1
	kills_map[peer_id] = 0
	spawner_players.spawn([peer_id, slot])
	_broadcast_kills()

func _spawn_player_custom(data: Variant) -> Node:
	# Se ejecuta en el servidor y en cada cliente con los mismos datos.
	var p = PLAYER_SCENE.instantiate()
	p.setup(int(data[0]), int(data[1]))
	# La posición real llega replicada (spawn=true); esto es el valor del servidor.
	p.position = spawn_points[int(data[1]) % spawn_points.size()]
	return p

func get_player_name(peer_id: int) -> String:
	var p = players_node.get_node_or_null(str(peer_id))
	return p.get_display_name() if p else "Peer %d" % peer_id

func _on_peer_joined(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_server_spawn_player(peer_id)

func _on_peer_left(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var p := players_node.get_node_or_null(str(peer_id))
	if p:
		p.queue_free()  # El spawner replica la eliminación.
	kills_map.erase(peer_id)
	_broadcast_kills()

# ---------------- Marcador ----------------
func add_kill(peer_id: int) -> void:
	kills_map[peer_id] = kills_map.get(peer_id, 0) + 1
	_broadcast_kills()

func _broadcast_kills() -> void:
	sync_kills.rpc(kills_map)

@rpc("authority", "call_local", "reliable")
func sync_kills(km: Dictionary) -> void:
	kills_map = km
	hud.update_kills.call_deferred(kills_map)  # Diferido: el jugador recién spawneado ya tiene nombre.

# ---------------- Conexión ----------------
func _on_lost_connection(msg: String) -> void:
	# Diferido: no cerrar el peer mientras ENet está emitiendo sus señales.
	_leave.call_deferred(msg)

func _leave(msg: String) -> void:
	NetworkManager.last_message = msg
	NetworkManager.close()
	get_tree().change_scene_to_file(MENU_SCENE)
