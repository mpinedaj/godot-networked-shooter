extends RefCounted
## Efectos visuales cortos (solo locales, no viajan por la red): cada peer
## los crea por su cuenta a partir de lo que ya recibe (aparición de balas).

## Destello del cañón: una luz y una esfera brillante durante 0,05 s.
static func muzzle_flash(parent: Node3D, pos: Vector3) -> void:
	var root := Node3D.new()
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.4)
	light.light_energy = 4.0
	light.omni_range = 3.0
	root.add_child(light)
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	mesh.mesh = sphere
	mesh.material_override = _glow(Color(1.0, 0.85, 0.4))
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)
	parent.add_child(root)
	root.global_position = pos
	parent.get_tree().create_timer(0.05).timeout.connect(root.queue_free)

## Chispas donde pega la bala (rojas si le dio a un jugador).
static func impact(parent: Node3D, pos: Vector3, normal: Vector3, hit_player: bool) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.35
	p.explosiveness = 1.0
	p.direction = normal if normal != Vector3.ZERO else Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.05
	box.material = _glow(Color(0.9, 0.15, 0.1) if hit_player else Color(1.0, 0.8, 0.3))
	p.mesh = box
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	parent.get_tree().create_timer(1.0).timeout.connect(p.queue_free)

static func _glow(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m
