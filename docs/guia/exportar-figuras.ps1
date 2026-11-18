# Exporta las figuras de la guía a PNG con draw.io de escritorio.
#
# Uso:
#   .\docs\guia\exportar-figuras.ps1 -Drawio "C:\ruta\a\draw.io.exe"
#
# draw.io recibe rutas relativas porque su línea de comandos no maneja bien las
# rutas con espacios (la carpeta del proyecto puede tenerlos).

param(
    [Parameter(Mandatory = $true)]
    [string]$Drawio
)

$raiz = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Push-Location $raiz
try {
    $pares = @(
        @("docs\diagramas\red\03-montaje-sustentacion.drawio", "docs\guia\figuras\03-montaje.png"),
        @("docs\diagramas\red\04-topologia-logica-sustentacion.drawio", "docs\guia\figuras\04-topologia-logica.png"),
        @("docs\diagramas\estados\02-decision-configuracion.drawio", "docs\guia\figuras\05-decision-configuracion.png")
    )

    New-Item -ItemType Directory -Force -Path "docs\guia\figuras" | Out-Null

    foreach ($par in $pares) {
        $entrada, $salida = $par
        $argumentos = @(
            "--no-sandbox", "--disable-gpu",
            "--export", "--format", "png", "--scale", "2",
            "--output", $salida, $entrada
        )
        $proceso = Start-Process -FilePath $Drawio -ArgumentList $argumentos -Wait -PassThru
        if (Test-Path $salida) {
            Write-Host "OK  $salida"
        }
        else {
            Write-Warning "No se generó $salida (código $($proceso.ExitCode))"
        }
    }
}
finally {
    Pop-Location
}
