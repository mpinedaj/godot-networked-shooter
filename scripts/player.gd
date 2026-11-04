extends CharacterBody3D
## Jugador (3D, tercera persona). La autoridad la tiene el servidor (peer id 1):
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

## Modelos FBX (todos comparten el mismo esqueleto y un único clip "Take 001").
const CHARACTERS := ["Policeman", "Ninja", "Spaceman", "Skeleton", "Alien_Blobby", "Samurai_CapHead_Rigged", "Stag"]
const GUN_MODEL := "res://Assets/Guns/vectorGun.glb"
const ANIM := "Take 001"
## Tramos del clip (segundos), identificados a ojo renderizando el clip.
const IDLE_SECTION := Vector2(1.0, 4.0)
const RUN_SECTION := Vector2(6.7, 7.8)

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

# Animación (cada peer la decide localmente según si la posición cambia).
var anim_player: AnimationPlayer = null
var _running: bool = false
var _move_timer: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO

## "Visual" gira hacia donde apunta el jugador (su rotación se replica).
## El cuerpo físico no gira, así las etiquetas de arriba quedan derechas.
@onready var visual: Node3D = $Visual
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var name_label: Label3D = $NameLabel

## Barra de vida sobre la cabeza (dos quads que siempre miran a la cámara).
const BAR_SIZE := Vector2(0.9, 0.12)
const BAR_HEIGHT := 1.95
var _bar_root: Node3D = null  # Copia la rotación de la cámara cada frame.
var _bar_fill: MeshInstance3D = null

func _ready() -> void:
	set_multiplayer_authority(1)
	_build_visual()
	_build_health_bar()
	_last_pos = global_position
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
func _build_visual() -> void:
	# Personaje según la ranura (mismo en todos los peers porque slot viaja en el spawn).
	var model: Node3D = load("res://Assets/Character/%s.FBX" % CHARACTERS[slot % CHARACTERS.size()]).instantiate()
	model.rotation.y = PI  # Los FBX miran a +Z; en Godot "adelante" es -Z.
	visual.add_child(model)
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		anim_player = aps[0]
		anim_player.get_animation(ANIM).loop_mode = Animation.LOOP_LINEAR
		_play_section(false)
	# Arma fija apuntando hacia adelante: así se ve claro hacia dónde dispara.
	var gun: Node3D = load(GUN_MODEL).instantiate()
	gun.scale = Vector3.ONE * 1.6
	gun.position = Vector3(0.28, GUN_HEIGHT, -0.4)
	visual.add_child(gun)
	# Anillo de color en el suelo (no gira) para identificar al jugador.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.48
	torus.outer_radius = 0.6
	ring.mesh = torus
	ring.scale = Vector3(1, 0.2, 1)
	ring.position.y = 0.03
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE if is_local() else get_color()
	ring.material_override = mat
	add_child(ring)

func _build_health_bar() -> void:
	_bar_root = Node3D.new()
	_bar_root.position.y = BAR_HEIGHT
	add_child(_bar_root)
	_bar_root.add_child(_make_bar_quad(Color(0, 0, 0, 0.75), BAR_SIZE + Vector2(0.04, 0.04), 0))
	_bar_fill = _make_bar_quad(Color(0.3, 0.9, 0.3), BAR_SIZE, 1)
	_bar_root.add_child(_bar_fill)

func _make_bar_quad(color: Color, size: Vector2, priority: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = priority  # El relleno se dibuja encima del fondo.
	mat.albedo_color = color
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _update_health_bar() -> void:
	if _bar_fill == null:
		return
	var ratio := clampf(float(health) / MAX_HEALTH, 0.0, 1.0)
	_bar_fill.visible = ratio > 0.0
	_bar_fill.scale.x = maxf(ratio, 0.001)
	# X local de _bar_root = horizontal en pantalla (copia la rotación de la cámara):
	# desplazamos el relleno para que la barra se vacíe de derecha a izquierda.
	_bar_fill.position.x = -(1.0 - ratio) * BAR_SIZE.x / 2
	_bar_fill.position.z = 0.001  # Un pelo delante del fondo.
	(_bar_fill.material_override as StandardMaterial3D).albedo_color = Color(0.9, 0.25, 0.2).lerp(Color(0.3, 0.9, 0.3), ratio)

func _play_section(running: bool) -> void:
	if anim_player == null:
		return
	var s := RUN_SECTION if running else IDLE_SECTION
	anim_player.play_section(ANIM, s.x, s.y, 0.15)

## Corre si la posición (calculada en el servidor y replicada) está cambiando.
## Con un pequeño margen de tiempo para no parpadear entre paquetes de red.
func _update_animation(delta: float) -> void:
	var speed := global_position.distance_to(_last_pos) / maxf(delta, 0.0001)
	_last_pos = global_position
	if speed > 0.5:
		_move_timer = 0.15
	else:
		_move_timer -= delta
	var running := _move_timer > 0.0
	if running != _running:
		_running = running
		_play_section(running)

func _update_label() -> void:
	if name_label == null:
		return
	name_label.text = get_display_name() + (" - Tú" if is_local() else "")
	_update_health_bar()
	name_label.modulate = Color.WHITE if is_local() else get_color().lightened(0.3)
	# En tercera persona el nombre propio estorba la vista.
	name_label.visible = not is_local()

func _apply_dead_state() -> void:
	visible = not is_dead
	if collision:
		# Diferido: puede llamarse dentro de un callback de física (impacto de bala).
		collision.set_deferred("disabled", is_dead)

# ---------------- Captura de input (en el peer dueño de este jugador) ----------------
func _process(delta: float) -> void:
	_update_animation(delta)
	var view_cam := get_viewport().get_camera_3d()
	if view_cam and _bar_root:
		_bar_root.global_basis = view_cam.global_basis  # La barra siempre de frente.
	if not is_local() or is_dead:
		return
	# WASD en ejes de la cámara (x = derecha, y = atrás).
	var local := Vector2.ZERO
	if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
		local.x += 1
	if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
		local.x -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		local.y += 1
	if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		local.y -= 1
	var cam = get_viewport().get_camera_3d()
	var move := local
	var aim := visual.rotation.y
	var shoot := false
	if cam and cam.has_method("get_yaw_basis"):
		# Se envía la dirección YA en coordenadas del mundo: el servidor no
		# necesita saber nada de la cámara del cliente.
		var world: Vector3 = cam.get_yaw_basis() * Vector3(local.x, 0, local.y)
		move = Vector2(world.x, world.z)
		aim = cam.yaw  # El personaje mira hacia donde mira la cámara.
		shoot = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and cam.is_mouse_captured() and get_window().has_focus()

	if multiplayer.is_server():
		# El host es servidor y jugador a la vez: aplica su input sin pasar por la red.
		_store_input(move, aim, shoot)
	else:
		# Cliente -> servidor. Solo se envía la intención, nunca la posición.
		receive_input.rpc_id(1, move, aim, shoot)
		# Predicción visual mínima: girar hacia la cámara sin esperar al servidor.
		visual.rotation.y = aim

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
