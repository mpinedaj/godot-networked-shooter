# Diseño de red: LAN – WAN – LAN

El juego se demuestra sobre dos redes locales unidas por un enlace WAN entre dos
routers. En la LAN A hay un solo PC, que crea la partida y actúa como servidor
(además de jugar). En la LAN B están los demás jugadores, que se conectan como
clientes atravesando los dos routers.

No hay servidor dedicado: el equipo que crea la partida es el servidor
(*listen server*). Todo es local, sin servicios en la nube.

Para montarlo con equipos reales, ver [`prueba-real.md`](prueba-real.md). La guía
[`guia-routers-sustentacion.docx`](guia-routers-sustentacion.docx) resume el
cableado, la consola y la configuración para la sustentación con dos PC.

## Topología

```
                                                                    PC2  192.168.2.10
 PC1 (servidor)                                                    /PC3  192.168.2.11
 192.168.1.10                                                     / PC4  192.168.2.12
      |                                                          /  PC5  192.168.2.13
  [Switch A]                                                [Switch B]   (clientes)
      |                                                          |
   G0/0 192.168.1.1                                        192.168.2.1 G0/0
  [Router A] G0/1 10.0.0.1 ======== WAN ======== 10.0.0.2 G0/1 [Router B]

   LAN A: 192.168.1.0/24        WAN: 10.0.0.0/30        LAN B: 192.168.2.0/24
```

## Tabla de direccionamiento

| Dispositivo    | Interfaz | Dirección IP  | Máscara         | Gateway     |
|----------------|----------|---------------|-----------------|-------------|
| PC1 (servidor) | NIC      | 192.168.1.10  | 255.255.255.0   | 192.168.1.1 |
| Router A       | G0/0     | 192.168.1.1   | 255.255.255.0   | —           |
| Router A       | G0/1     | 10.0.0.1      | 255.255.255.252 | —           |
| Router B       | G0/1     | 10.0.0.2      | 255.255.255.252 | —           |
| Router B       | G0/0     | 192.168.2.1   | 255.255.255.0   | —           |
| PC2 (cliente)  | NIC      | 192.168.2.10  | 255.255.255.0   | 192.168.2.1 |
| PC3 (cliente)  | NIC      | 192.168.2.11  | 255.255.255.0   | 192.168.2.1 |
| PC4 (cliente)  | NIC      | 192.168.2.12  | 255.255.255.0   | 192.168.2.1 |
| PC5 (cliente)  | NIC      | 192.168.2.13  | 255.255.255.0   | 192.168.2.1 |

El enlace WAN usa una /30 porque solo necesita dos direcciones (una por router).
El juego admite hasta 8 jugadores; la LAN B puede crecer sin cambiar el diseño.

## Enrutamiento

Cada router conoce sus dos redes conectadas, pero no la LAN del otro lado. Se
resuelve con una **ruta estática** en cada uno (sin NAT):

| Router   | Red destino     | Siguiente salto |
|----------|-----------------|-----------------|
| Router A | 192.168.2.0/24  | 10.0.0.2        |
| Router B | 192.168.1.0/24  | 10.0.0.1        |

## Tráfico del juego

| Dato         | Valor                                               |
|--------------|-----------------------------------------------------|
| Arquitectura | Cliente-servidor (el servidor tiene la autoridad)   |
| Transporte   | UDP (ENet), puerto **9999**                         |
| Servidor     | PC1 – 192.168.1.10:9999                             |
| Clientes     | PC2 a PC5 – escriben `192.168.1.10` en "Unirse"     |

Recorrido de un paquete de un cliente al servidor:
`PC → Switch B → Router B (G0/0 → G0/1) → WAN → Router A (G0/1 → G0/0) → Switch A → PC1`.
Son 2 saltos de capa 3, así que el TTL llega disminuido en 2.

Los clientes no se comunican entre sí: todo pasa por el servidor, que reenvía
el estado de la partida a cada uno.

## Mensajes del juego

Todo viaja por la misma conexión ENet (UDP 9999). Lo que se repite muchas veces
por segundo va **no fiable**: si un paquete se pierde, el siguiente lo reemplaza.
Lo que ocurre una sola vez va **fiable**: ENet lo reenvía hasta que llega.

| Mensaje                                              | Sentido                  | Entrega                | Frecuencia      |
|------------------------------------------------------|--------------------------|------------------------|-----------------|
| Input: dirección, giro, apuntado vertical, botones   | cliente → servidor       | no fiable, ordenado    | 60 por segundo  |
| Posición y orientación de cada jugador               | servidor → todos         | no fiable              | 30 por segundo  |
| Vida, muerte, resistencia, munición, recarga         | servidor → todos         | fiable, solo si cambia | al cambiar      |
| Aparición y desaparición de jugadores y balas        | servidor → todos         | fiable                 | al ocurrir      |
| Presentación con el nombre del jugador               | cliente → servidor       | fiable                 | una vez         |
| Estado de la partida (sala, jugando, ganador)        | servidor → todos         | fiable                 | al cambiar      |
| Marcador, registro de eliminaciones, botiquines      | servidor → todos         | fiable                 | al ocurrir      |
| Marca de acierto                                     | servidor → solo el tirador | fiable               | al acertar      |

Los botones viajan empaquetados en un entero (un bit por botón: disparar,
saltar, correr, recargar), así el paquete de input no crece con cada acción
nueva. Las balas no envían su posición: el servidor solo anuncia dónde nacen y
hacia dónde van, y cada equipo las mueve por su cuenta. Los efectos visuales
(destellos, chispas, borde rojo) tampoco generan tráfico: cada equipo los
dibuja a partir de lo que ya recibe.

**Simulador de mala red.** En un cliente, con el panel F3 abierto, F4 añade
retraso (0, 50, 100, 200 o 400 ms en cada sentido) y F5 pérdida de paquetes
(0, 5, 10, 20 o 40 %) a los dos flujos no fiables. Sirve para mostrar en la
demo qué pasa con un enlace WAN malo: en la prueba local, la respuesta a una
tecla pasó de 66 ms a 502 ms con 200 ms por sentido y 10 % de pérdida, y los
demás jugadores se siguen moviendo suave gracias a la interpolación.

En el PC servidor, el Firewall de Windows debe permitir la entrada de UDP 9999.
