# Despliega el codigo MQL5 del repositorio en la carpeta MQL5 del terminal MetaTrader 5.
#
# El repositorio es la fuente de verdad. La carpeta del terminal es un destino
# desechable: nunca se edita codigo directamente dentro del terminal.
#
# Cada subcarpeta 4points\ del destino se borra y se vuelve a copiar, de modo que
# los ficheros eliminados en el repositorio no queden colgando en el terminal.
# Solo se toca 4points\, nunca el resto del contenido del terminal.
#
# Configuracion: define MT5_TERMINAL_DIR como variable de entorno o en deploy.config
# (copia deploy.config.example). Debe apuntar a la carpeta que CONTIENE MQL5\, por
# ejemplo:  C:\Users\<user>\AppData\Roaming\MetaQuotes\Terminal\<terminal-id>
#
# Uso:  .\deploy.ps1 [-DryRun]

[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Configuracion: deploy.config tiene prioridad sobre la variable de entorno
$TerminalDir = $env:MT5_TERMINAL_DIR
$ConfigFile = Join-Path $RepoDir 'deploy.config'

if (Test-Path $ConfigFile) {
    Get-Content $ConfigFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#') -and $line -match '^\s*MT5_TERMINAL_DIR\s*=\s*(.+)$') {
            $TerminalDir = $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
}

if ([string]::IsNullOrWhiteSpace($TerminalDir)) {
    Write-Error "MT5_TERMINAL_DIR no esta definido. Copia deploy.config.example a deploy.config y ajusta la ruta."
}

$Target = Join-Path $TerminalDir 'MQL5'

if (-not (Test-Path $Target)) {
    Write-Error "No existe la carpeta $Target. Comprueba que MT5_TERMINAL_DIR apunta a la carpeta que contiene MQL5\."
}

Write-Host "Origen : $(Join-Path $RepoDir 'MQL5')"
Write-Host "Destino: $Target"
Write-Host ""

$total = 0
foreach ($sub in @('Include', 'Indicators', 'Experts', 'Scripts')) {
    $src = Join-Path $RepoDir "MQL5\$sub\4points"
    if (-not (Test-Path $src)) { continue }

    $dst = Join-Path $Target $sub
    $count = (Get-ChildItem -Path $src -Recurse -File | Where-Object { $_.Name -ne '.gitkeep' }).Count
    Write-Host ("  {0}\4points  ({1} ficheros)" -f $sub, $count)

    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
        $leaf = Join-Path $dst '4points'
        if (Test-Path $leaf) { Remove-Item -Path $leaf -Recurse -Force }
        Copy-Item -Path $src -Destination $dst -Recurse -Force
    }
    $total += $count
}

Write-Host ""
if ($DryRun) {
    Write-Host "Dry run: no se ha copiado nada. Total que se copiaria: $total ficheros."
} else {
    Write-Host "Deploy completado: $total ficheros. Recompila desde MetaEditor."
}
