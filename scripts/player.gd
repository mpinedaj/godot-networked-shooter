extends CharacterBody2D
## Jugador. La autoridad la tiene el servidor (peer id 1): el cliente solo envía
## inputs mediante RPCs; el servidor calcula posición, disparos, daño y muerte.

const SPEED := 220.0
const MAX_HEALTH := 100
const BULLET_DAMAGE := 25

# Lista de texturas de personajes (asignada por el servidor al spawnear).
var character_textures: Array = []

@export var peer_id: int = 0
@export var health: int = MAX_HEALTH
@export var sprite_index: int = 0
@export var kills: int = 0
@export var is_dead: bool = false

# Inputs recibidos del cliente (solo el servidor los usa).
var input_move: Vector2 = Vector2.ZERO
var input_aim: float = 0.0
var input_shoot: bool = false
var shoot_cooldown: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var gun: Node2D = $Gun
@onready var gun_sprite: Sprite2D = $Gun/GunSprite
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var camera: Camera2D = $Camera2D

func _ready() -> void:
	# La autoridad del jugador es el servidor.
	set_multiplayer_authority(1)
	# Solo el jugador local tiene cámara activa.
	if multiplayer.get_unique_id() == peer_id:
		camera.make_current()
	# Aplicar sprite inicial.
	_apply_sprite()

func setup(p_peer_id: int, textures: Array) -> void:
	peer_id = p_peer_id
	character_textures = textures
	# El servidor elige el sprite aleatorio.
	if multiplayer.is_server():
		sprite_index = randi() % max(1, textures.size())
		rpc("set_sprite_index", sprite_index)
	_apply_sprite()

@rpc("authority", "call_remote", "reliable")
func set_sprite_index(idx: int) -> void:
	sprite_index = idx
	_apply_sprite()

func _apply_sprite() -> void:
	if character_textures.is_empty():
		return
	if sprite_index < 0 or sprite_index >= character_textures.size():
		sprite_index = 0
	var tex = character_textures[sprite_index]
	if tex != null:
		sprite.texture = tex
		# Las texturas son grandes (mapas de textura 3D), las escalamos.
		sprite.scale = Vector2(0.12, 0.12)

## --- RPCs de entrada (cliente -> servidor) ---
# El cliente envía su input; el servidor lo almacena y lo aplica en física.
@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func receive_input(move: Vector2, aim: float, shoot: bool) -> void:
	if not multiplayer.is_server():
		return
	# Solo el dueño de este jugador puede enviar input.
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	input_move = move
	input_aim = aim
	input_shoot = shoot

@rpc("any_peer", "call_remote", "reliable", 1)
func request_shoot(aim: float) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	if is_dead:
		return
	_spawn_bullet(aim)

func _spawn_bullet(aim: float) -> void:
	# Ejecutado en servidor: instancia la bala y la añade vía MultiplayerSpawner.
	var game = get_parent().get_parent()
	if game == null:
		return
	var bullet_scene = load("res://scenes/bullet.tscn")
	var b = bullet_scene.instantiate()
	b.global_position = gun.global_position
	b.rotation = aim
	b.shooter_peer = peer_id
	game.get_node("Bullets").add_child(b, true)

func _physics_process(delta: float) -> void:
	# Solo el servidor simula el movimiento.
	if not multiplayer.is_server():
		return
	if is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	# Apuntado del arma.
	gun.rotation = input_aim
	# Voltear sprite según dirección del mouse.
	if cos(input_aim) < 0:
		sprite.flip_h = true
	else:
		sprite.flip_h = false

	shoot_cooldown -= delta
	if input_shoot and shoot_cooldown <= 0.0:
		shoot_cooldown = 0.25
		_spawn_bullet(input_aim)

	# Movimiento con colisiones del servidor (autoridad).
	velocity = input_move.normalized() * SPEED
	move_and_slide()

	# Sincronizar vida/estado se hace por el synchronizer automáticamente.

## Daño aplicado por el servidor cuando una bala impacta.
func take_damage(amount: int, from_peer: int) -> void:
	if not multiplayer.is_server():
		return
	if is_dead:
		return
	health -= amount
	if health <= 0:
		health = 0
		_die(from_peer)

func _die(killer_peer: int) -> void:
	is_dead = true
	collision.disabled = true
	visible = false
	rpc("client_die")
	# Incrementar kills del asesino.
	var game = get_parent().get_parent()
	if game and game.has_method("add_kill"):
		game.add_kill(killer_peer)
	# Respawn tras 3 segundos.
	await get_tree().create_timer(3.0).timeout
	if multiplayer.is_server():
		_respawn()

func _respawn() -> void:
	health = MAX_HEALTH
	is_dead = false
	collision.disabled = false
	visible = true
	# Punto aleatorio del mapa.
	var game = get_parent().get_parent()
	if game and game.has_method("random_spawn_point"):
		global_position = game.random_spawn_point()
	rpc("client_respawn", global_position)

@rpc("authority", "call_remote", "reliable")
func client_die() -> void:
	visible = false

@rpc("authority", "call_remote", "reliable")
func client_respawn(pos: Vector2) -> void:
	global_position = pos
	visible = true

## En el cliente: capturar input y enviarlo al servidor.
func _process(delta: float) -> void:
	if multiplayer.is_server():
		return
	if peer_id != multiplayer.get_unique_id():
		return
	if is_dead:
		return
	var move := Vector2.ZERO
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		move.x += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		move.x -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		move.y += 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		move.y -= 1
	var mouse_pos := get_global_mouse_position()
	var aim := (mouse_pos - global_position).angle()
	var shoot := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	rpc_id(1, "receive_input", move, aim, shoot)
	if shoot:
		rpc_id(1, "request_shoot", aim)

	# Apuntado local visual (el servidor lo sobreescribe por sync de rotación del arma).
	gun.rotation = aim
	if cos(aim) < 0:
		sprite.flip_h = true
	else:
		sprite.flip_h = false
