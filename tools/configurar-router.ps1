#Requires -Version 5.1
<#
.SYNOPSIS
  Configura un router Cisco por el cable de consola (USB-serial), sin PuTTY.

.DESCRIPTION
  Hace lo mismo que escribir a mano en PuTTY los comandos de la guía
  (docs/guia-routers-fisicos.pdf):
    1. Abre el puerto COM a 9600 baudios, 8 bits, sin paridad, 1 bit de parada.
    2. Despierta el router, contesta "no" al asistente inicial y entra a "enable".
    3. Lee las interfaces que tiene ("show ip interface brief") y propone cuál
       es la LAN y cuál la WAN.
    4. Aplica la configuración del Router A o del Router B (nombre, IPs,
       "no shutdown" y la ruta estática hacia la otra LAN).
    5. Muestra las interfaces y la tabla de rutas, y prueba ping al otro router.
  Todo lo que responde el router queda guardado en tools\registros\.

.EXAMPLE
  .\configurar-router.ps1                      # pregunta todo
.EXAMPLE
  .\configurar-router.ps1 -Router A -Puerto COM3
.EXAMPLE
  .\configurar-router.ps1 -Router B -SoloMostrar   # solo muestra los comandos
#>
[CmdletBinding()]
param(
    # A = el router de la LAN del PC host. B = el de la LAN del PC cliente.
    [ValidateSet('A', 'B')] [string]$Router,
    # Puerto COM del cable de consola (p. ej. COM3). Si se omite, se detecta.
    [string]$Puerto,
    # Velocidad de la consola Cisco: 9600 salvo que alguien la haya cambiado.
    [int]$Velocidad = 9600,
    # Nombres de interfaz (p. ej. GigabitEthernet0/0, Fa0/0, Serial0/0/0).
    # Si se omiten, se proponen a partir de lo que tenga el router.
    [string]$InterfazLan,
    [string]$InterfazWan,
    # Guardar en la memoria del router (write memory) sin preguntar.
    [switch]$Guardar,
    # No conecta nada: solo imprime los comandos que se enviarían.
    [switch]$SoloMostrar,
    # Para pruebas: objeto con métodos Write(texto), Read() y Close().
    [Parameter(DontShow)] [object]$IoPrueba
)

$ErrorActionPreference = 'Stop'

# ---------------- Plan de direcciones (igual que en Packet Tracer) ----------------
$Plan = @{
    A = @{ Nombre = 'RouterA'; Lan = '192.168.1.1'; Wan = '10.0.0.1'
           RedRemota = '192.168.2.0'; Vecino = '10.0.0.2'; PcLocal = '192.168.1.10'
           DescLan = 'LAN A - PC host'; DescWan = 'WAN hacia RouterB' }
    B = @{ Nombre = 'RouterB'; Lan = '192.168.2.1'; Wan = '10.0.0.2'
           RedRemota = '192.168.1.0'; Vecino = '10.0.0.1'; PcLocal = '192.168.2.10'
           DescLan = 'LAN B - PC cliente'; DescWan = 'WAN hacia RouterA' }
}
$MascaraLan = '255.255.255.0'
$MascaraWan = '255.255.255.252'

# Prompt de IOS al final de lo recibido: "Router>", "RouterA#", "RouterA(config-if)#".
$Prompt = '[\w\-\.]+(\([\w\-]+\))?[>#]\s*$'

# Lo que imprime el router puede terminar sin salto de línea (el prompt):
# los mensajes del script empiezan en una línea nueva para no quedar pegados.
$script:LineaAbierta = $false
function Close-Linea { if ($script:LineaAbierta) { Write-Host ''; $script:LineaAbierta = $false } }
function Write-Paso([string]$texto) { Close-Linea; Write-Host "`n== $texto" -ForegroundColor Cyan }
function Write-Ok([string]$texto) { Close-Linea; Write-Host "   OK  $texto" -ForegroundColor Green }
function Write-Aviso([string]$texto) { Close-Linea; Write-Host "   !!  $texto" -ForegroundColor Yellow }
function Write-Mal([string]$texto) { Close-Linea; Write-Host "   XX  $texto" -ForegroundColor Red }
function Read-Respuesta([string]$texto) { Close-Linea; return Read-Host $texto }
function Read-Clave([string]$texto) {
    Close-Linea
    $sec = Read-Host $texto -AsSecureString
    return [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}

## $puertosSwitch: puertos de switch del router (si los tiene). En ese caso la LAN
## es una interfaz Vlan: la IP va en ella y el PC se conecta a cualquier puerto de switch.
function Get-Comandos([string]$r, [string]$lan, [string]$wan, [bool]$wanEsDce, [string[]]$puertosSwitch = @()) {
    $p = $Plan[$r]
    $c = @(
        'configure terminal'
        "hostname $($p.Nombre)"
        'no ip domain-lookup'              # Un comando mal escrito no se queda "buscando" en DNS.
        'line console 0'
        ' logging synchronous'             # Los avisos no cortan lo que uno está escribiendo.
        ' exit'
    )
    if ($lan -match '^(?i)vlan\s*(\d+)$') {
        foreach ($sp in $puertosSwitch) {
            $c += @("interface $sp", " switchport access vlan $($matches[1])", ' no shutdown', ' exit')
        }
    }
    $c += @(
        "interface $lan"
        " description $($p.DescLan)"
        " ip address $($p.Lan) $MascaraLan"
        ' no shutdown'
        ' exit'
        "interface $wan"
        " description $($p.DescWan)"
        " ip address $($p.Wan) $MascaraWan"
    )
    if ($wanEsDce) { $c += ' clock rate 64000' }   # Solo en enlaces serie, del lado DCE.
    $c += @(
        ' no shutdown'
        ' exit'
        "ip route $($p.RedRemota) $MascaraLan $($p.Vecino)"
        'end'
    )
    return $c
}

# ---------------- Solo mostrar ----------------
if ($SoloMostrar) {
    if (-not $Router) { $Router = Read-Host 'Router (A o B)' }
    $Router = $Router.ToUpper()
    $lan = if ($InterfazLan) { $InterfazLan } else { 'GigabitEthernet0/0' }
    $wan = if ($InterfazWan) { $InterfazWan } else { 'GigabitEthernet0/1' }
    Write-Host "Comandos para el Router $Router (LAN: $lan, WAN: $wan):" -ForegroundColor Cyan
    $ejemplo = if ($lan -match '^(?i)vlan') { @('<puerto de switch>') } else { @() }
    Get-Comandos $Router $lan $wan $false $ejemplo | ForEach-Object { Write-Host "  $_" }
    return
}

# ---------------- Entrada / salida por el puerto serie ----------------
$Registro = New-Object System.Text.StringBuilder

function New-IoSerie([string]$nombre, [int]$baudios) {
    $p = New-Object System.IO.Ports.SerialPort $nombre, $baudios, ([System.IO.Ports.Parity]::None), 8, ([System.IO.Ports.StopBits]::One)
    $p.Handshake = [System.IO.Ports.Handshake]::None   # "Flow control: None" en PuTTY.
    $p.ReadTimeout = 500
    $p.WriteTimeout = 3000
    $p.Open()
    $io = [pscustomobject]@{ Port = $p }
    $io | Add-Member ScriptMethod Write { param($s) $this.Port.Write($s) }
    $io | Add-Member ScriptMethod Read { $this.Port.ReadExisting() }
    $io | Add-Member ScriptMethod Close { $this.Port.Close() }
    return $io
}

## Lee lo que llega hasta que aparezca $patron (o se acabe el tiempo).
function Read-Hasta([string]$patron, [int]$ms = 8000) {
    $buf = ''
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    while ($reloj.ElapsedMilliseconds -lt $ms) {
        $trozo = $script:Io.Read()
        if ($trozo) {
            $buf += $trozo
            [void]$Registro.Append($trozo)
            Write-Host -NoNewline $trozo -ForegroundColor DarkGray
            $script:LineaAbierta = -not $trozo.EndsWith("`n")
            if ($buf -match '--More--\s*$') { $script:Io.Write(' '); continue }
            if ($buf -match $patron) { return $buf }
        } else {
            Start-Sleep -Milliseconds 100
        }
    }
    return $buf
}

## Envía un comando y devuelve lo que respondió el router hasta el siguiente prompt.
function Send-Comando([string]$cmd, [int]$ms = 8000) {
    $script:Io.Write("$cmd`r")
    return Read-Hasta $Prompt $ms
}

function Get-PuertoConsola {
    $puertos = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '\((COM\d+)\)' } |
        ForEach-Object { [pscustomobject]@{ Puerto = ($_.Name -replace '.*\((COM\d+)\).*', '$1'); Nombre = $_.Name } })
    if ($puertos.Count -eq 0) {
        Write-Mal 'No hay ningún puerto COM. Revisa que el cable de consola esté conectado'
        Write-Mal 'y que Windows haya instalado su controlador (Administrador de dispositivos).'
        throw 'Sin puerto COM.'
    }
    Write-Host 'Puertos COM encontrados:'
    $puertos | ForEach-Object { Write-Host "   $($_.Puerto)   $($_.Nombre)" }
    if ($puertos.Count -eq 1) { return $puertos[0].Puerto }
    return (Read-Host 'Escribe el puerto del cable de consola (p. ej. COM3)').Trim().ToUpper()
}

# ---------------- Programa ----------------
if (-not $Router) {
    Write-Host 'Router A: el de la LAN del PC que crea la partida (host).'
    Write-Host 'Router B: el de la LAN del PC que se une (cliente).'
    $Router = (Read-Host 'Que router vas a configurar (A o B)').Trim().ToUpper()
}
$Router = $Router.ToUpper()
if (-not $Plan.ContainsKey($Router)) { throw 'El router debe ser A o B.' }
$p = $Plan[$Router]

if ($IoPrueba) {
    $script:Io = $IoPrueba
} else {
    if (-not $Puerto) { $Puerto = Get-PuertoConsola }
    Write-Paso "Abriendo $Puerto a $Velocidad baudios (8 bits, sin paridad, 1 bit de parada, sin control de flujo)"
    try {
        $script:Io = New-IoSerie $Puerto $Velocidad
    } catch {
        Write-Mal "No se pudo abrir $Puerto. Si PuTTY está abierto con ese puerto, ciérralo primero."
        throw
    }
}

try {
    # 1) Despertar el router y llegar al modo privilegiado (#).
    Write-Paso 'Despertando el router (Enter)'
    $listo = $false
    $reloj = [Diagnostics.Stopwatch]::StartNew()
    while (-not $listo -and $reloj.Elapsed.TotalSeconds -lt 120) {
        $script:Io.Write("`r")
        $out = Read-Hasta "($Prompt|\[yes/no\]|\[yes\]:|Password:\s*$)" 3000
        if ($out -match 'terminate autoinstall') {
            $script:Io.Write("yes`r")
        } elseif ($out -match '\[yes/no\]') {
            Write-Aviso 'El router ofrece el asistente inicial: se contesta "no".'
            $script:Io.Write("no`r")
            Start-Sleep -Seconds 3
        } elseif ($out -match 'Password:\s*$') {
            $script:Io.Write((Read-Clave 'El router pide contraseña (pídesela al profesor)') + "`r")
        } elseif ($out -match $Prompt) {
            $listo = $true
            $ultimo = $out
        } elseif (-not $out) {
            Write-Aviso '(sin respuesta todavía: si tarda más de un minuto revisa cable, puerto COM y velocidad)'
        }
    }
    if (-not $listo) { throw 'El router no respondió. Revisa el cable de consola, el puerto COM y que esté encendido.' }

    if ($ultimo -match '\(config[^\)]*\)#\s*$') { $ultimo = Send-Comando 'end' }
    if ($ultimo -match '>\s*$') {
        $script:Io.Write("enable`r")
        $ultimo = Read-Hasta "($Prompt|Password:\s*$)"
        if ($ultimo -match 'Password:\s*$') {
            $script:Io.Write((Read-Clave 'Contraseña de "enable" (pídesela al profesor)') + "`r")
            $ultimo = Read-Hasta $Prompt
        }
    }
    if ($ultimo -notmatch '#\s*$') { throw 'No se pudo entrar al modo privilegiado (enable).' }
    Write-Ok 'Router listo en modo privilegiado (#).'

    # 2) Ver qué interfaces tiene.
    Write-Paso 'Leyendo las interfaces del router'
    [void](Send-Comando 'terminal length 0')
    $out = Send-Comando 'show ip interface brief'
    $interfaces = @(foreach ($linea in ($out -split "`r?`n")) {
        if ($linea -match '^((?:Gigabit|Fast)?Ethernet\S+|Serial\S+|Vlan\d+)\s+(\S+)\s+\S+\s+\S+\s+(administratively down|up|down)\s+(up|down)') {
            [pscustomobject]@{ Interfaz = $matches[1]; IP = $matches[2]; Estado = $matches[3]; Protocolo = $matches[4] }
        }
    })
    # Puertos de switch integrados (módulo EHWIC/HWIC o routers como el 1100/890):
    # no llevan IP; la IP de la LAN va en la interfaz Vlan1.
    $sw = Send-Comando 'show interfaces switchport'
    $abrevSwitch = @([regex]::Matches($sw, '(?ms)^Name:\s*(\S+)\s*\r?\nSwitchport:\s*Enabled') | ForEach-Object { $_.Groups[1].Value })
    foreach ($i in $interfaces) {
        $abrev = ($i.Interfaz -replace '^GigabitEthernet', 'Gi' -replace '^FastEthernet', 'Fa' -replace '^Ethernet', 'Et')
        $i | Add-Member NoteProperty Tipo $(if ($abrevSwitch -contains $abrev -or $abrevSwitch -contains $i.Interfaz) { 'switch' }
                                            elseif ($i.Interfaz -match '^Vlan') { 'vlan' } else { 'ruteado' })
    }
    Close-Linea
    $interfaces | Format-Table Interfaz, Tipo, IP, Estado, Protocolo -AutoSize | Out-String | Write-Host
    $puertosSwitch = @($interfaces | Where-Object { $_.Tipo -eq 'switch' } | ForEach-Object { $_.Interfaz })
    $ruteados = @($interfaces | Where-Object { $_.Tipo -eq 'ruteado' -and $_.Interfaz -match 'Ethernet' })
    if ($puertosSwitch.Count -gt 0) {
        Write-Aviso "Este router tiene $($puertosSwitch.Count) puertos de switch: la IP de la LAN va en Vlan1 y el PC se conecta a cualquiera de ellos."
        $lanAuto = 'Vlan1'
        $wanAuto = if ($ruteados.Count -ge 1) { $ruteados[0].Interfaz } else { '' }
    } else {
        $lanAuto = if ($ruteados.Count -ge 1) { $ruteados[0].Interfaz } else { '' }
        $wanAuto = if ($ruteados.Count -ge 2) { $ruteados[1].Interfaz } else { '' }
    }
    $lan = if ($InterfazLan) { $InterfazLan } else { $lanAuto }
    $wan = if ($InterfazWan) { $InterfazWan } else { $wanAuto }
    Write-Host "Propuesta:  LAN (cable al PC) = $lan    WAN (cable al otro router) = $wan"
    $resp = Read-Respuesta '¿Es correcto? Enter = sí, n = escribirlas yo'
    if ($resp -match '^\s*n' -or -not $lan -or -not $wan) {
        $lan = (Read-Respuesta 'Interfaz LAN, la que va al PC (p. ej. GigabitEthernet0/0, o Vlan1 si el PC va a un puerto de switch)').Trim()
        $wan = (Read-Respuesta 'Interfaz WAN, la que va al otro router (p. ej. GigabitEthernet0/1)').Trim()
    }

    # Enlace serie: el lado DCE del cable pone el reloj.
    $dce = $false
    if ($wan -match '^(s|Serial)') {
        $ctl = Send-Comando "show controllers $wan"
        $dce = $ctl -match '\bDCE\b'
        if ($dce) { Write-Aviso 'La WAN es serie y este router es el lado DCE: se agrega "clock rate 64000".' }
    }

    # 3) Configurar.
    Write-Paso "Configurando el $($p.Nombre)"
    $errores = @()
    foreach ($cmd in (Get-Comandos $Router $lan $wan $dce $puertosSwitch)) {
        $r = Send-Comando $cmd
        if ($r -match '(?m)^%\s') {
            $errores += "$($cmd.Trim())  ->  $(($r -split "`r?`n" | Where-Object { $_ -match '^%\s' } | Select-Object -First 1).Trim())"
        }
    }
    if ($errores.Count -gt 0) {
        Write-Mal 'El router rechazó algunos comandos:'
        $errores | ForEach-Object { Write-Mal "  $_" }
        Write-Aviso 'Si dice "Invalid input" en "interface ...", el nombre de interfaz no existe: vuelve a correr el script y escríbelo a mano.'
    } else {
        Write-Ok 'El router aceptó todos los comandos.'
    }

    # 4) Guardar (opcional).
    if (-not $Guardar) { $Guardar = (Read-Respuesta '¿Guardar la configuración en el router (write memory)? s/N') -match '^\s*s' }
    if ($Guardar) {
        $r = Send-Comando 'write memory' 30000
        if ($r -match '\[OK\]') { Write-Ok 'Configuración guardada.' } else { Write-Aviso 'No se vio "[OK]" al guardar.' }
    }

    # 5) Verificar.
    Write-Paso 'Verificando'
    $out = Send-Comando 'show ip interface brief'
    foreach ($nombre in @($lan, $wan)) {
        $linea = ($out -split "`r?`n" | Where-Object { $_ -match ('^' + [regex]::Escape($nombre)) } | Select-Object -First 1)
        if (-not $linea) {
            # El usuario pudo escribir una abreviatura (g0/0): se busca por el número.
            $num = $nombre -replace '^[A-Za-z\-]+', ''
            $linea = ($out -split "`r?`n" | Where-Object { $_ -match ('^\S*' + [regex]::Escape($num) + '\s') } | Select-Object -First 1)
        }
        if ($linea -match '\s+up\s+up\s*$') { Write-Ok "$nombre está up/up." }
        elseif ($linea -match 'down\s+down\s*$' -and $nombre -match '^(?i)vlan') { Write-Aviso "$nombre está down/down: se enciende cuando conecten el PC a un puerto de switch." }
        elseif ($linea -match 'down\s+down\s*$') { Write-Aviso "$nombre está down/down: falta el cable, o el equipo del otro lado está apagado." }
        else { Write-Aviso "$nombre : $($linea -replace '\s+', ' ')" }
    }
    $rutas = Send-Comando 'show ip route'
    if ($rutas -match ('S\s+' + [regex]::Escape($p.RedRemota))) { Write-Ok "Ruta estática hacia $($p.RedRemota)/24 presente." }
    else { Write-Mal "No aparece la ruta estática hacia $($p.RedRemota)/24." }
    $ping = Send-Comando "ping $($p.Vecino)" 20000
    if ($ping -match 'Success rate is (\d+) percent') {
        if ([int]$matches[1] -gt 0) { Write-Ok "El otro router ($($p.Vecino)) responde al ping." }
        else { Write-Aviso "El otro router ($($p.Vecino)) no responde todavía: normal si aún no lo configuran o falta el cable entre routers." }
    }
    Close-Linea
    Write-Host ''
    Write-Host "Siguiente paso: configurar el PC conectado a la $lan con IP $($p.PcLocal) (tools\configurar-pc.bat)." -ForegroundColor Cyan
} finally {
    if ($script:Io) { $script:Io.Close() }
    if (-not $IoPrueba) {
        $dir = Join-Path $PSScriptRoot 'registros'
        New-Item -ItemType Directory -Force $dir | Out-Null
        $archivo = Join-Path $dir ("router{0}-{1:yyyyMMdd-HHmmss}.txt" -f $Router, (Get-Date))
        [IO.File]::WriteAllText($archivo, $Registro.ToString())
        Write-Host "Todo lo que respondió el router quedó en: $archivo" -ForegroundColor DarkCyan
    }
}
