extends Node
## Gestor de red (autoload). Encapsula toda la lógica de ENetMultiplayerPeer:
## crear servidor (listen server), unirse como cliente y reenviar señales.

signal server_created
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal connected_to_server_ok
signal connection_failed_sig
signal server_disconnected_sig

var peer: ENetMultiplayerPeer
var is_host: bool = false
var port: int = 9999
const MAX_PLAYERS: int = 8

## Crea un servidor listen-server. El host también juega (peer id 1).
func create_server(p_port: int) -> int:
	port = p_port
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	# Señales del servidor: llegada/salida de peers.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	server_created.emit()
	return OK

## Se une como cliente a un servidor remoto por IP y puerto.
func join_server(ip: String, p_port: int) -> int:
	port = p_port
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	return OK

func _on_peer_connected(id: int) -> void:
	peer_joined.emit(id)

func _on_peer_disconnected(id: int) -> void:
	peer_left.emit(id)

func _on_connected_to_server() -> void:
	connected_to_server_ok.emit()

func _on_connection_failed() -> void:
	connection_failed_sig.emit()

func _on_server_disconnected() -> void:
	server_disconnected_sig.emit()

## IP local (privada) para mostrar en HUD.
func get_local_ip() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.") or a.begins_with("10.") or a.begins_with("172."):
			return a
	return "127.0.0.1"

func get_role() -> String:
	if multiplayer.multiplayer_peer == null:
		return "Sin conexión"
	return "Host" if is_host else "Cliente"

func get_player_count() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_peers().size() + 1
