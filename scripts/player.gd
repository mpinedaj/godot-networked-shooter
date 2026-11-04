extends CharacterBody3D
## Jugador (3D, vista cenital). La autoridad la tiene el servidor (peer id 1):
##  - Cada peer captura SU input. El host lo aplica directo; un cliente lo envía
##    al servidor por RPC (canal no fiable: si se pierde un paquete llega el siguiente).
##  - El servidor calcula movimiento, disparos, daño y muerte.
##  - El MultiplayerSynchronizer replica posición/orientación/vida/estado a todos.

const SPEED := 5.0  # m/s
const MAX_HEALTH := 100
const SHOOT_COOLDOWN := 0.25
const MUZZLE_DISTANCE := 0.9  # La bala nace fuera del propio cuerpo.
const GUN_HEIGHT := 1.0  # Altura del arma y de las balas (m).
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
		_update_label()

@export var is_dead: bool = false:
	set(value):
		is_dead = value
		_apply_dead_state()

# Input recibido (solo el servidor lo usa para simular).
var input_move: Vector2 = Vector2.ZERO
var input_aim: float = 0.0  # Ángulo (yaw) en radianes alrededor del eje Y.
var input_shoot: bool = false
var shoot_cooldown: float = 0.0

## "Visual" gira hacia donde apunta el jugador (su rotación se replica).
## El cuerpo físico no gira, así las etiquetas de arriba quedan derechas.
@onready var visual: Node3D = $Visual
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var name_label: Label3D = $NameLabel

func _ready() -> void:
	set_multiplayer_authority(1)
	_build_placeholder_visual()
	_apply_dead_state()
	_update_label()

func setup(p_peer_id: int, p_slot: int) -> void:
	peer_id = p_peer_id
	slot = p_slot
	name = str(peer_id)  # Nombre igual en todos los peers (ruta de los RPC).

func get_color() -> Color:
	return COLORS[slot % COLORS.size()]

func get_display_name() -> String:
	return COLOR_NAMES[slot % COLOR_NAMES.size()] + (" (host)" if peer_id == 1 else "")

func is_local() -> bool:
	return peer_id == multiplayer.get_unique_id()

## Dirección horizontal a la que mira un yaw dado (Godot: -Z es "adelante").
static func aim_direction(yaw: float) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, yaw)

# ---------------- Visual ----------------
func _build_placeholder_visual() -> void:
	# Cuerpo: cápsula del color del jugador.
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.6
	body.mesh = capsule
	body.position.y = 0.8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = get_color()
	body.material_override = mat
	visual.add_child(body)
	# Arma: caja alargada hacia adelante (-Z).
	var gun := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.14, 0.14, 0.6)
	gun.mesh = box
	gun.position = Vector3(0.25, GUN_HEIGHT, -0.45)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.15, 0.15, 0.18)
	gun.material_override = gmat
	visual.add_child(gun)

func _update_label() -> void:
	if name_label == null:
		return
	var txt := get_display_name() + (" - Tú" if is_local() else "")
	name_label.text = "%s\n%d HP" % [txt, health]
	name_label.modulate = Color.WHITE if is_local() else get_color().lightened(0.3)

func _apply_dead_state() -> void:
	visible = not is_dead
	if collision:
		# Diferido: puede llamarse dentro de un callback de física (impacto de bala).
		collision.set_deferred("disabled", is_dead)

# ---------------- Captura de input (en el peer dueño de este jugador) ----------------
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
	var aim := _mouse_aim()
	var shoot := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and get_window().has_focus()

	if multiplayer.is_server():
		# El host es servidor y jugador a la vez: aplica su input sin pasar por la red.
		_store_input(move, aim, shoot)
	else:
		# Cliente -> servidor. Solo se envía la intención, nunca la posición.
		receive_input.rpc_id(1, move, aim, shoot)
		# Predicción visual mínima: girar hacia el mouse sin esperar al servidor.
		visual.rotation.y = aim

## Proyecta el mouse sobre el plano horizontal a la altura del arma.
func _mouse_aim() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return input_aim
	var mp := get_viewport().get_mouse_position()
	var hit = Plane(Vector3.UP, GUN_HEIGHT).intersects_ray(cam.project_ray_origin(mp), cam.project_ray_normal(mp))
	if hit == null:
		return visual.rotation.y
	var d: Vector3 = hit - global_position
	d.y = 0
	if d.length() < 0.05:
		return visual.rotation.y
	return atan2(-d.x, -d.z)

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

# ---------------- Simulación (solo servidor) ----------------
func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if is_dead:
		return
	visual.rotation.y = input_aim
	shoot_cooldown -= delta
	if input_shoot and shoot_cooldown <= 0.0:
		shoot_cooldown = SHOOT_COOLDOWN
		_spawn_bullet(input_aim)
	velocity = Vector3(input_move.x, 0, input_move.y) * SPEED
	move_and_slide()

func _spawn_bullet(aim: float) -> void:
	# En el servidor: se añade bajo Game/Bullets y el MultiplayerSpawner la replica.
	var game = get_parent().get_parent()
	var b = BULLET_SCENE.instantiate()
	var origin := global_position + Vector3(0, GUN_HEIGHT, 0)
	b.position = origin + aim_direction(aim) * MUZZLE_DISTANCE
	b.rotation.y = aim
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
