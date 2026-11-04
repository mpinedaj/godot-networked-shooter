extends Control
## Menú principal: crear partida (host), unirse por IP/puerto, salir.

@onready var ip_field: LineEdit = $VBox/IPField
@onready var port_field: LineEdit = $VBox/PortField
@onready var status_label: Label = $VBox/StatusLabel
@onready var host_button: Button = $VBox/HostButton
@onready var join_button: Button = $VBox/JoinButton
@onready var quit_button: Button = $VBox/QuitButton

func _ready() -> void:
	port_field.text = "9999"
	ip_field.text = "127.0.0.1"
	host_button.pressed.connect(_on_host)
	join_button.pressed.connect(_on_join)
	quit_button.pressed.connect(_on_quit)
	NetworkManager.connected_to_server_ok.connect(_on_connected_ok)
	NetworkManager.connection_failed_sig.connect(_on_connection_failed)
	NetworkManager.server_disconnected_sig.connect(_on_server_disconnected)

func _on_host() -> void:
	var port := int(port_field.text)
	var err: int = NetworkManager.create_server(port)
	if err != OK:
		status_label.text = "Error al crear servidor: %d" % err
		return
	status_label.text = "Servidor creado. Esperando jugadores..."
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_join() -> void:
	var ip := ip_field.text.strip_edges()
	var port := int(port_field.text)
	status_label.text = "Conectando a %s:%d..." % [ip, port]
	var err: int = NetworkManager.join_server(ip, port)
	if err != OK:
		status_label.text = "Error al conectar: %d" % err
		return

func _on_connected_ok() -> void:
	status_label.text = "Conectado. Entrando a la partida..."
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_connection_failed() -> void:
	status_label.text = "Falló la conexión. Verifica IP/puerto y firewall."

func _on_server_disconnected() -> void:
	status_label.text = "El servidor se desconectó."

func _on_quit() -> void:
	get_tree().quit()
