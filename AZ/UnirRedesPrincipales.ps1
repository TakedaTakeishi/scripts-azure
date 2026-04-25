param(
    [string]$ResourceGroup,
    [string[]]$VNetNames = @("Red01", "Red02", "Red03"),
    [string[]]$NsgNames = @("NSG01", "NSG02", "NSG03"),
    [switch]$SkipNsgIcmp
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\VMConfig.ps1"

if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    $ResourceGroup = $RG
}

if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
    throw "No hay grupo de recursos configurado. Define -ResourceGroup o revisa VMConfig.ps1."
}

if (-not $VNetNames -or $VNetNames.Count -lt 2) {
    throw "Debes indicar al menos 2 redes en -VNetNames para crear peering."
}

Write-Host "=== Uniendo redes principales (VNet Peering) ===" -ForegroundColor Cyan
Write-Host "Grupo de recursos objetivo: $ResourceGroup" -ForegroundColor DarkCyan

try {
    $accountName = az account show --query "name" --output tsv --only-show-errors
    $accountId = az account show --query "id" --output tsv --only-show-errors

    if ([string]::IsNullOrWhiteSpace($accountId)) {
        throw "No se pudo leer la suscripcion activa."
    }

    Write-Host "Suscripcion activa: $accountName ($accountId)" -ForegroundColor DarkCyan
}
catch {
    throw "Azure CLI no esta autenticado o no tiene contexto. Ejecuta: az login"
}

$exists = az group exists --name $ResourceGroup --output tsv --only-show-errors
if ([string]$exists -ne "true") {
    throw "El grupo de recursos '$ResourceGroup' no existe en la suscripcion activa."
}

$vnetMap = @{}
$activeVNetNames = @()
foreach ($vnetName in $VNetNames) {
    $vnetJson = az network vnet show --resource-group $ResourceGroup --name $vnetName --output json --only-show-errors 2>$null
    if ([string]::IsNullOrWhiteSpace($vnetJson)) {
        Write-Host "VNet no encontrada, se omite: $vnetName" -ForegroundColor Yellow
        continue
    }

    $vnetObj = $vnetJson | ConvertFrom-Json
    $prefixes = @($vnetObj.addressSpace.addressPrefixes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($prefixes.Count -eq 0) {
        Write-Host "No se pudieron obtener prefijos de '$vnetName'. Se omite." -ForegroundColor Yellow
        continue
    }

    $vnetMap[$vnetName] = [ordered]@{
        Id = [string]$vnetObj.id
        Prefixes = $prefixes
    }

    $activeVNetNames += $vnetName
}

$missingVnets = @($VNetNames | Where-Object { $activeVNetNames -notcontains $_ })
if ($missingVnets.Count -gt 0) {
    Write-Host ("VNets omitidas por no existir: {0}" -f ($missingVnets -join ", ")) -ForegroundColor Yellow
}

if ($activeVNetNames.Count -lt 2) {
    throw "No hay suficientes VNets existentes para peering. Encontradas: $($activeVNetNames -join ', ')"
}

for ($i = 0; $i -lt $activeVNetNames.Count; $i++) {
    for ($j = $i + 1; $j -lt $activeVNetNames.Count; $j++) {
        $a = $activeVNetNames[$i]
        $b = $activeVNetNames[$j]

        $abName = "peer-{0}-to-{1}" -f $a, $b
        $baName = "peer-{0}-to-{1}" -f $b, $a

        $abExists = az network vnet peering list --resource-group $ResourceGroup --vnet-name $a --query "[?name=='$abName'].name | [0]" --output tsv --only-show-errors 2>$null
        if ([string]::IsNullOrWhiteSpace($abExists)) {
            Write-Host "Creando peering: $abName" -ForegroundColor Cyan
            az network vnet peering create --resource-group $ResourceGroup --vnet-name $a --name $abName --remote-vnet $vnetMap[$b].Id --allow-vnet-access --only-show-errors --output none
        }
        else {
            Write-Host "Peering ya existe: $abName" -ForegroundColor DarkCyan
        }

        $baExists = az network vnet peering list --resource-group $ResourceGroup --vnet-name $b --query "[?name=='$baName'].name | [0]" --output tsv --only-show-errors 2>$null
        if ([string]::IsNullOrWhiteSpace($baExists)) {
            Write-Host "Creando peering: $baName" -ForegroundColor Cyan
            az network vnet peering create --resource-group $ResourceGroup --vnet-name $b --name $baName --remote-vnet $vnetMap[$a].Id --allow-vnet-access --only-show-errors --output none
        }
        else {
            Write-Host "Peering ya existe: $baName" -ForegroundColor DarkCyan
        }
    }
}

if (-not $SkipNsgIcmp) {
    Write-Host "Configurando reglas ICMP en NSG para habilitar ping entre redes..." -ForegroundColor Cyan

    foreach ($nsg in $NsgNames) {
        $nsgId = az network nsg list --resource-group $ResourceGroup --query "[?name=='$nsg'].id | [0]" --output tsv --only-show-errors 2>$null
        if ([string]::IsNullOrWhiteSpace($nsgId)) {
            Write-Host "NSG no encontrado, se omite: $nsg" -ForegroundColor Yellow
            continue
        }

        $priority = 1200
        foreach ($sourceVnet in $activeVNetNames) {
            $sourcePrefixes = $vnetMap[$sourceVnet].Prefixes
            foreach ($prefix in $sourcePrefixes) {
                $ruleName = "AllowIcmpFrom-{0}-{1}" -f $sourceVnet, ($priority - 1200 + 1)
                $ruleExists = az network nsg rule list --resource-group $ResourceGroup --nsg-name $nsg --query "[?name=='$ruleName'].name | [0]" --output tsv --only-show-errors 2>$null
                if ([string]::IsNullOrWhiteSpace($ruleExists)) {
                    az network nsg rule create --resource-group $ResourceGroup --nsg-name $nsg --name $ruleName --priority $priority --direction Inbound --access Allow --protocol Icmp --source-address-prefixes $prefix --destination-address-prefixes '*' --source-port-ranges '*' --destination-port-ranges '*' --only-show-errors --output none
                    Write-Host ("Regla ICMP creada en {0}: {1} ({2})" -f $nsg, $ruleName, $prefix) -ForegroundColor DarkCyan
                }
                else {
                    Write-Host ("Regla ICMP ya existe en {0}: {1}" -f $nsg, $ruleName) -ForegroundColor DarkCyan
                }
                $priority++
            }
        }
    }
}
else {
    Write-Host "Se omitio configuracion de NSG ICMP por -SkipNsgIcmp." -ForegroundColor Yellow
}

Write-Host "=== Redes unidas correctamente ===" -ForegroundColor Green
Write-Host "Nota: si ping falla aun, revisa firewall del SO dentro de cada VM (ej. ufw/iptables)." -ForegroundColor Yellow
