# Diagramas

Diagramas del proyecto en formato draw.io (`.drawio`), agrupados por tipo. Cada
archivo tiene una sola página y guarda XML sin comprimir, así que se puede leer
y comparar en Git. Se abren con el editor de draw.io o con la extensión de
VS Code; no necesitan conexión.

## `secuencia/` — diagramas de secuencia

El recorrido de los mensajes entre menú, `NetworkManager`, `game.gd` y los nodos
del juego.

| Archivo | Qué muestra |
|---|---|
| `01-conexion.drawio` | Crear la partida como host o unirse como cliente, y la entrada al juego. Sale de `scripts/main_menu.gd`, `scripts/network_manager.gd` y `scripts/game.gd`. |
| `02-partida.drawio` | Bucle de input a 60 Hz, sincronización de estado a 30 Hz y el disparo con su daño. Sale de `scripts/player.gd`, `scripts/bullet.gd` y `scripts/game.gd`. |
| `03-eventos-cierre.drawio` | Eliminaciones, fin de ronda, botiquines y desconexión. Incluye los estados de partida `LOBBY`, `PLAYING` y `ENDED`. |

## `red/` — topología de red

La red LAN–WAN–LAN que describe [`../red.md`](../red.md), montada en Packet
Tracer según [`../simulacion-packet-tracer.md`](../simulacion-packet-tracer.md).

| Archivo | Qué muestra |
|---|---|
| `01-topologia-fisica.drawio` | Equipos, modelos, puertos y tipo de cable (directo o cruzado) de cada enlace. |
| `02-topologia-logica.drawio` | Subredes, direcciones IP, rutas estáticas y el recorrido de un paquete del juego hasta el servidor. |
| `03-montaje-sustentacion.drawio` | Montaje real de la sustentación: dos PC, dos routers y el cable de consola. Sin switches. |
| `04-topologia-logica-sustentacion.drawio` | Direccionamiento, rutas estáticas y camino del paquete en el montaje de dos PC. |

## `estados/` — máquina de estados

| Archivo | Qué muestra |
|---|---|
| `01-estados-red.drawio` | Estados de la conexión (`NetworkManager`): desconectado, servidor escuchando, cliente conectando y cliente en partida, con sus disparadores y las dos formas de fallo. |
| `02-decision-configuracion.drawio` | Árbol de decisión para la sustentación: Cisco IOS con CLI o router con NAT, y qué revisar si no sale el prompt por consola. |

La máquina de estados de la **partida** (`LOBBY` → `PLAYING` → `ENDED`) no está
aquí: se dibuja en `secuencia/03-eventos-cierre.drawio`.
