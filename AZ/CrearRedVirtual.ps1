. "$PSScriptRoot\..\VMConfig.ps1"

$ErrorActionPreference = "Stop"

Write-Host "--- Iniciando despliegue de 3 redes virtuales y 3 VMs ---" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $KEY_PUBLIC_PATH)) {
    throw "No se encontro la llave publica en: $KEY_PUBLIC_PATH"
}

$SSH_PUBLIC_KEY = (Get-Content -LiteralPath $KEY_PUBLIC_PATH -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($SSH_PUBLIC_KEY)) {
    throw "El archivo de llave publica esta vacio: $KEY_PUBLIC_PATH"
}

$IMAGE = $SO
if ($SO -notmatch ":") {
    switch ($SO) {
        "Ubuntu2404LTS" { $IMAGE = "Canonical:ubuntu-24_04-lts:server:latest" }
        "Ubuntu2204" { $IMAGE = "Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest" }
        default {
            throw "El valor de SO '$SO' no es URN valida ni alias soportado. Usa formato Publisher:Offer:Sku:Version."
        }
    }
}

$deployments = @(
    [ordered]@{
        Index = 1
        ResourceGroup = $RG
        Location = $LOC
        VNetName = "Red01"
        AddressPrefix = "10.0.0.0/16"
        SubnetName = "Principal01"
        SubnetPrefix = "10.0.0.0/24"
        VmName = "Maquina01"
    },
    [ordered]@{
        Index = 2
        ResourceGroup = $RG
        Location = $LOC
        VNetName = "Red02"
        AddressPrefix = "10.1.0.0/16"
        SubnetName = "Principal02"
        SubnetPrefix = "10.1.0.0/24"
        VmName = "Maquina02"
    },
    [ordered]@{
        Index = 3
        ResourceGroup = $RG
        Location = "eastus"
        VNetName = "Red03"
        AddressPrefix = "10.2.0.0/16"
        SubnetName = "Principal03"
        SubnetPrefix = "10.2.0.0/24"
        VmName = "Maquina03"
    }
)

Write-Host "1. Creando Grupo de Recursos compartido..." -ForegroundColor Cyan
az group create --name $RG --location $LOC --only-show-errors --output none

$multiStatePath = Join-Path -Path $PSScriptRoot -ChildPath "..\vm-connections-multired.json"

function Save-MultiVmState {
    param(
        [hashtable]$StateItem,
        [string]$Path
    )

    $existing = @()
    if (Test-Path -LiteralPath $Path) {
        try {
            $raw = Get-Content -LiteralPath $Path -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $parsed = $raw | ConvertFrom-Json
                $existing = if ($parsed -is [System.Array]) { @($parsed) } else { @($parsed) }
            }
        }
        catch {
            $existing = @()
        }
    }

    $filtered = @($existing | Where-Object {
        -not (($_.vmName -eq $StateItem.vmName) -and ($_.rg -eq $StateItem.rg))
    })

    $updated = @($filtered)
    $updated += [pscustomobject]$StateItem

    $updated | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Save-SingleVmState {
    param([hashtable]$StateItem)

    $singleState = [ordered]@{
        rg = $StateItem.rg
        vmName = $StateItem.vmName
        user = $StateItem.user
        so = $StateItem.so
        publicIp = $StateItem.publicIp
        keyPrivatePath = $StateItem.keyPrivatePath
        keyPublicPath = $StateItem.keyPublicPath
        updatedAt = $StateItem.updatedAt
    }

    $singleState | ConvertTo-Json | Set-Content -LiteralPath $STATE_PATH -Encoding UTF8
}

foreach ($d in $deployments) {
    $suffix = "{0:D2}" -f $d.Index
    $ipName = "IP$suffix"
    $nsgName = "NSG$suffix"
    $nicName = "NIC$suffix"

    Write-Host "2.$($d.Index) Creando Red Virtual y Subred: $($d.VNetName) ($($d.Location))..." -ForegroundColor Cyan
    az network vnet create --resource-group $d.ResourceGroup --name $d.VNetName --address-prefix $d.AddressPrefix --location $d.Location --subnet-name $d.SubnetName --subnet-prefix $d.SubnetPrefix --only-show-errors --output none

    Write-Host "3.$($d.Index) Creando IP Publica Estatica: $ipName..." -ForegroundColor Cyan
    az network public-ip create --resource-group $d.ResourceGroup --name $ipName --location $d.Location --sku Standard --allocation-method Static --only-show-errors --output none

    Write-Host "4.$($d.Index) Configurando NSG y regla SSH: $nsgName..." -ForegroundColor Cyan
    az network nsg create --resource-group $d.ResourceGroup --name $nsgName --location $d.Location --only-show-errors --output none
    az network nsg rule create --resource-group $d.ResourceGroup --nsg-name $nsgName --name AllowSSH --priority 1000 --protocol Tcp --destination-port-ranges 22 --access Allow --only-show-errors --output none

    Write-Host "5.$($d.Index) Creando NIC: $nicName..." -ForegroundColor Cyan
    az network nic create --resource-group $d.ResourceGroup --name $nicName --location $d.Location --vnet-name $d.VNetName --subnet $d.SubnetName --public-ip-address $ipName --network-security-group $nsgName --only-show-errors --output none

    Write-Host "6.$($d.Index) Creando VM: $($d.VmName)..." -ForegroundColor Cyan
    az vm create --resource-group $d.ResourceGroup --name $d.VmName --location $d.Location --zone 1 --nics $nicName --image $IMAGE --size $SIZE --admin-username $USER --ssh-key-values $SSH_PUBLIC_KEY --only-show-errors --output none

    if ($LASTEXITCODE -ne 0) {
        throw "La creacion de la VM '$($d.VmName)' fallo (codigo $LASTEXITCODE)."
    }

    $vmId = az vm show --resource-group $d.ResourceGroup --name $d.VmName --query "id" --output tsv --only-show-errors 2>$null
    if ([string]::IsNullOrWhiteSpace($vmId)) {
        throw "No se pudo confirmar la creacion de la VM '$($d.VmName)' en el grupo '$($d.ResourceGroup)'."
    }

    $publicIp = az vm show -d --resource-group $d.ResourceGroup --name $d.VmName --query "publicIps" --output tsv --only-show-errors 2>$null
    $stateItem = [ordered]@{
        rg = $d.ResourceGroup
        vmName = $d.VmName
        user = $USER
        so = $IMAGE
        vnet = $d.VNetName
        subnet = $d.SubnetName
        location = $d.Location
        publicIp = $publicIp
        keyPrivatePath = $KEY_PRIVATE_PATH
        keyPublicPath = $KEY_PUBLIC_PATH
        updatedAt = (Get-Date).ToString("s")
    }

    Save-MultiVmState -StateItem $stateItem -Path $multiStatePath
    Save-SingleVmState -StateItem $stateItem

    Write-Host "Estado actualizado: $($d.VmName) en vm-connections-multired.json y vm-connection.json" -ForegroundColor DarkCyan

    Write-Host "VM creada correctamente: $($d.VmName)" -ForegroundColor Green
}

Write-Host "Estado multi-VM guardado en: $multiStatePath" -ForegroundColor Green

Write-Host "--- Proceso Finalizado con Exito ---" -ForegroundColor Green

if ($AUTO_DELETE) {
    Write-Host "Borrando recursos..." -ForegroundColor Yellow
    az group delete --name $RG --yes --no-wait
}
