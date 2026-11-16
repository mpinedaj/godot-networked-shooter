extends Node3D
## Escena de juego (3D, tercera persona). El servidor spawnea jugadores, gestiona
## el mapa y el marcador. Los clientes reconstruyen el mismo mapa localmente
## (semilla fija) y reciben jugadores/balas por los MultiplayerSpawner.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const MENU_SCENE := "res://scenes/main_menu.tscn"
## Arena: X en [-HALF.x, HALF.x], Z en [-HALF.y, HALF.y] (metros).
const HALF := Vector2(18, 12)
const WALL_THICKNESS := 0.6   # Muros del borde.
const BORDER_HEIGHT := 3.0
const CRATE_SIZE := 1.2
## Coberturas: los muros altos tapan la vista; los bajos cubren medio cuerpo
## y se pueden saltar (el salto llega a ~1,2 m).
const HIGH := 2.4
const LOW := 1.0
const COVER_THICKNESS := 0.4
## Mapa diseñado a mano. Se describe UN cuadrante (x >= 0, z >= 0) y se refleja
## en los otros tres: así es simétrico y nadie aparece con ventaja.
## Cada muro: [centro x, centro z, largo en x, largo en z, alto].
const QUADRANT_WALLS := [
	[13.75, 6.0, 3.5, COVER_THICKNESS, HIGH],  # Cuarto de la esquina: muro hacia el centro.
	[12.0, 7.75, COVER_THICKNESS, 3.5, HIGH],  # Cuarto de la esquina: muro hacia el pasillo.
	[5.5, 6.0, 5.0, COVER_THICKNESS, HIGH],    # Separa el pasillo lateral del centro.
	[3.0, 0.0, COVER_THICKNESS, 3.0, LOW],     # Anillo de coberturas del centro.
	[0.0, 3.0, 3.0, COVER_THICKNESS, LOW],
	[13.5, 0.0, COVER_THICKNESS, 3.0, LOW],    # Cobertura de la zona de aparición.
	[7.0, 9.5, COVER_THICKNESS, 2.0, LOW],     # Cobertura en el pasillo.
]
const QUADRANT_CRATES := [Vector2(8.5, 2.5), Vector2(9.5, 10.5)]
## Color de cada cuarto de esquina (luz y piso), para orientarse: [x, z, color].
const ZONES := [
	[15.0, 9.0, Color(0.95, 0.3, 0.25)], [-15.0, 9.0, Color(0.3, 0.5, 1.0)],
	[15.0, -9.0, Color(0.3, 0.9, 0.4)], [-15.0, -9.0, Color(1.0, 0.85, 0.25)],
]
## Modelos del escenario y su tamaño original (medido del FBX importado).
const WALL_MODEL := "res://Assets/Environment/Wall_01.fbx"
const WALL_MODEL_SIZE := Vector3(4.0, 2.4, 0.3)
const BOX_MODEL := "res://Assets/Environment/Box_01.fbx"
const BOX_MODEL_SIZE := 0.743
const ThirdPersonCamera := preload("res://scripts/third_person_camera.gd")

## Cámara en tercera persona del jugador local (no se replica).
var camera = null  # third_person_camera.gd

## Estado de la partida. Lo decide el servidor y lo replica con sync_state.
enum State { LOBBY, PLAYING, ENDED }
const KILLS_TO_WIN := 10
const END_SCREEN_TIME := 6.0  # s mostrando al ganador antes de la siguiente ronda.
var state: int = State.LOBBY
var winner_name: String = ""

var kills_map: Dictionary = {}  # peer_id -> kills (autoritativo en el servidor)
var _bullet_counter: int = 0
## Los dos primeros (los primeros jugadores) quedan en lados opuestos.
var spawn_points: Array[Vector3] = [
	Vector3(-16, 0, 0), Vector3(16, 0, 0), Vector3(0, 0, -9), Vector3(0, 0, 9),
	Vector3(-15.5, 0, 9.5), Vector3(15.5, 0, -9.5), Vector3(15.5, 0, 9.5), Vector3(-15.5, 0, -9.5),
]

@onready var players_node: Node3D = $Players
@onready var bullets_node: Node3D = $Bullets
@onready var spawner_players: MultiplayerSpawner = $SpawnerPlayers
@onready var hud: CanvasLayer = $HUD
@onready var map_node: Node3D = $Map

func _ready() -> void:
	_build_map()
	# Spawner de jugadores con función propia: los datos de spawn son [peer_id, slot, nombre].
	# El servidor crea al jugador cuando el cliente se presenta (request_spawn).
	spawner_players.spawn_function = _spawn_player_custom
	# Balas: cualquier bullet.tscn añadida bajo Bullets en el servidor se replica sola.
	$SpawnerBullets.add_spawnable_scene("res://scenes/bullet.tscn")
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.server_disconnected_sig.connect(_on_lost_connection.bind("El servidor se desconectó."))
	NetworkManager.connection_failed_sig.connect(_on_lost_connection.bind("No se pudo conectar. Verifica IP, puerto y firewall."))
	hud.setup(self)
	sync_state(State.LOBBY, "")  # Todos empiezan en la sala de espera hasta saber el estado real.
	if multiplayer.is_server():
		# El host también juega: spawnea su propio jugador.
		_server_spawn_player(1, NetworkManager.player_name)
	elif multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_send_hello()
	else:
		NetworkManager.connected_to_server_ok.connect(_send_hello, CONNECT_ONE_SHOT)

func _process(_delta: float) -> void:
	# Cada peer sigue a SU jugador (la cámara es local, no se replica).
	if not is_instance_valid(camera.target):
		camera.target = players_node.get_node_or_null(str(multiplayer.get_unique_id()))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		# Primer Esc: soltar el mouse. Segundo Esc (mouse libre): salir de la partida.
		if camera.is_mouse_captured():
			camera.capture_mouse(false)
		else:
			_leave("Saliste de la partida.")

# ---------------- Mapa (determinista: igual en todos los peers) ----------------
func _build_map() -> void:
	_build_environment()

	# Suelo con colisión (los jugadores caen por gravedad): su cara superior está en y = 0.
	var floor_size := HALF * 2 + Vector2(WALL_THICKNESS, WALL_THICKNESS) * 2
	var ground := _make_block(Vector3(0, -1, 0), Vector3(floor_size.x, 1, floor_size.y), Color.WHITE)
	(ground.get_child(1) as MeshInstance3D).material_override = _floor_material()
	map_node.add_child(ground)
	_build_zones()

	var walls := Node3D.new()
	walls.name = "Walls"
	map_node.add_child(walls)
	# Bordes: muros Wall_01 repetidos a lo largo de cada lado.
	var t := WALL_THICKNESS
	var long := HALF.x * 2 + t * 2
	var short := HALF.y * 2
	walls.add_child(_make_wall(Vector3(0, 0, -HALF.y - t / 2), long, false, BORDER_HEIGHT, t))
	walls.add_child(_make_wall(Vector3(0, 0, HALF.y + t / 2), long, false, BORDER_HEIGHT, t))
	walls.add_child(_make_wall(Vector3(-HALF.x - t / 2, 0, 0), short, true, BORDER_HEIGHT, t))
	walls.add_child(_make_wall(Vector3(HALF.x + t / 2, 0, 0), short, true, BORDER_HEIGHT, t))

	# Muros interiores y cajas: el cuadrante descrito arriba, reflejado en los cuatro.
	for w in _mirror(QUADRANT_WALLS):
		var along_z: bool = w[3] > w[2]
		walls.add_child(_make_wall(Vector3(w[0], 0, w[1]), maxf(w[2], w[3]), along_z, w[4], minf(w[2], w[3])))
	for c in _mirror(QUADRANT_CRATES.map(func(v): return [v.x, v.y])):
		walls.add_child(_make_crate(Vector3(c[0], 0, c[1])))
	# Columna de dos cajas en el centro: tapa la vista de lado a lado.
	walls.add_child(_make_crate(Vector3.ZERO))
	walls.add_child(_make_crate(Vector3(0, CRATE_SIZE, 0)))

## Refleja piezas [x, z, ...] del cuadrante x>=0, z>=0 en los cuatro cuadrantes.
## Las que están sobre un eje (x = 0 o z = 0) no se duplican.
func _mirror(pieces: Array) -> Array:
	var out: Array = []
	var seen := {}
	for p in pieces:
		for sx in [1, -1]:
			for sz in [1, -1]:
				var q: Array = p.duplicate()
				q[0] = p[0] * sx
				q[1] = p[1] * sz
				var key := "%.2f,%.2f" % [q[0], q[1]]
				if not seen.has(key):
					seen[key] = true
					out.append(q)
	return out

func _make_crate(pos: Vector3) -> StaticBody3D:
	var crate := _make_block(pos, Vector3.ONE * CRATE_SIZE, Color(0.5, 0.38, 0.25), false)
	var m: Node3D = load(BOX_MODEL).instantiate()
	m.scale = Vector3.ONE * (CRATE_SIZE / BOX_MODEL_SIZE)  # El modelo ya está centrado.
	crate.add_child(m)
	return crate

func _build_environment() -> void:
	# Cámara en tercera persona; _process le asigna el jugador local cuando aparece.
	camera = ThirdPersonCamera.new()
	camera.fov = 70
	map_node.add_child(camera)
	camera.position = Vector3(0, 20, 16)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	# Luz del sol (cálida, de tarde) con sombras.
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.1
	map_node.add_child(sun)
	sun.rotation_degrees = Vector3(-50, -30, 0)
	# Cielo procedural: también ilumina la escena (luz ambiente).
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.4, 0.72)
	sky_mat.sky_horizon_color = Color(0.72, 0.76, 0.82)
	sky_mat.ground_horizon_color = Color(0.6, 0.62, 0.66)
	sky_mat.ground_bottom_color = Color(0.2, 0.2, 0.22)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	map_node.add_child(we)

## Piso a cuadros de 2 m: una textura de 2x2 píxeles generada en código y
## proyectada desde arriba (triplanar), así no hace falta ningún archivo.
func _floor_material() -> StandardMaterial3D:
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	var a := Color(0.52, 0.53, 0.5)
	var b := Color(0.45, 0.46, 0.44)
	img.set_pixel(0, 0, a)
	img.set_pixel(1, 1, a)
	img.set_pixel(1, 0, b)
	img.set_pixel(0, 1, b)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.25  # 1 repetición (2x2 cuadros) cada 4 m.
	return m

## Cada cuarto de esquina con su color: un piso tintado y una luz.
func _build_zones() -> void:
	for z in ZONES:
		var color: Color = z[2]
		var patch := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(5.6, 5.6)
		patch.mesh = plane
		patch.material_override = _mat(color.lerp(Color(0.5, 0.5, 0.5), 0.45))
		patch.position = Vector3(z[0], 0.01, z[1])
		map_node.add_child(patch)
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 2.0
		light.omni_range = 8.0
		light.position = Vector3(z[0], 2.6, z[1])
		map_node.add_child(light)

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

## Muro: una colisión de caja + modelos Wall_01 (4 m) estirados para cubrir
## exactamente `length` con la altura y el grosor pedidos. along_z = true si
## el muro va a lo largo del eje Z.
func _make_wall(center: Vector3, length: float, along_z: bool, height: float, thickness: float) -> StaticBody3D:
	var sb := _make_block(center, Vector3(length, height, thickness), Color.GRAY, false)
	if along_z:
		sb.rotation.y = PI / 2
	var n := ceili(length / WALL_MODEL_SIZE.x)
	var sx := length / (n * WALL_MODEL_SIZE.x)
	for i in n:
		var m: Node3D = load(WALL_MODEL).instantiate()
		# Wall_01 tiene la base en y=0 y está centrado en X/Z.
		m.scale = Vector3(sx, height / WALL_MODEL_SIZE.y, thickness / WALL_MODEL_SIZE.z)
		m.position = Vector3(-length / 2 + (i + 0.5) * WALL_MODEL_SIZE.x * sx, -height / 2, 0)
		sb.add_child(m)
	return sb

func next_bullet_id() -> int:
	_bullet_counter += 1
	return _bullet_counter

func random_spawn_point() -> Vector3:
	return spawn_points[randi() % spawn_points.size()]

# ---------------- Jugadores ----------------
## Cliente: al conectarse se presenta al servidor con su nombre.
func _send_hello() -> void:
	request_spawn.rpc_id(1, NetworkManager.player_name)

@rpc("any_peer", "call_remote", "reliable")
func request_spawn(player_name: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or players_node.has_node(str(id)):
		return
	_server_spawn_player(id, player_name)
	sync_state.rpc_id(id, state, winner_name)  # Quien entra tarde recibe el estado actual.

func _server_spawn_player(peer_id: int, player_name: String) -> void:
	# El servidor no confía en el cliente: limpia y recorta el nombre.
	player_name = player_name.strip_edges().replace("\n", " ").left(16)
	# Ranura libre más baja (define color/nombre y punto de aparición inicial).
	var used: Array = []
	for p in players_node.get_children():
		used.append(p.slot)
	var slot := 0
	while slot in used:
		slot += 1
	kills_map[peer_id] = 0
	spawner_players.spawn([peer_id, slot, player_name])
	_broadcast_kills()

func _spawn_player_custom(data: Variant) -> Node:
	# Se ejecuta en el servidor y en cada cliente con los mismos datos.
	var p = PLAYER_SCENE.instantiate()
	p.setup(int(data[0]), int(data[1]), str(data[2]))
	# La posición real llega replicada (spawn=true); esto es el valor del servidor.
	p.position = spawn_points[int(data[1]) % spawn_points.size()]
	return p

# ---------------- Estado de la partida ----------------
func is_playing() -> bool:
	return state == State.PLAYING

## Servidor (botón "Iniciar" del host): marcador a cero, todos a su punto de
## aparición con vida y munición completas, y a jugar.
func start_match() -> void:
	if not multiplayer.is_server():
		return
	for k in kills_map.keys():
		kills_map[k] = 0
	_broadcast_kills()
	for p in players_node.get_children():
		p.reset_for_round(spawn_points[p.slot % spawn_points.size()])
	sync_state.rpc(State.PLAYING, "")

@rpc("authority", "call_local", "reliable")
func sync_state(new_state: int, winner: String) -> void:
	var was_lobby := state == State.LOBBY
	state = new_state
	winner_name = winner
	# En la sala el mouse queda libre para pulsar "Iniciar"; al empezar se captura.
	camera.allow_capture = state != State.LOBBY
	if state == State.LOBBY:
		camera.capture_mouse(false)
	elif was_lobby:
		camera.capture_mouse(true)
	hud.on_state_changed()

func has_local_player() -> bool:
	return players_node.has_node(str(multiplayer.get_unique_id()))

func get_local_player() -> Node:
	return players_node.get_node_or_null(str(multiplayer.get_unique_id()))

func get_player_name(peer_id: int) -> String:
	var p = players_node.get_node_or_null(str(peer_id))
	return p.get_display_name() if p else "Peer %d" % peer_id

func _on_peer_left(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var p = players_node.get_node_or_null(str(peer_id))
	if p:
		p.queue_free()  # El spawner replica la eliminación.
	kills_map.erase(peer_id)
	_broadcast_kills()

# ---------------- Marcador ----------------
## Servidor: un jugador eliminó a otro.
func player_killed(killer_peer: int, victim_peer: int) -> void:
	kills_map[killer_peer] = kills_map.get(killer_peer, 0) + 1
	_broadcast_kills()
	if state == State.PLAYING and kills_map[killer_peer] >= KILLS_TO_WIN:
		# Fin de partida: todos ven al ganador y luego empieza otra ronda sola.
		sync_state.rpc(State.ENDED, get_player_name(killer_peer))
		get_tree().create_timer(END_SCREEN_TIME).timeout.connect(start_match)
	# Se envían los nombres ya resueltos: el cliente no tiene que buscarlos.
	kill_feed.rpc(get_player_name(killer_peer), get_player_name(victim_peer))

@rpc("authority", "call_local", "reliable")
func kill_feed(killer_name: String, victim_name: String) -> void:
	hud.add_kill_feed(killer_name, victim_name)

## Servidor: avisar SOLO al tirador de que acertó (si el tirador es el host,
## call_local hace que se ejecute aquí mismo sin pasar por la red).
func notify_hit(shooter_peer: int, killed: bool) -> void:
	if shooter_peer == 1 or shooter_peer in multiplayer.get_peers():
		hit_marker.rpc_id(shooter_peer, killed)

@rpc("authority", "call_local", "reliable")
func hit_marker(killed: bool) -> void:
	hud.show_hit_marker(killed)

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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # El menú necesita el cursor.
	NetworkManager.last_message = msg
	NetworkManager.close()
	get_tree().change_scene_to_file(MENU_SCENE)
