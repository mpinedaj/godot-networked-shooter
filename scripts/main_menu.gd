extends Control
## Menú principal: crear partida (host), unirse por IP/puerto, salir.

const GAME_SCENE := "res://scenes/game.tscn"

@onready var ip_field: LineEdit = $VBox/IPField
@onready var port_field: LineEdit = $VBox/PortField
@onready var status_label: Label = $VBox/StatusLabel
@onready var local_ip_label: Label = $VBox/LocalIPLabel
@onready var host_button: Button = $VBox/HostButton
@onready var join_button: Button = $VBox/JoinButton
@onready var quit_button: Button = $VBox/QuitButton

func _ready() -> void:
	port_field.text = str(NetworkManager.DEFAULT_PORT)
	ip_field.text = "127.0.0.1"
	local_ip_label.text = "Tu IP en la red local: %s" % NetworkManager.get_local_ip()
	# Mensaje pendiente (p. ej. al volver porque el servidor se cerró).
	status_label.text = NetworkManager.last_message
	NetworkManager.last_message = ""
	host_button.pressed.connect(_on_host)
	join_button.pressed.connect(_on_join)
	quit_button.pressed.connect(_on_quit)

func _on_host() -> void:
	var port := int(port_field.text)
	var err: int = NetworkManager.create_server(port)
	if err != OK:
		status_label.text = "Error al crear servidor (¿puerto %d ocupado?): %s" % [port, error_string(err)]
		return
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_join() -> void:
	var ip := ip_field.text.strip_edges()
	var port := int(port_field.text)
	var err: int = NetworkManager.join_server(ip, port)
	if err != OK:
		status_label.text = "Error al conectar: %s" % error_string(err)
		return
	# Cargamos la escena de juego YA (mientras ENet hace el handshake), para que
	# los MultiplayerSpawner existan cuando el servidor empiece a replicar.
	# Si la conexión falla, game.gd nos devuelve al menú con el mensaje.
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_quit() -> void:
	get_tree().quit()
