# LAN Shooter - Client-Server Architecture

## Description
An academic project developed for the Computer Networks course. It consists of a multiplayer third-person shooter that demonstrates the practical operation of a **Client-Server** architecture across two Local Area Networks joined by a WAN link between two routers. The project illustrates key networking concepts such as server authority, state synchronization, latency and routing, using the UDP protocol.

## Network Architecture
- **Topology:** PC1 (server) – LAN A – Router A – WAN – Router B – LAN B – PC2…PC5 (clients).
- **Local Host:** One machine simultaneously acts as the Server (physics and collision authority) and a Client.
- **Transport Protocol:** UDP port 9999 (ENet), optimized for low latency in real-time games.
- **Routing:** One static route per router, no NAT.

![Topology](docs/topologia-packet-tracer.png)

## How to Run
1. Open the project in Godot 4.7 and press F5.
2. On the server PC type a name and click **Crear partida (Host)**; the menu shows its local IP.
3. On each client PC type a name, the server IP and port 9999, then click **Unirse**.
4. Everyone waits in the lobby; the host clicks **Iniciar partida** when all players are in.

To try it on a single PC: Debug → Customize Run Instances → 2 instances, and join `127.0.0.1`.

Controls: WASD to move, Shift to sprint, Space to jump, mouse to aim, left click to shoot, R to reload, F3 for the network panel (F4/F5 inside it: simulated delay/loss), Esc to release the mouse (Esc again to leave).

## Gameplay
- Hand-designed symmetric arena: open centre, side corridors, a coloured room in each corner, high walls that block sight and low walls you can jump over.
- 12-round magazine with unlimited reserve; medkits at four fixed points (+50 health, back after 20 s).
- First to 10 eliminations wins; the winner is shown to everyone and a new round starts automatically.
- Muzzle flash, impact sparks, red screen edge when hit, hit marker when you hit, kill feed.
- Bad-network simulator (clients only): adds delay and packet loss to the unreliable streams to show how the game behaves on a poor link.

## Documentation
| File | Content |
|------|---------|
| [docs/red.md](docs/red.md) | Network design: topology, addressing table, routes and game messages |
| [docs/simulacion-packet-tracer.md](docs/simulacion-packet-tracer.md) | Cisco Packet Tracer simulation, router configuration and verification |
| [docs/red-lan-wan-lan.pkt](docs/red-lan-wan-lan.pkt) | Packet Tracer file (9.0.1) |
| [docs/prueba-real.md](docs/prueba-real.md) | Guide for the test with two physical PCs and routers |
| [docs/informe/main.tex](docs/informe/main.tex) | Project report in IEEE format (LaTeX, IEEEtran) |
| [docs/sustentacion.pdf](docs/sustentacion.pdf) | Guide for the oral presentation, in Spanish (source: [docs/sustentacion.html](docs/sustentacion.html)) |

## Technologies and Tools
- **Game Engine:** Godot 4.7 (3D)
- **Language:** GDScript
- **Network simulation:** Cisco Packet Tracer 9.0.1

## Authors
- Martin Pineda Jaramillo
- David Felipe Beltran Tabares
- Juan David Navarro Bermudez
