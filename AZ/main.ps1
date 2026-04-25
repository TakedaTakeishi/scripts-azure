param(
    [switch]$SkipCreate,
    [switch]$SkipConnect,
    [switch]$RefreshIp,
    [switch]$MultiNet,
    [switch]$RebuildState
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\VMConfig.ps1"

Write-Host "=== Flujo Principal VM (AZ) ===" -ForegroundColor Cyan

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

if ($RebuildState) {
    Write-Host "Paso 0: Regenerar estado(s) JSON desde Azure" -ForegroundColor Cyan
    & "$PSScriptRoot\RegenerarEstadoVMs.ps1"

    if ($LASTEXITCODE -ne 0) {
        throw "AZ\\RegenerarEstadoVMs.ps1 termino con codigo $LASTEXITCODE"
    }
}

if (-not $SkipCreate) {
    if ($MultiNet) {
        Write-Host "Paso 1: Crear infraestructura multi-red (3 redes + 3 VMs)" -ForegroundColor Cyan
        & "$PSScriptRoot\CrearRedVirtual.ps1"
    }
    else {
        Write-Host "Paso 1: Crear infraestructura y VM" -ForegroundColor Cyan
        & "$PSScriptRoot\CrearVM.ps1"
    }

    if ($LASTEXITCODE -ne 0) {
        if ($MultiNet) {
            throw "AZ\\CrearRedVirtual.ps1 termino con codigo $LASTEXITCODE"
        }

        throw "AZ\\CrearVM.ps1 terminó con código $LASTEXITCODE"
    }
}
else {
    Write-Host "Paso 1 omitido (SkipCreate)." -ForegroundColor Yellow

    if ($MultiNet) {
        Write-Host "Paso 2 omitido: el modo MultiNet guarda estado durante la creacion." -ForegroundColor Yellow
        Write-Host "Archivo esperado: ..\\vm-connections-multired.json" -ForegroundColor DarkCyan
    }
    else {
        Write-Host "Paso 2: Guardar/actualizar estado de conexión" -ForegroundColor Cyan
        & "$PSScriptRoot\GuardarEstadoVM.ps1"

        if ($LASTEXITCODE -ne 0) {
            throw "AZ\\GuardarEstadoVM.ps1 terminó con código $LASTEXITCODE"
        }
    }
}

if ($AUTO_DELETE) {
    Write-Host "AUTO_DELETE=true: se omite conexión SSH porque el grupo puede ser eliminado." -ForegroundColor Yellow
}
elseif (-not $SkipConnect) {
    if ($MultiNet) {
        Write-Host "Paso 3: Conexion SSH (menu multi-VM)" -ForegroundColor Cyan
        & "$PSScriptRoot\ConectarVMMenu.ps1" -RefreshIp:$RefreshIp

        if ($LASTEXITCODE -ne 0) {
            throw "AZ\\ConectarVMMenu.ps1 termino con codigo $LASTEXITCODE"
        }
    }
    else {
        Write-Host "Paso 3: Conexión SSH" -ForegroundColor Cyan
        & "$PSScriptRoot\ConectarVM.ps1" -RefreshIp:$RefreshIp

        if ($LASTEXITCODE -ne 0) {
            throw "AZ\\ConectarVM.ps1 terminó con código $LASTEXITCODE"
        }
    }
}
else {
    Write-Host "Paso 3 omitido (SkipConnect)." -ForegroundColor Yellow
}

Write-Host "=== Flujo completado ===" -ForegroundColor Green

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
