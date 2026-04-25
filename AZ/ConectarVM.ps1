param(
    [switch]$RefreshIp,
    [int]$SshReadyTimeoutSeconds = 180,
    [string]$PublicIp,
    [string]$VmName,
    [string]$ResourceGroup,
    [string]$UserName
)

. "$PSScriptRoot\..\VMConfig.ps1"
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $KEY_PRIVATE_PATH)) {
    throw "No se encontró la llave privada en: $KEY_PRIVATE_PATH"
}

$resolvedVmName = if ([string]::IsNullOrWhiteSpace($VmName)) { $VM_NAME } else { $VmName }
$resolvedResourceGroup = if ([string]::IsNullOrWhiteSpace($ResourceGroup)) { $RG } else { $ResourceGroup }
$sshUser = if ([string]::IsNullOrWhiteSpace($UserName)) { $USER } else { $UserName }

$publicIp = $PublicIp

if ((-not $RefreshIp) -and [string]::IsNullOrWhiteSpace($publicIp) -and (Test-Path -LiteralPath $STATE_PATH)) {
    try {
        $state = Get-Content -LiteralPath $STATE_PATH -Raw | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace($VmName) -or ($state.vmName -eq $resolvedVmName)) {
            $publicIp = $state.publicIp
        }
    }
    catch {
        Write-Host "No se pudo leer el estado en $STATE_PATH. Se consultará Azure." -ForegroundColor Yellow
    }
}

if ([string]::IsNullOrWhiteSpace($publicIp)) {
    $multiStatePath = Join-Path -Path $PSScriptRoot -ChildPath "..\vm-connections-multired.json"
    if (Test-Path -LiteralPath $multiStatePath) {
        try {
            $multiState = Get-Content -LiteralPath $multiStatePath -Raw | ConvertFrom-Json
            $multiStateItems = if ($multiState -is [System.Array]) { $multiState } else { @($multiState) }

            $match = $multiStateItems | Where-Object {
                ($_.vmName -eq $resolvedVmName) -and
                ([string]::IsNullOrWhiteSpace($resolvedResourceGroup) -or [string]::IsNullOrWhiteSpace([string]$_.rg) -or ($_.rg -eq $resolvedResourceGroup))
            } | Select-Object -First 1

            if ($match) {
                $publicIp = [string]$match.publicIp
                if ([string]::IsNullOrWhiteSpace($UserName) -and -not [string]::IsNullOrWhiteSpace([string]$match.user)) {
                    $sshUser = [string]$match.user
                }
            }
        }
        catch {
            Write-Host "No se pudo leer estado multi-VM en $multiStatePath. Se consultará Azure." -ForegroundColor Yellow
        }
    }
}

if ($RefreshIp -or [string]::IsNullOrWhiteSpace($publicIp)) {
    if (-not [string]::IsNullOrWhiteSpace($resolvedResourceGroup) -and -not [string]::IsNullOrWhiteSpace($resolvedVmName)) {
        try {
            $publicIp = az vm show -d --resource-group $resolvedResourceGroup --name $resolvedVmName --query "publicIps" --output tsv 2>$null
        }
        catch {
            $publicIp = $null
        }
    }
}

if ([string]::IsNullOrWhiteSpace($publicIp) -and [string]::IsNullOrWhiteSpace($VmName)) {
    & "$PSScriptRoot\GuardarEstadoVM.ps1"
    $state = Get-Content -LiteralPath $STATE_PATH -Raw | ConvertFrom-Json
    $publicIp = $state.publicIp
}

Write-Host "Verificando disponibilidad SSH en $publicIp:22..." -ForegroundColor Cyan
$deadline = (Get-Date).AddSeconds($SshReadyTimeoutSeconds)
$sshReady = $false

while ((Get-Date) -lt $deadline) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $async = $tcp.BeginConnect($publicIp, 22, $null, $null)
        $connected = $async.AsyncWaitHandle.WaitOne(3000, $false)

        if ($connected -and $tcp.Connected) {
            $tcp.EndConnect($async)
            $sshReady = $true
            $tcp.Close()
            break
        }

        $tcp.Close()
    }
    catch {
        # Reintenta hasta cumplir timeout.
    }

    Start-Sleep -Seconds 5
}

if (-not $sshReady) {
    throw "SSH no respondió en $publicIp:22 dentro de $SshReadyTimeoutSeconds segundos. Revisa NSG, estado de la VM o vuelve a intentar con -RefreshIp."
}

Write-Host "Conectando a $sshUser@$publicIp" -ForegroundColor Green
ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$SSH_KNOWN_HOSTS_PATH" -o LogLevel=ERROR -i $KEY_PRIVATE_PATH "$sshUser@$publicIp"

if ($LASTEXITCODE -ne 0) {
    throw "Fallo la conexión SSH con código $LASTEXITCODE"
}
