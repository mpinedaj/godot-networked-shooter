extends Node
## Gestor de red (autoload). Encapsula toda la lógica de ENetMultiplayerPeer:
## crear servidor (listen server), unirse como cliente y reenviar señales.
##
## Transporte: ENet sobre UDP. ENet añade canales y entrega fiable opcional
## encima de UDP, así que podemos mandar el input como "unreliable" (rápido)
## y los eventos importantes como "reliable".

signal server_created
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal connected_to_server_ok
signal connection_failed_sig
signal server_disconnected_sig

const DEFAULT_PORT: int = 9999
const MAX_PLAYERS: int = 8

var peer: ENetMultiplayerPeer = null
var is_host: bool = false
var port: int = DEFAULT_PORT
## Mensaje para mostrar en el menú al volver (p. ej. "El servidor se desconectó").
var last_message: String = ""

func _ready() -> void:
	# Las señales de `multiplayer` se conectan UNA sola vez, así se puede
	# hostear/unirse varias veces en la misma sesión sin errores.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

## Crea un servidor listen-server. El host también juega (peer id 1).
func create_server(p_port: int) -> int:
	close()
	port = p_port
	var p := ENetMultiplayerPeer.new()
	# Escucha en todas las interfaces (0.0.0.0): sirve para localhost y para la LAN.
	var err := p.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	peer = p
	multiplayer.multiplayer_peer = peer
	is_host = true
	server_created.emit()
	return OK

## Se une como cliente a un servidor remoto por IP y puerto.
func join_server(ip: String, p_port: int) -> int:
	close()
	port = p_port
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(ip, port)
	if err != OK:
		return err
	peer = p
	multiplayer.multiplayer_peer = peer
	is_host = false
	return OK

## Cierra la conexión actual y vuelve al modo sin red.
func close() -> void:
	if peer != null:
		peer.close()
	peer = null
	is_host = false
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

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

## IP local (privada, IPv4) para mostrarla y que los clientes sepan a dónde conectarse.
func get_local_ip() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10."):
			return a
		if a.begins_with("172."):
			var second := int(a.split(".")[1])
			if second >= 16 and second <= 31:
				return a
	return "127.0.0.1"

func get_role() -> String:
	if peer == null:
		return "Sin conexión"
	return "Host (servidor + jugador)" if is_host else "Cliente"

func get_player_count() -> int:
	if peer == null:
		return 0
	return multiplayer.get_peers().size() + 1

## Latencia (RTT) medida por ENet en milisegundos.
## Cliente: RTT hacia el servidor. Host: RTT de cada cliente conectado.
func get_ping_text() -> String:
	if peer == null:
		return "n/a"
	if is_host:
		var parts: Array[String] = []
		for id in multiplayer.get_peers():
			var pp := peer.get_peer(id)
			if pp:
				parts.append("%d: %d ms" % [id, int(pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))])
		return "sin clientes" if parts.is_empty() else ", ".join(parts)
	var sp := peer.get_peer(1)
	if sp == null:
		return "conectando..."
	return "%d ms" % int(sp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
