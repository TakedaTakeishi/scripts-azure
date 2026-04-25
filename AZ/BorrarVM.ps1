param(
    [string]$ResourceGroup,
    [switch]$Force,
    [switch]$Wait,
    [switch]$ClearState
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\VMConfig.ps1"

if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    $ResourceGroup = $RG
}

if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    throw "No hay grupo de recursos configurado. Define -ResourceGroup o revisa VMConfig.ps1."
}

Write-Host "=== Eliminación de recursos Azure ===" -ForegroundColor Cyan
Write-Host "Grupo de recursos objetivo: $ResourceGroup" -ForegroundColor DarkCyan

try {
    $accountName = az account show --query "name" --output tsv --only-show-errors
    $accountId = az account show --query "id" --output tsv --only-show-errors

    if ([string]::IsNullOrWhiteSpace($accountId)) {
        throw "No se pudo leer la suscripción activa."
    }

    Write-Host "Suscripción activa: $accountName ($accountId)" -ForegroundColor DarkCyan
}
catch {
    throw "Azure CLI no está autenticado o no tiene contexto. Ejecuta: az login"
}

$exists = az group exists --name $ResourceGroup --output tsv --only-show-errors
if ($LASTEXITCODE -ne 0) {
    throw "No se pudo validar la existencia del grupo $ResourceGroup (código $LASTEXITCODE)."
}

if ([string]$exists -ne "true") {
    Write-Host "El grupo de recursos no existe: $ResourceGroup" -ForegroundColor Yellow
    exit 0
}

if (-not $Force) {
    $confirm = Read-Host "Confirma eliminación del grupo '$ResourceGroup' (escribe SI para continuar)"
    if ($confirm -ne "SI") {
        Write-Host "Operación cancelada por el usuario." -ForegroundColor Yellow
        exit 0
    }
}

if ($Wait) {
    Write-Host "Iniciando eliminación y esperando finalización..." -ForegroundColor Yellow
    az group delete --name $ResourceGroup --yes --no-wait false --only-show-errors
}
else {
    Write-Host "Iniciando eliminación en segundo plano..." -ForegroundColor Yellow
    az group delete --name $ResourceGroup --yes --no-wait --only-show-errors
}

if ($LASTEXITCODE -ne 0) {
    throw "Falló la eliminación del grupo $ResourceGroup (código $LASTEXITCODE)."
}

if ($ClearState -and (Test-Path -LiteralPath $STATE_PATH)) {
    Remove-Item -LiteralPath $STATE_PATH -Force
    Write-Host "Se eliminó el archivo de estado: $STATE_PATH" -ForegroundColor DarkCyan
}

if ($Wait) {
    Write-Host "Eliminación finalizada correctamente." -ForegroundColor Green
}
else {
    Write-Host "Eliminación lanzada. Puedes revisar estado con: az group show --name $ResourceGroup" -ForegroundColor Green
}
