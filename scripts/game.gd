extends Node3D
## Escena de juego (3D, vista cenital). El servidor spawnea jugadores, gestiona
## el mapa y el marcador. Los clientes reconstruyen el mismo mapa localmente
## (semilla fija) y reciben jugadores/balas por los MultiplayerSpawner.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const MENU_SCENE := "res://scenes/main_menu.tscn"
## Arena: X en [-HALF.x, HALF.x], Z en [-HALF.y, HALF.y] (metros).
const HALF := Vector2(12, 7)
const WALL_THICKNESS := 0.6
const WALL_HEIGHT := 1.5
const CRATE_SIZE := 1.2
## Modelos del escenario y su tamaño original (medido del FBX importado).
const WALL_MODEL := "res://Assets/Environment/Wall_01.fbx"
const WALL_MODEL_SIZE := Vector3(4.0, 2.4, 0.3)
const BOX_MODEL := "res://Assets/Environment/Box_01.fbx"
const BOX_MODEL_SIZE := 0.743
## Cámara: sigue al jugador local desde arriba y un poco atrás.
const CAM_OFFSET := Vector3(0, 9.5, 6.5)
const CAM_LOOK_HEIGHT := 0.8

var camera: Camera3D = null

var kills_map: Dictionary = {}  # peer_id -> kills (autoritativo en el servidor)
var _bullet_counter: int = 0
var spawn_points: Array[Vector3] = [
	Vector3(-8, 0, -3.5), Vector3(8, 0, 3.5), Vector3(8, 0, -3.5), Vector3(-8, 0, 3.5),
	Vector3(0, 0, 0), Vector3(0, 0, -4.5), Vector3(0, 0, 4.5), Vector3(-4, 0, 0),
]

@onready var players_node: Node3D = $Players
@onready var bullets_node: Node3D = $Bullets
@onready var spawner_players: MultiplayerSpawner = $SpawnerPlayers
@onready var hud: CanvasLayer = $HUD
@onready var map_node: Node3D = $Map

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

func _process(delta: float) -> void:
	# Cada peer sigue a SU jugador (la cámara es local, no se replica).
	var me = players_node.get_node_or_null(str(multiplayer.get_unique_id()))
	if me == null or camera == null:
		return
	var target: Vector3 = me.global_position + CAM_OFFSET
	camera.global_position = camera.global_position.lerp(target, 1.0 - exp(-8.0 * delta))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_leave("Saliste de la partida.")

# ---------------- Mapa (determinista: igual en todos los peers) ----------------
func _build_map() -> void:
	_build_environment()

	# Suelo (solo visual: los jugadores se mueven en el plano y = 0).
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = HALF * 2 + Vector2(WALL_THICKNESS, WALL_THICKNESS) * 2
	floor_mesh.mesh = plane
	floor_mesh.material_override = _mat(Color(0.55, 0.55, 0.5))
	map_node.add_child(floor_mesh)

	var walls := Node3D.new()
	walls.name = "Walls"
	map_node.add_child(walls)
	# Bordes: muros Wall_01 repetidos a lo largo de cada lado.
	var t := WALL_THICKNESS
	var long := HALF.x * 2 + t * 2
	var short := HALF.y * 2
	walls.add_child(_make_wall(Vector3(0, 0, -HALF.y - t / 2), long, false))
	walls.add_child(_make_wall(Vector3(0, 0, HALF.y + t / 2), long, false))
	walls.add_child(_make_wall(Vector3(-HALF.x - t / 2, 0, 0), short, true))
	walls.add_child(_make_wall(Vector3(HALF.x + t / 2, 0, 0), short, true))

	# Obstáculos (cajas Box_01) con semilla fija: todos los peers generan los mismos.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var placed := 0
	while placed < 12:
		var pos := Vector3(rng.randf_range(-HALF.x + 1.5, HALF.x - 1.5), 0, rng.randf_range(-HALF.y + 1.5, HALF.y - 1.5))
		if _near_spawn(pos):
			continue  # Sigue usando el mismo rng: el resultado sigue siendo determinista.
		var crate := _make_block(pos, Vector3.ONE * CRATE_SIZE, Color(0.5, 0.38, 0.25), false)
		var m: Node3D = load(BOX_MODEL).instantiate()
		m.scale = Vector3.ONE * (CRATE_SIZE / BOX_MODEL_SIZE)  # El modelo ya está centrado.
		crate.add_child(m)
		walls.add_child(crate)
		placed += 1

func _build_environment() -> void:
	# Cámara: orientación fija; _process la desplaza siguiendo al jugador local.
	camera = Camera3D.new()
	camera.fov = 50
	map_node.add_child(camera)
	camera.position = CAM_OFFSET
	camera.look_at(Vector3(0, CAM_LOOK_HEIGHT, 0))
	camera.make_current()
	# Luz del sol con sombras.
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	map_node.add_child(sun)
	sun.rotation_degrees = Vector3(-55, -30, 0)
	# Cielo/ambiente.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.11, 0.12, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.7)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	map_node.add_child(we)

func _near_spawn(pos: Vector3) -> bool:
	for sp in spawn_points:
		if pos.distance_to(sp) < 2.0:
			return true
	return false

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m

## Bloque con colisión apoyado en el suelo (center.y = 0 es la base).
## Si with_mesh es false, solo tiene colisión (el modelo se añade aparte).
func _make_block(center: Vector3, size: Vector3, color: Color, with_mesh := true) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = center + Vector3(0, size.y / 2, 0)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	if with_mesh:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = _mat(color)
		sb.add_child(mi)
	return sb

## Muro de borde: una colisión de caja + modelos Wall_01 (4 m) estirados para
## cubrir exactamente `length`. along_z = true para los muros laterales.
func _make_wall(center: Vector3, length: float, along_z: bool) -> StaticBody3D:
	var sb := _make_block(center, Vector3(length, WALL_HEIGHT, WALL_THICKNESS), Color.GRAY, false)
	if along_z:
		sb.rotation.y = PI / 2
	var n := ceili(length / WALL_MODEL_SIZE.x)
	var sx := length / (n * WALL_MODEL_SIZE.x)
	for i in n:
		var m: Node3D = load(WALL_MODEL).instantiate()
		# Wall_01 tiene la base en y=0 y está centrado en X/Z.
		m.scale = Vector3(sx, WALL_HEIGHT / WALL_MODEL_SIZE.y, WALL_THICKNESS / WALL_MODEL_SIZE.z)
		m.position = Vector3(-length / 2 + (i + 0.5) * WALL_MODEL_SIZE.x * sx, -WALL_HEIGHT / 2, 0)
		sb.add_child(m)
	return sb

func next_bullet_id() -> int:
	_bullet_counter += 1
	return _bullet_counter

func random_spawn_point() -> Vector3:
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
	var p = players_node.get_node_or_null(str(peer_id))
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
