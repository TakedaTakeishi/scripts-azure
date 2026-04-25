param(
    [switch]$RefreshIp
)

. "$PSScriptRoot\..\VMConfig.ps1"
$ErrorActionPreference = "Stop"

function Get-MultiVmStates {
    $multiStatePath = Join-Path -Path $PSScriptRoot -ChildPath "..\vm-connections-multired.json"
    if (-not (Test-Path -LiteralPath $multiStatePath)) {
        return @()
    }

    try {
        $raw = Get-Content -LiteralPath $multiStatePath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return @()
        }

        $parsed = $raw | ConvertFrom-Json
        if ($parsed -is [System.Array]) {
            return $parsed
        }

        return @($parsed)
    }
    catch {
        Write-Host "No se pudo leer el archivo multi-VM: $multiStatePath" -ForegroundColor Yellow
        return @()
    }
}

$options = @()
$seen = @{}

foreach ($item in (Get-MultiVmStates)) {
    $vmName = [string]$item.vmName
    if ([string]::IsNullOrWhiteSpace($vmName)) {
        continue
    }

    $rg = [string]$item.rg
    $key = "$rg|$vmName"
    if ($seen.ContainsKey($key)) {
        continue
    }

    $seen[$key] = $true
    $options += [pscustomobject]@{
        Source = "multi"
        VmName = $vmName
        ResourceGroup = $rg
        Location = [string]$item.location
        PublicIp = [string]$item.publicIp
        User = [string]$item.user
    }
}

if (Test-Path -LiteralPath $STATE_PATH) {
    try {
        $single = Get-Content -LiteralPath $STATE_PATH -Raw | ConvertFrom-Json
        if ($single -and -not [string]::IsNullOrWhiteSpace([string]$single.vmName)) {
            $singleRg = [string]$single.rg
            $singleVm = [string]$single.vmName
            $singleKey = "$singleRg|$singleVm"

            if (-not $seen.ContainsKey($singleKey)) {
                $options += [pscustomobject]@{
                    Source = "single"
                    VmName = $singleVm
                    ResourceGroup = $singleRg
                    Location = ""
                    PublicIp = [string]$single.publicIp
                    User = [string]$single.user
                }
            }
        }
    }
    catch {
        Write-Host "No se pudo leer el estado single VM: $STATE_PATH" -ForegroundColor Yellow
    }
}

if ($options.Count -eq 0) {
    throw "No hay VMs disponibles en estado local. Ejecuta primero AZ\\CrearVM.ps1 o AZ\\CrearRedVirtual.ps1."
}

Write-Host "" 
Write-Host "=== Menu de Conexion SSH ===" -ForegroundColor Cyan
for ($i = 0; $i -lt $options.Count; $i++) {
    $o = $options[$i]
    $locationText = if ([string]::IsNullOrWhiteSpace($o.Location)) { "N/A" } else { $o.Location }
    $ipText = if ([string]::IsNullOrWhiteSpace($o.PublicIp)) { "(sin IP en estado)" } else { $o.PublicIp }

    Write-Host ("{0}. {1} | RG: {2} | Region: {3} | IP: {4}" -f ($i + 1), $o.VmName, $o.ResourceGroup, $locationText, $ipText)
}
Write-Host "Q. Salir"

$choice = Read-Host "Selecciona una VM por numero"
if ($choice -match "^[Qq]$") {
    Write-Host "Conexion cancelada por el usuario." -ForegroundColor Yellow
    return
}

$selectedIndex = 0
if (-not [int]::TryParse($choice, [ref]$selectedIndex)) {
    throw "Entrada invalida: '$choice'"
}

if ($selectedIndex -lt 1 -or $selectedIndex -gt $options.Count) {
    throw "Opcion fuera de rango: $selectedIndex"
}

$target = $options[$selectedIndex - 1]
$connectUser = if ([string]::IsNullOrWhiteSpace($target.User)) { $USER } else { $target.User }

& "$PSScriptRoot\ConectarVM.ps1" -RefreshIp:$RefreshIp -VmName $target.VmName -ResourceGroup $target.ResourceGroup -PublicIp $target.PublicIp -UserName $connectUser
if ($LASTEXITCODE -ne 0) {
    throw "AZ\\ConectarVM.ps1 termino con codigo $LASTEXITCODE"
}
