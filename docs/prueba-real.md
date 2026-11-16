# Prueba real: dos PC y dos routers

Guía para montar la topología de [`red.md`](red.md) con equipos físicos y jugar
de un PC al otro atravesando los dos routers.

## 1. Preparar los dos PC

1. Copiar a cada PC la carpeta del proyecto y el ejecutable de Godot 4.7 (es
   portable, no se instala).
2. Abrir el proyecto en Godot y ejecutar con F5.
3. **Solo en el PC servidor (PC1):** permitir la entrada de UDP 9999. En una
   consola de Windows como administrador:

   ```
   netsh advfirewall firewall add rule name="LAN Shooter UDP 9999" dir=in action=allow protocol=UDP localport=9999
   ```

   Para quitar la regla al terminar:

   ```
   netsh advfirewall firewall delete rule name="LAN Shooter UDP 9999"
   ```

4. Poner IP estática en cada PC (Configuración → Red → Ethernet → Editar IP):

   | PC  | IP            | Máscara       | Puerta de enlace |
   |-----|---------------|---------------|------------------|
   | PC1 | 192.168.1.10  | 255.255.255.0 | 192.168.1.1      |
   | PC2 | 192.168.2.10  | 255.255.255.0 | 192.168.2.1      |

   Si hay más jugadores, se conectan al Router B con las IP siguientes
   (`192.168.2.11`, `.12`, …) y la misma puerta de enlace.

## 2. Configurar los routers

Hay dos casos según el tipo de router disponible.

### Caso A: routers configurables (Cisco o similares)

Es el mismo montaje de la simulación. Cablear PC1 – Router A – Router B – PC2 y
aplicar los comandos de [`simulacion-packet-tracer.md`](simulacion-packet-tracer.md).
En el juego, el cliente escribe **`192.168.1.10`**.

### Caso B: routers caseros (TP-Link, etc.)

Un router casero siempre hace NAT en su puerto WAN y no deja quitarlo, así que
el montaje cambia un poco:

1. Unir los dos routers **por sus puertos WAN** con un cable de red.
2. Conectar cada PC a un puerto LAN de su router.
3. En la página de administración de cada router:

   | Ajuste              | Router A        | Router B        |
   |---------------------|-----------------|-----------------|
   | IP de la LAN        | 192.168.1.1     | 192.168.2.1     |
   | WAN: tipo           | IP estática     | IP estática     |
   | WAN: IP             | 10.0.0.1        | 10.0.0.2        |
   | WAN: máscara        | 255.255.255.252 | 255.255.255.252 |
   | WAN: puerta enlace  | 10.0.0.2        | 10.0.0.1        |

4. **Solo en Router A:** crear una redirección de puertos (Port Forwarding /
   Virtual Server): puerto externo **9999**, protocolo **UDP**, hacia
   `192.168.1.10` puerto 9999.
5. En el juego, el cliente escribe **`10.0.0.1`** (la IP WAN del Router A), no
   la IP privada del servidor: el Router A recibe el paquete y lo reenvía a PC1.

En este caso el `ping` de PC2 a `192.168.1.10` no responde (el NAT oculta la
LAN A); se prueba con `ping 10.0.0.1`.

## 3. Jugar

1. PC1: "Crear partida (Host)". El menú muestra su IP local.
2. PC2: escribir la IP del servidor (según el caso A o B), puerto 9999, y "Unirse".
3. En ambos, F3 abre el panel de red.

## 4. Evidencias para el informe

Tomar estas capturas durante la prueba:

| # | Dónde | Qué capturar |
|---|-------|--------------|
| 1 | PC2, consola | `ipconfig` (IP y puerta de enlace del cliente) |
| 2 | PC2, consola | `ping` al servidor (pérdida y TTL) |
| 3 | PC2, consola | `tracert` al servidor (los saltos por los routers) |
| 4 | PC1, juego   | Partida con F3 abierto: rol Host, jugadores 2, ping del cliente |
| 5 | PC2, juego   | Partida con F3 abierto: servidor, ping (RTT) y tráfico |
| 6 | Foto         | El montaje físico: dos PC y dos routers |

## Si no conecta

| Síntoma | Revisar |
|---------|---------|
| El cliente se queda en "Conectando a…" | Regla del firewall en PC1; IP escrita en el cliente |
| `ping` al gateway propio falla | Cable e IP estática del PC |
| `ping` al otro router falla | Cable WAN e IP WAN de ambos routers |
| Caso A: llega al router pero no al PC | Rutas estáticas en los dos routers |
| Caso B: llega a `10.0.0.1` pero el juego no | Redirección UDP 9999 en Router A |
