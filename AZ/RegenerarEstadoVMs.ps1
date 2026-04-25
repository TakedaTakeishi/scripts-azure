param(
    [string]$ResourceGroup,
    [string[]]$VmNames,
    [switch]$IncludeWithoutPublicIp
)

. "$PSScriptRoot\..\VMConfig.ps1"
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    $ResourceGroup = $RG
}

if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    throw "No se definio ResourceGroup. Revisa VMConfig.ps1 o pasa -ResourceGroup."
}

Write-Host "--- Regenerando estados de VMs desde Azure ---" -ForegroundColor Cyan
Write-Host "Grupo de recursos: $ResourceGroup" -ForegroundColor DarkCyan

$rgExists = az group exists --name $ResourceGroup
if ($rgExists -ne "true") {
    throw "El grupo '$ResourceGroup' no existe en la suscripcion activa."
}

if (-not $VmNames -or $VmNames.Count -eq 0) {
    $VmNames = @(az vm list --resource-group $ResourceGroup --query "[].name" --output tsv --only-show-errors)
}

$VmNames = @($VmNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
if ($VmNames.Count -eq 0) {
    throw "No se encontraron VMs en el grupo '$ResourceGroup'."
}

$items = @()

foreach ($vm in $VmNames) {
    Write-Host "Consultando VM: $vm" -ForegroundColor Cyan

    $vmInfo = $null
    try {
        $vmInfo = az vm show -d --resource-group $ResourceGroup --name $vm --query "{vmName:name,rg:resourceGroup,location:location,publicIp:publicIps}" --output json --only-show-errors | ConvertFrom-Json
    }
    catch {
        Write-Host "No se pudo consultar '$vm'. Se omite." -ForegroundColor Yellow
        continue
    }

    if ($null -eq $vmInfo) {
        continue
    }

    $publicIp = [string]$vmInfo.publicIp
    if ([string]::IsNullOrWhiteSpace($publicIp) -and -not $IncludeWithoutPublicIp) {
        Write-Host "VM '$vm' sin IP publica. Se omite (usa -IncludeWithoutPublicIp para incluirla)." -ForegroundColor Yellow
        continue
    }

    $stateItem = [ordered]@{
        rg = [string]$vmInfo.rg
        vmName = [string]$vmInfo.vmName
        user = $USER
        so = $SO
        vnet = ""
        subnet = ""
        location = [string]$vmInfo.location
        publicIp = $publicIp
        keyPrivatePath = $KEY_PRIVATE_PATH
        keyPublicPath = $KEY_PUBLIC_PATH
        updatedAt = (Get-Date).ToString("s")
    }

    $items += [pscustomobject]$stateItem
}

if ($items.Count -eq 0) {
    throw "No se pudo construir estado util: ninguna VM con datos validos."
}

$multiStatePath = Join-Path -Path $PSScriptRoot -ChildPath "..\vm-connections-multired.json"
$items | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $multiStatePath -Encoding UTF8
Write-Host "Estado multi-VM regenerado: $multiStatePath" -ForegroundColor Green

$primary = $items | Where-Object { $_.vmName -eq $VM_NAME } | Select-Object -First 1
if ($null -eq $primary) {
    $primary = $items | Select-Object -First 1
}

$singleState = [ordered]@{
    rg = $primary.rg
    vmName = $primary.vmName
    user = $primary.user
    so = $primary.so
    publicIp = $primary.publicIp
    keyPrivatePath = $primary.keyPrivatePath
    keyPublicPath = $primary.keyPublicPath
    updatedAt = $primary.updatedAt
}

$singleState | ConvertTo-Json | Set-Content -LiteralPath $STATE_PATH -Encoding UTF8
Write-Host "Estado single-VM regenerado: $STATE_PATH" -ForegroundColor Green
Write-Host "VMs registradas: $($items.Count)" -ForegroundColor Green
