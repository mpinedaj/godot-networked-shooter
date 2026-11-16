extends Node3D
## Bala. El servidor decide los impactos: en cada paso lanza un rayo desde su
## posición anterior a la nueva, así no atraviesa paredes aunque vaya rápido.
## Por la red solo viaja su aparición (posición, dirección y tirador) y su
## desaparición: como vuela en línea recta, cada peer la mueve por su cuenta.
## Los clientes lanzan el mismo rayo solo para dibujar las chispas del impacto.

const Effects := preload("res://scripts/effects.gd")
const SPEED := 40.0  # m/s
const LIFETIME := 1.5
const DAMAGE := 25

@export var shooter_peer: int = 0
var shooter_rid: RID  # Cuerpo de quien disparó: el rayo lo ignora.
var life: float = LIFETIME
var _hit: bool = false  # Cliente: ya chocó (se oculta hasta que el servidor la borre).

func _ready() -> void:
	set_multiplayer_authority(1)
	if not shooter_rid.is_valid():
		# Cliente: buscar el cuerpo del tirador con el id que llegó en el spawn.
		var shooter = _game().get_node_or_null("Players/%d" % shooter_peer)
		if shooter is CollisionObject3D:
			shooter_rid = shooter.get_rid()
	Effects.muzzle_flash(_game(), global_position)

func _game() -> Node3D:
	return get_parent().get_parent()

func _physics_process(delta: float) -> void:
	if _hit:
		return
	var step := -global_basis.z * SPEED * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
	if shooter_rid.is_valid():
		query.exclude = [shooter_rid]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var is_player: bool = hit.collider.has_method("take_damage")
		Effects.impact(_game(), hit.position, hit.normal, is_player)
		if multiplayer.is_server():
			if is_player:
				hit.collider.take_damage(DAMAGE, shooter_peer)
			queue_free()  # Jugador, pared o suelo: la bala desaparece en todos los peers.
		else:
			_hit = true
			visible = false
		return
	if multiplayer.is_server():
		life -= delta
		if life <= 0.0:
			queue_free()
			return
	global_position += step
