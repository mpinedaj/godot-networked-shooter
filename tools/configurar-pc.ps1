#Requires -Version 5.1
<#
.SYNOPSIS
  Prepara el puerto Ethernet de este PC para la prueba con los routers reales.

.DESCRIPTION
  Host    (LAN A): IP 192.168.1.10/24, router 192.168.1.1
  Cliente (LAN B): IP 192.168.2.10/24, router 192.168.2.1
  Además:
   - Agrega rutas hacia la otra LAN y hacia la WAN por ese router. No se usa
     "puerta de enlace predeterminada", así el internet del Wi-Fi no se pierde.
   - Abre el Firewall de Windows para el ping y para el juego (UDP 9999).
   - Prueba ping al router y al otro PC.
  Con -Restaurar deja el Ethernet en automático (DHCP) y borra las reglas.

.EXAMPLE
  .\configurar-pc.ps1 -Rol host
.EXAMPLE
  .\configurar-pc.ps1 -Restaurar
.EXAMPLE
  .\configurar-pc.ps1 -Rol cliente -SoloMostrar
#>
[CmdletBinding()]
param(
    [ValidateSet('host', 'cliente')] [string]$Rol,
    # Nombre del adaptador (p. ej. "Ethernet"). Si se omite, se elige el Ethernet físico.
    [string]$Adaptador,
    [switch]$Restaurar,
    [switch]$SoloMostrar
)

$ErrorActionPreference = 'Stop'

$Plan = @{
    host    = @{ IP = '192.168.1.10'; Router = '192.168.1.1'; OtraLan = '192.168.2.0/24'; OtroPc = '192.168.2.10' }
    cliente = @{ IP = '192.168.2.10'; Router = '192.168.2.1'; OtraLan = '192.168.1.0/24'; OtroPc = '192.168.1.10' }
}
$RedWan = '10.0.0.0/30'
$ReglaPing = 'LAN Shooter - ping'
$ReglaJuego = 'LAN Shooter - juego UDP 9999'

function Write-Paso([string]$t) { Write-Host "`n== $t" -ForegroundColor Cyan }
function Write-Ok([string]$t) { Write-Host "   OK  $t" -ForegroundColor Green }
function Write-Aviso([string]$t) { Write-Host "   !!  $t" -ForegroundColor Yellow }
function Write-Mal([string]$t) { Write-Host "   XX  $t" -ForegroundColor Red }

# Cambiar IPs y el firewall requiere administrador: se vuelve a abrir elevado.
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $esAdmin -and -not $SoloMostrar) {
    Write-Host 'Hace falta permiso de administrador: se abrirá otra ventana (acepta el aviso de Windows).'
    $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$PSCommandPath`"")
    if ($Rol) { $args2 += @('-Rol', $Rol) }
    if ($Adaptador) { $args2 += @('-Adaptador', "`"$Adaptador`"") }
    if ($Restaurar) { $args2 += '-Restaurar' }
    Start-Process powershell -Verb RunAs -ArgumentList $args2
    return
}

# ---------------- Elegir el adaptador Ethernet ----------------
function Get-AdaptadorEthernet {
    if ($Adaptador) { return Get-NetAdapter -Name $Adaptador }
    $cands = @(Get-NetAdapter -Physical | Where-Object { $_.NdisPhysicalMedium -eq 14 -or $_.MediaType -eq '802.3' } |
        Where-Object { $_.InterfaceDescription -notmatch 'Wi-?Fi|Wireless|Bluetooth|Virtual|VPN' })
    if ($cands.Count -eq 0) { throw 'No se encontró un adaptador Ethernet (de cable) en este PC.' }
    if ($cands.Count -eq 1) { return $cands[0] }
    Write-Host 'Hay varios adaptadores de cable:'
    $cands | ForEach-Object { Write-Host "   $($_.Name)  -  $($_.InterfaceDescription)  ($($_.Status))" }
    $n = Read-Host 'Escribe el nombre del que va al router'
    return Get-NetAdapter -Name $n.Trim()
}

$nic = Get-AdaptadorEthernet
Write-Host "Adaptador: $($nic.Name)  ($($nic.InterfaceDescription)), estado: $($nic.Status)"

# ---------------- Restaurar ----------------
if ($Restaurar) {
    if ($SoloMostrar) { Write-Host "Se pondría $($nic.Name) en DHCP y se borrarían las reglas '$ReglaPing' y '$ReglaJuego'."; return }
    Write-Paso 'Dejando el Ethernet como estaba (automático por DHCP)'
    foreach ($pref in @('192.168.1.0/24', '192.168.2.0/24', $RedWan)) {
        Get-NetRoute -InterfaceIndex $nic.ifIndex -DestinationPrefix $pref -ErrorAction SilentlyContinue |
            Where-Object { $_.NextHop -ne '0.0.0.0' } | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
    }
    Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceIndex $nic.ifIndex -Dhcp Enabled
    Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ResetServerAddresses
    Get-NetFirewallRule -DisplayName $ReglaPing, $ReglaJuego -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Write-Ok 'Listo: Ethernet en automático y reglas del firewall borradas.'
    return
}

# ---------------- Configurar ----------------
if (-not $Rol) {
    Write-Host 'host    = este PC crea la partida (va al Router A, LAN A).'
    Write-Host 'cliente = este PC se une a la partida (va al Router B, LAN B).'
    $Rol = (Read-Host '¿Este PC es host o cliente?').Trim().ToLower()
}
if (-not $Plan.ContainsKey($Rol)) { throw 'El rol debe ser host o cliente.' }
$p = $Plan[$Rol]

# Otro adaptador (casi siempre el Wi-Fi) con direcciones de nuestra red: choca.
$choques = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceIndex -ne $nic.ifIndex -and $_.IPAddress -match '^(192\.168\.1\.|192\.168\.2\.|10\.0\.0\.)' })
foreach ($c in $choques) {
    Write-Aviso "El adaptador '$($c.InterfaceAlias)' tiene la IP $($c.IPAddress), de la misma red que la prueba."
    Write-Aviso 'Desconecta el Wi-Fi (o ese adaptador) mientras hacen la prueba, o los paquetes pueden irse por ahí.'
}

if ($SoloMostrar) {
    Write-Host "`nSe aplicaría en '$($nic.Name)':" -ForegroundColor Cyan
    Write-Host "  IP $($p.IP) / 255.255.255.0 (sin DHCP)"
    Write-Host "  Ruta $($p.OtraLan) por $($p.Router)"
    Write-Host "  Ruta $RedWan por $($p.Router)"
    Write-Host "  Firewall: permitir ping entrante y UDP 9999 entrante"
    return
}

Write-Paso "Poniendo la IP $($p.IP)/24 en $($nic.Name)"
Set-NetIPInterface -InterfaceIndex $nic.ifIndex -Dhcp Disabled
Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
foreach ($pref in @($p.OtraLan, $RedWan)) {
    Get-NetRoute -DestinationPrefix $pref -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
}
New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $p.IP -PrefixLength 24 | Out-Null
Write-Ok "IP $($p.IP) con máscara 255.255.255.0."

Write-Paso "Rutas hacia la otra LAN y la WAN por el router $($p.Router)"
foreach ($pref in @($p.OtraLan, $RedWan)) {
    New-NetRoute -InterfaceIndex $nic.ifIndex -DestinationPrefix $pref -NextHop $p.Router -RouteMetric 5 | Out-Null
    Write-Ok "$pref  ->  $($p.Router)"
}

Write-Paso 'Firewall de Windows'
Get-NetFirewallRule -DisplayName $ReglaPing, $ReglaJuego -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName $ReglaPing -Direction Inbound -Protocol ICMPv4 -IcmpType 8 -Action Allow -Profile Any | Out-Null
New-NetFirewallRule -DisplayName $ReglaJuego -Direction Inbound -Protocol UDP -LocalPort 9999 -Action Allow -Profile Any | Out-Null
Write-Ok 'Permitido: ping entrante y el puerto UDP 9999 del juego.'

Write-Paso 'Probando'
if ($nic.Status -ne 'Up') {
    Write-Aviso 'El cable Ethernet no está conectado (o el router está apagado): conéctalo y vuelve a probar con:'
    Write-Host "     ping $($p.Router)   y   ping $($p.OtroPc)"
} else {
    Start-Sleep -Seconds 2   # Windows tarda un momento en activar la IP nueva.
    foreach ($dest in @($p.Router, $p.OtroPc)) {
        if (Test-Connection -ComputerName $dest -Count 2 -Quiet) { Write-Ok "$dest responde." }
        elseif ($dest -eq $p.Router) { Write-Mal "$dest (el router) no responde: revisa el cable y la IP de la interfaz del router." }
        else { Write-Aviso "$dest (el otro PC) no responde todavía: ¿ya está configurado? ¿están los dos routers y el cable entre ellos?" }
    }
}
Write-Host ''
if ($Rol -eq 'host') { Write-Host 'En el juego: "Crear partida (Host)". El cliente se une a 192.168.1.10, puerto 9999.' -ForegroundColor Cyan }
else { Write-Host 'En el juego: escribir 192.168.1.10 y puerto 9999, y "Unirse".' -ForegroundColor Cyan }
Write-Host 'Al terminar la práctica: tools\configurar-pc.bat y elegir "restaurar".' -ForegroundColor DarkCyan
