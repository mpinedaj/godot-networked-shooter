extends CharacterBody2D
## Jugador. La autoridad la tiene el servidor (peer id 1):
##  - Cada peer captura SU input. El host lo aplica directo; un cliente lo envía
##    al servidor por RPC (canal no fiable: si se pierde un paquete llega el siguiente).
##  - El servidor calcula movimiento, disparos, daño y muerte.
##  - El MultiplayerSynchronizer replica posición/vida/estado a todos.

const SPEED := 220.0
const MAX_HEALTH := 100
const SHOOT_COOLDOWN := 0.25
const RADIUS := 18.0
const MUZZLE_DISTANCE := 32.0  # La bala nace fuera del propio cuerpo.
const RESPAWN_TIME := 3.0
const BULLET_SCENE := preload("res://scenes/bullet.tscn")

const COLORS := [
	Color(0.90, 0.30, 0.30), Color(0.30, 0.55, 0.95), Color(0.35, 0.80, 0.40),
	Color(0.95, 0.80, 0.25), Color(0.75, 0.40, 0.90), Color(0.95, 0.55, 0.20),
	Color(0.30, 0.85, 0.85), Color(0.90, 0.45, 0.70),
]
const COLOR_NAMES := ["Rojo", "Azul", "Verde", "Amarillo", "Morado", "Naranja", "Cian", "Rosa"]

var peer_id: int = 0
## Ranura del jugador (0..7): define color y nombre. La asigna el servidor
## y viaja en los datos de spawn, así que es igual en todos los peers.
var slot: int = 0

@export var health: int = MAX_HEALTH:
	set(value):
		health = value
		queue_redraw()

@export var is_dead: bool = false:
	set(value):
		is_dead = value
		_apply_dead_state()

# Input recibido (solo el servidor lo usa para simular).
var input_move: Vector2 = Vector2.ZERO
var input_aim: float = 0.0
var input_shoot: bool = false
var shoot_cooldown: float = 0.0

@onready var gun: Node2D = $Gun
@onready var gun_visual: Polygon2D = $Gun/GunVisual
@onready var collision: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	# La autoridad del jugador es el servidor.
	set_multiplayer_authority(1)
	gun_visual.polygon = PackedVector2Array([
		Vector2(8, -4), Vector2(MUZZLE_DISTANCE - 4, -4),
		Vector2(MUZZLE_DISTANCE - 4, 4), Vector2(8, 4),
	])
	gun_visual.color = Color(0.15, 0.15, 0.18)
	_apply_dead_state()
	queue_redraw()

func setup(p_peer_id: int, p_slot: int) -> void:
	peer_id = p_peer_id
	slot = p_slot
	name = str(peer_id)  # Nombre igual en todos los peers (ruta de los RPC).

func get_display_name() -> String:
	return COLOR_NAMES[slot % COLOR_NAMES.size()] + (" (host)" if peer_id == 1 else "")

func is_local() -> bool:
	return peer_id == multiplayer.get_unique_id()

## --- Dibujo simple: cuerpo, barra de vida y nombre ---
func _draw() -> void:
	var c: Color = COLORS[slot % COLORS.size()]
	draw_circle(Vector2.ZERO, RADIUS, c)
	# El jugador local tiene borde blanco para reconocerse.
	var outline := Color.WHITE if is_local() else Color(0, 0, 0, 0.6)
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 32, outline, 3.0 if is_local() else 1.5)
	# Barra de vida.
	var w := 40.0
	var y := -RADIUS - 12
	draw_rect(Rect2(-w / 2, y, w, 5), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(-w / 2, y, w * float(health) / MAX_HEALTH, 5), Color(0.3, 0.9, 0.3))
	# Nombre.
	var font := ThemeDB.fallback_font
	var label := get_display_name() + (" - Tú" if is_local() else "")
	var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(font, Vector2(-size.x / 2, y - 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)

func _apply_dead_state() -> void:
	visible = not is_dead
	if collision:
		# Diferido: puede llamarse dentro de un callback de física (impacto de bala).
		collision.set_deferred("disabled", is_dead)

## --- Captura de input (en el peer dueño de este jugador) ---
func _process(_delta: float) -> void:
	if not is_local() or is_dead:
		return
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
		move.x += 1
	if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
		move.x -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		move.y += 1
	if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		move.y -= 1
	var aim := (get_global_mouse_position() - global_position).angle()
	var shoot := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _window_has_focus()

	if multiplayer.is_server():
		# El host es servidor y jugador a la vez: aplica su input sin pasar por la red.
		_store_input(move, aim, shoot)
	else:
		# Cliente -> servidor. Solo se envía la intención, nunca la posición.
		receive_input.rpc_id(1, move, aim, shoot)
		# Predicción visual mínima: el arma apunta al mouse sin esperar al servidor.
		gun.rotation = aim

func _window_has_focus() -> bool:
	# Con dos instancias en el mismo PC, evita que un clic en una ventana dispare en la otra.
	return get_window().has_focus()

@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func receive_input(move: Vector2, aim: float, shoot: bool) -> void:
	if not multiplayer.is_server():
		return
	# Solo el dueño de este jugador puede controlarlo.
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_store_input(move, aim, shoot)

func _store_input(move: Vector2, aim: float, shoot: bool) -> void:
	input_move = move.limit_length(1.0)  # El servidor no confía en el cliente.
	input_aim = aim
	input_shoot = shoot

## --- Simulación (solo servidor) ---
func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if is_dead:
		return
	gun.rotation = input_aim
	shoot_cooldown -= delta
	if input_shoot and shoot_cooldown <= 0.0:
		shoot_cooldown = SHOOT_COOLDOWN
		_spawn_bullet(input_aim)
	velocity = input_move * SPEED
	move_and_slide()

func _spawn_bullet(aim: float) -> void:
	# En el servidor: se añade bajo Game/Bullets y el MultiplayerSpawner la replica.
	var game = get_parent().get_parent()
	var b = BULLET_SCENE.instantiate()
	b.position = global_position + Vector2.from_angle(aim) * MUZZLE_DISTANCE
	b.rotation = aim
	b.shooter_peer = peer_id
	# Nombre único: si se reutiliza un nombre de una bala ya destruida, los
	# clientes pueden confundir los paquetes de sincronización de ambas.
	b.name = "B%d_%d" % [peer_id, game.next_bullet_id()]
	game.get_node("Bullets").add_child(b)

## Daño aplicado por el servidor cuando una bala impacta.
func take_damage(amount: int, from_peer: int) -> void:
	if not multiplayer.is_server() or is_dead:
		return
	health = max(0, health - amount)
	if health == 0:
		_die(from_peer)

func _die(killer_peer: int) -> void:
	is_dead = true  # Se replica: los clientes lo ocultan por el setter.
	input_shoot = false
	var game = get_parent().get_parent()
	if game and game.has_method("add_kill"):
		game.add_kill(killer_peer)
	# Si el jugador se va antes, la conexión del timer se elimina sola.
	get_tree().create_timer(RESPAWN_TIME).timeout.connect(_respawn)

func _respawn() -> void:
	var game = get_parent().get_parent()
	if game and game.has_method("random_spawn_point"):
		global_position = game.random_spawn_point()
	health = MAX_HEALTH
	is_dead = false
