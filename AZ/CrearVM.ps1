. "$PSScriptRoot\..\VMConfig.ps1"

Write-Host "--- Iniciando despliegue en Azure ---" -ForegroundColor Cyan

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $KEY_PUBLIC_PATH)) {
	throw "No se encontró la llave pública en: $KEY_PUBLIC_PATH"
}

$SSH_PUBLIC_KEY = (Get-Content -LiteralPath $KEY_PUBLIC_PATH -Raw).Trim()

if ([string]::IsNullOrWhiteSpace($SSH_PUBLIC_KEY)) {
	throw "El archivo de llave pública está vacío: $KEY_PUBLIC_PATH"
}

$IMAGE = $SO
if ($SO -notmatch ":") {
	switch ($SO) {
		"Ubuntu2404LTS" { $IMAGE = "Canonical:ubuntu-24_04-lts:server:latest" }
		"Ubuntu2204" { $IMAGE = "Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest" }
		default {
			throw "El valor de SO '$SO' no es URN válida ni alias soportado. Usa formato Publisher:Offer:Sku:Version."
		}
	}
}

Write-Host "1. Creando Grupo de Recursos..."
az group create --name $RG --location $LOC

Write-Host "2. Creando Red Virtual y Subred..."
az network vnet create --resource-group $RG --name $VNET --address-prefix 10.0.0.0/16 --location $LOC --subnet-name $SUBNET --subnet-prefix 10.0.0.0/24

Write-Host "3. Creando IP Pública Estática..."
az network public-ip create --resource-group $RG --name $IP_NAME --location $LOC --sku Standard --allocation-method Static

Write-Host "4. Configurando Grupo de Seguridad (NSG) y Reglas..."
az network nsg create --resource-group $RG --name $NSG --location $LOC
az network nsg rule create --resource-group $RG --nsg-name $NSG --name AllowSSH --priority 1000 --protocol Tcp --destination-port-ranges 22 --access Allow
az network nsg rule create --resource-group $RG --nsg-name $NSG --name AllowHTTP --priority 1010 --protocol Tcp --destination-port-ranges 80 --access Allow
az network nsg rule create --resource-group $RG --nsg-name $NSG --name AllowHTTPS --priority 1020 --protocol Tcp --destination-port-ranges 443 --access Allow

Write-Host "5. Creando Interfaz de Red (NIC)..."
az network nic create --resource-group $RG --name $NIC --location $LOC --vnet-name $VNET --subnet $SUBNET --public-ip-address $IP_NAME --network-security-group $NSG

Write-Host "6. Creando Máquina Virtual (esto puede tardar unos minutos)..."
az vm create --resource-group $RG --name $VM_NAME --location $LOC --zone 1 --nics $NIC --image $IMAGE --size $SIZE --admin-username $USER --ssh-key-values $SSH_PUBLIC_KEY --only-show-errors --output none

if ($LASTEXITCODE -ne 0) {
	throw "La creación de la VM falló (az vm create, código $LASTEXITCODE)."
}

$vmId = az vm show --resource-group $RG --name $VM_NAME --query "id" --output tsv --only-show-errors 2>$null
if ([string]::IsNullOrWhiteSpace($vmId)) {
	throw "No se pudo confirmar la creación de la VM $VM_NAME en el grupo $RG."
}

Write-Host "VM creada correctamente: $VM_NAME" -ForegroundColor Green

& "$PSScriptRoot\GuardarEstadoVM.ps1"

Write-Host "--- Proceso Finalizado con Éxito ---" -ForegroundColor Green

if ($AUTO_DELETE) {
	Write-Host "Borrando recursos..." -ForegroundColor Yellow
	az group delete --name $RG --yes --no-wait
}
