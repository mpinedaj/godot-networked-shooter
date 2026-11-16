extends Node3D
## Bala. El servidor decide los impactos: en cada paso lanza un rayo desde su
## posición anterior a la nueva, así no atraviesa paredes aunque vaya rápido.
## Por la red solo viaja su aparición (posición y dirección) y su desaparición:
## como vuela en línea recta, cada peer la mueve por su cuenta sin más paquetes.

const SPEED := 40.0  # m/s
const LIFETIME := 1.5
const DAMAGE := 25

var shooter_peer: int = 0
var shooter_rid: RID  # Cuerpo de quien disparó: el rayo lo ignora.
var life: float = LIFETIME

func _ready() -> void:
	set_multiplayer_authority(1)

func _physics_process(delta: float) -> void:
	var step := -global_basis.z * SPEED * delta
	if multiplayer.is_server():
		var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
		if shooter_rid.is_valid():
			query.exclude = [shooter_rid]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			if hit.collider.has_method("take_damage"):
				hit.collider.take_damage(DAMAGE, shooter_peer)
			queue_free()  # Jugador, pared o suelo: la bala desaparece en todos los peers.
			return
		life -= delta
		if life <= 0.0:
			queue_free()
			return
	global_position += step
