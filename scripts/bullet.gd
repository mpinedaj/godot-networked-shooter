extends Area3D
## Bala (3D). Autoridad del servidor: se crea, se mueve y detecta impactos en el
## servidor; los clientes solo ven su posición replicada.

const SPEED := 14.0  # m/s
const LIFETIME := 1.5
const DAMAGE := 25

var shooter_peer: int = 0
var direction: Vector3 = Vector3.FORWARD
var life: float = LIFETIME

func _ready() -> void:
	set_multiplayer_authority(1)
	direction = Vector3.FORWARD.rotated(Vector3.UP, rotation.y)
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	position += direction * SPEED * delta
	life -= delta
	if life <= 0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body.has_method("take_damage"):
		# Ignorar al que disparó (la bala no debe destruirse contra su dueño).
		if body.peer_id == shooter_peer:
			return
		body.take_damage(DAMAGE, shooter_peer)
	# Jugador enemigo o pared/obstáculo: la bala desaparece.
	queue_free()
