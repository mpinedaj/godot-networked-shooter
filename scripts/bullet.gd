extends Area2D
## Bala. Autoridad del servidor: se spawnea en servidor, se mueve en servidor,
## y al impactar aplica daño mediante RPC/llamada local.

const SPEED := 600.0
const LIFETIME := 1.5
const DAMAGE := 25

var shooter_peer: int = 0
var direction: Vector2 = Vector2.RIGHT
var life: float = LIFETIME

@onready var visual: Polygon2D = $Visual

func _ready() -> void:
	# La bala la simula el servidor; los clientes solo la ven.
	set_multiplayer_authority(1)
	# Dibujar una bala simple (no hay asset de bala).
	if visual:
		visual.polygon = PackedVector2Array([Vector2(-6,-2),Vector2(6,-2),Vector2(6,2),Vector2(-6,2)])
		visual.color = Color(1, 0.9, 0.2)
	direction = Vector2.RIGHT.rotated(rotation)
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	global_position += direction * SPEED * delta
	life -= delta
	if life <= 0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return
	if body is CharacterBody2D and body.has_method("take_damage"):
		if body.peer_id != shooter_peer:
			body.take_damage(DAMAGE, shooter_peer)
	queue_free()

func _on_area_entered(area: Area2D) -> void:
	if not multiplayer.is_server():
		return
	queue_free()
