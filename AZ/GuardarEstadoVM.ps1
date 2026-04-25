param(
	[string]$ResourceGroup,
	[string]$VmName
)

. "$PSScriptRoot\..\VMConfig.ps1"
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
	$ResourceGroup = $RG
}

if ([string]::IsNullOrWhiteSpace($VmName)) {
	$VmName = $VM_NAME
}

if ([string]::IsNullOrWhiteSpace($ResourceGroup) -or [string]::IsNullOrWhiteSpace($VmName)) {
	throw "Faltan variables de configuración (RG/VM_NAME). Revisa VMConfig.ps1"
}

$rgExists = az group exists --name $ResourceGroup
if ($rgExists -ne "true") {
	throw "El grupo '$ResourceGroup' no existe en la suscripción actual. Si la VM se creó antes, pudo haberse borrado al final del script o estás en otro contexto de Azure."
}

Write-Host "7. Consultando IP pública de la VM..." -ForegroundColor Cyan
$PUBLIC_IP = $null

try {
	$PUBLIC_IP = az vm show -d --resource-group $ResourceGroup --name $VmName --query "publicIps" --output tsv 2>$null
}
catch {
	$PUBLIC_IP = $null
}

if ([string]::IsNullOrWhiteSpace($PUBLIC_IP) -and -not [string]::IsNullOrWhiteSpace($IP_NAME)) {
	try {
		$PUBLIC_IP = az network public-ip show --resource-group $ResourceGroup --name $IP_NAME --query "ipAddress" --output tsv 2>$null
	}
	catch {
		$PUBLIC_IP = $null
	}
}

if ([string]::IsNullOrWhiteSpace($PUBLIC_IP)) {
	$availableVms = $null

	try {
		$availableVms = az vm list --query "[].join('|',[resourceGroup,name])" --output tsv 2>$null
	}
	catch {
		$availableVms = $null
	}

	if ([string]::IsNullOrWhiteSpace($availableVms)) {
		throw "No se pudo obtener la IP. No hay VMs visibles en la suscripción actual o no existe $VmName en $ResourceGroup."
	}

	throw "No se pudo obtener la IP para VM '$VmName' en RG '$ResourceGroup'. VMs disponibles (RG|Nombre): $availableVms"
}

$state = [ordered]@{
	rg = $ResourceGroup
	vmName = $VmName
	user = $USER
	so = $SO
	publicIp = $PUBLIC_IP
	keyPrivatePath = $KEY_PRIVATE_PATH
	keyPublicPath = $KEY_PUBLIC_PATH
	updatedAt = (Get-Date).ToString("s")
}

$state | ConvertTo-Json | Set-Content -LiteralPath $STATE_PATH -Encoding UTF8

Write-Host "IP guardada en: $STATE_PATH" -ForegroundColor Green
Write-Host "IP actual: $PUBLIC_IP" -ForegroundColor Green
Write-Host "Estado VM guardado:" -ForegroundColor DarkCyan
$state.GetEnumerator() | ForEach-Object {
	Write-Host ("  {0}: {1}" -f $_.Key, $_.Value) -ForegroundColor Gray
}
Write-Host "Conecta con: .\AZ\ConectarVM.ps1" -ForegroundColor Cyan
