# Diseño de red: LAN – WAN – LAN

El juego se demuestra sobre dos redes locales unidas por un enlace WAN entre dos
routers. El servidor (host) está en la LAN A y el cliente en la LAN B.

## Topología

```
 PC1 (servidor)                                                    PC2 (cliente)
 192.168.1.10                                                      192.168.2.10
      |                                                                  |
  [Switch A]                                                        [Switch B]
      |                                                                  |
   G0/0 192.168.1.1                                        192.168.2.1 G0/0
  [Router A] G0/1 10.0.0.1 ======== WAN ======== 10.0.0.2 G0/1 [Router B]

   LAN A: 192.168.1.0/24        WAN: 10.0.0.0/30        LAN B: 192.168.2.0/24
```

## Tabla de direccionamiento

| Dispositivo | Interfaz | Dirección IP  | Máscara         | Gateway     |
|-------------|----------|---------------|-----------------|-------------|
| PC1         | NIC      | 192.168.1.10  | 255.255.255.0   | 192.168.1.1 |
| Router A    | G0/0     | 192.168.1.1   | 255.255.255.0   | —           |
| Router A    | G0/1     | 10.0.0.1      | 255.255.255.252 | —           |
| Router B    | G0/1     | 10.0.0.2      | 255.255.255.252 | —           |
| Router B    | G0/0     | 192.168.2.1   | 255.255.255.0   | —           |
| PC2         | NIC      | 192.168.2.10  | 255.255.255.0   | 192.168.2.1 |

El enlace WAN usa una /30 porque solo necesita dos direcciones (una por router).

## Enrutamiento

Cada router conoce sus dos redes conectadas, pero no la LAN del otro lado. Se
resuelve con una **ruta estática** en cada uno (sin NAT):

| Router   | Red destino     | Siguiente salto |
|----------|-----------------|-----------------|
| Router A | 192.168.2.0/24  | 10.0.0.2        |
| Router B | 192.168.1.0/24  | 10.0.0.1        |

## Tráfico del juego

| Dato        | Valor                                             |
|-------------|---------------------------------------------------|
| Arquitectura| Cliente-servidor (el servidor tiene la autoridad) |
| Transporte  | UDP (ENet), puerto **9999**                       |
| Servidor    | PC1 – 192.168.1.10:9999                           |
| Cliente     | PC2 – escribe `192.168.1.10` en "Unirse"          |

Recorrido de un paquete del cliente al servidor:
`PC2 → Switch B → Router B (G0/0 → G0/1) → WAN → Router A (G0/1 → G0/0) → Switch A → PC1`.
Son 2 saltos de capa 3, así que el TTL llega disminuido en 2.

En el PC servidor, el Firewall de Windows debe permitir la entrada de UDP 9999.
