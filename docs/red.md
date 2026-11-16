# Diseño de red: LAN – WAN – LAN

El juego se demuestra sobre dos redes locales unidas por un enlace WAN entre dos
routers. En la LAN A hay un solo PC, que crea la partida y actúa como servidor
(además de jugar). En la LAN B están los demás jugadores, que se conectan como
clientes atravesando los dos routers.

No hay servidor dedicado: el equipo que crea la partida es el servidor
(*listen server*). Todo es local, sin servicios en la nube.

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

En el PC servidor, el Firewall de Windows debe permitir la entrada de UDP 9999.
