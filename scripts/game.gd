extends Node2D
## Escena principal de juego. El servidor spawnea jugadores, gestiona mapa y marcador.

const PLAYER_SCENE := "res://scenes/player.tscn"
const BULLET_SCENE := "res://scenes/bullet.tscn"

var kills_map: Dictionary = {}  # peer_id -> kills
var spawn_points: Array[Vector2] = []
var character_textures: Array = []

@onready var players_node: Node2D = $Players
@onready var bullets_node: Node2D = $Bullets
@onready var spawner_players: MultiplayerSpawner = $SpawnerPlayers
@onready var spawner_bullets: MultiplayerSpawner = $SpawnerBullets
@onready var hud: CanvasLayer = $HUD
@onready var map_node: Node2D = $Map

func _ready() -> void:
	# Cargar texturas de personajes.
	_load_character_textures()
	# Generar mapa determinista.
	_build_map()
	# Configurar spawners.
	spawner_players.spawn_path = players_node.get_path()
	spawner_players.spawn_function = Callable(self, "_spawn_player_custom")
	spawner_bullets.spawn_path = bullets_node.get_path()
	# Conectar señales de red.
	NetworkManager.peer_joined.connect(_on_peer_joined)
	NetworkManager.peer_left.connect(_on_peer_left)
	NetworkManager.server_disconnected_sig.connect(_on_server_disconnected)
	# Si somos host, spawnear nuestro jugador vía spawner (replica a todos).
	if multiplayer.is_server():
		spawner_players.spawn(multiplayer.get_unique_id())
	# HUD.
	if hud and hud.has_method("setup"):
		hud.setup(self)

func _load_character_textures() -> void:
	var dir := DirAccess.open("res://Assets/Character/Textures")
	if dir:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".png"):
				var tex := load("res://Assets/Character/Textures/" + f)
				if tex:
					character_textures.append(tex)
			f = dir.get_next()
		dir.list_dir_end()
	# Si no se encontraron, dejar vacío (el jugador usará sprite por defecto).

func _build_map() -> void:
	# Mapa determinista: suelo + paredes + obstáculos.
	# Suelo
	var floor_sprite := Sprite2D.new()
	var floor_tex := load("res://Assets/Environment/FPSLite_Texture_01.png")
	floor_sprite.texture = floor_tex
	floor_sprite.scale = Vector2(4, 4)
	floor_sprite.position = Vector2(640, 360)
	floor_sprite.z_index = -10
	map_node.add_child(floor_sprite)

	# Paredes (bordes) con colisión.
	var walls := StaticBody2D.new()
	walls.name = "Walls"
	map_node.add_child(walls)
	var border_rects := [
		Rect2(0, 0, 1280, 40),
		Rect2(0, 720-40, 1280, 40),
		Rect2(0, 0, 40, 720),
		Rect2(1280-40, 0, 40, 720),
	]
	for r in border_rects:
		var sb := StaticBody2D.new()
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = r.size
		cs.shape = rs
		sb.position = r.position + r.size/2
		sb.add_child(cs)
		# Visual
		var vis := ColorRect.new()
		vis.size = r.size
		vis.position = -r.size/2
		vis.color = Color(0.3, 0.3, 0.35)
		sb.add_child(vis)
		walls.add_child(sb)

	# Obstáculos deterministas.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var obstacles := ["Box", "Rock", "Tree"]
	for i in range(12):
		var pos := Vector2(rng.randf_range(100, 1180), rng.randf_range(100, 620))
		# Evitar centro de spawn.
		var sb := StaticBody2D.new()
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = Vector2(48, 48)
		cs.shape = rs
		sb.position = pos
		sb.add_child(cs)
		var vis := ColorRect.new()
		vis.size = Vector2(48, 48)
		vis.position = Vector2(-24, -24)
		vis.color = Color(0.45, 0.35, 0.25)
		sb.add_child(vis)
		walls.add_child(sb)

	# Puntos de spawn.
	spawn_points = [
		Vector2(200, 200), Vector2(1080, 200), Vector2(200, 520), Vector2(1080, 520),
		Vector2(640, 360),
	]

func random_spawn_point() -> Vector2:
	if spawn_points.is_empty():
		return Vector2(640, 360)
	return spawn_points[randi() % spawn_points.size()]

func _spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var ps = load(PLAYER_SCENE)
	var p = ps.instantiate()
	p.peer_id = peer_id
	# Asignar texturas y sprite aleatorio (servidor).
	p.setup(peer_id, character_textures)
	p.global_position = random_spawn_point()
	players_node.add_child(p, true)
	kills_map[peer_id] = 0

func _spawn_player_custom(data) -> Node:
	# MultiplayerSpawner custom spawn: reconstruir jugador a partir de peer_id.
	var peer_id: int = int(data)
	var ps = load(PLAYER_SCENE)
	var p = ps.instantiate()
	p.peer_id = peer_id
	p.setup(peer_id, character_textures)
	p.global_position = random_spawn_point()
	kills_map[peer_id] = kills_map.get(peer_id, 0)
	return p

func _on_peer_joined(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Spawnear jugador para el nuevo peer.
	spawner_players.spawn(peer_id)

func _on_peer_left(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Eliminar jugador.
	for c in players_node.get_children():
		if c.peer_id == peer_id:
			c.queue_free()
	kills_map.erase(peer_id)

func add_kill(peer_id: int) -> void:
	kills_map[peer_id] = kills_map.get(peer_id, 0) + 1
	rpc("sync_kills", kills_map)

@rpc("authority", "call_remote", "reliable")
func sync_kills(km: Dictionary) -> void:
	kills_map = km
	if hud and hud.has_method("update_kills"):
		hud.update_kills(kills_map)

func _on_server_disconnected() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
