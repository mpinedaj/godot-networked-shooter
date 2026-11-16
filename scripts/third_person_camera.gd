extends Camera3D
## Cámara en tercera persona (solo local, no se replica).
## El mouse capturado controla yaw (giro horizontal) y pitch (vertical).
## La cámara se coloca detrás y sobre el hombro derecho del jugador objetivo,
## y se acerca si una pared se interpone.

const MOUSE_SENSITIVITY := 0.0025
const PITCH_MIN := -0.9   # Mirar hacia abajo (rad).
const PITCH_MAX := 0.35   # Mirar hacia arriba (rad).
const PIVOT_HEIGHT := 1.6
## Desplazamiento relativo al pivote: derecha, arriba, atrás.
const OFFSET := Vector3(0.6, 0.35, 3.2)
const COLLISION_MARGIN := 0.2

var target: Node3D = null
var yaw: float = 0.0
var pitch: float = -0.3

func _ready() -> void:
	capture_mouse(true)

func capture_mouse(on: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE

func is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and is_mouse_captured():
		yaw -= event.relative.x * MOUSE_SENSITIVITY
		pitch = clampf(pitch - event.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
	elif event is InputEventMouseButton and event.pressed and not is_mouse_captured():
		# Clic con el mouse libre: volver a capturarlo (no dispara).
		capture_mouse(true)
		get_viewport().set_input_as_handled()

## Base horizontal de la cámara: para convertir WASD a dirección en el mundo.
func get_yaw_basis() -> Basis:
	return Basis(Vector3.UP, yaw)

func _process(_delta: float) -> void:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return
	var pivot := target.global_position + Vector3(0, PIVOT_HEIGHT, 0)
	var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var desired := pivot + rot * OFFSET
	# "Spring arm": si hay una pared entre el pivote y la cámara, acercarla.
	var query := PhysicsRayQueryParameters3D.create(pivot, desired)
	if target is CollisionObject3D:
		query.exclude = [target.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		desired = hit.position + (pivot - desired).normalized() * COLLISION_MARGIN
	global_transform = Transform3D(rot, desired)
