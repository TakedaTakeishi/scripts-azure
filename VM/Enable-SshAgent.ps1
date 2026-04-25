param(
    [string]$KeyPath,
    [switch]$FailOnError
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\Upload-Lib.ps1"

function Stop-OrWarn {
    param([string]$Message)

    if ($FailOnError) {
        throw $Message
    }

    Write-Host "[SSH] $Message" -ForegroundColor Yellow
    return $false
}

if ([string]::IsNullOrWhiteSpace($KeyPath)) {
    . "$PSScriptRoot\..\VMConfig.ps1"
    $KeyPath = $KEY_PRIVATE_PATH
}

if (-not (Test-Path -LiteralPath $KeyPath)) {
    Stop-OrWarn -Message "No se encontro la llave privada en: $KeyPath" | Out-Null
    exit 1
}

try {
    Ensure-PrivateKeyPermissions -KeyPath $KeyPath
}
catch {
    Stop-OrWarn -Message $_.Exception.Message | Out-Null
    exit 1
}

$sshAdd = Get-Command ssh-add -ErrorAction SilentlyContinue
$sshKeygen = Get-Command ssh-keygen -ErrorAction SilentlyContinue
if (-not $sshAdd -or -not $sshKeygen) {
    Stop-OrWarn -Message "OpenSSH no esta disponible (ssh-add/ssh-keygen)." | Out-Null
    exit 1
}

$agentService = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
if (-not $agentService) {
    Stop-OrWarn -Message "El servicio ssh-agent no existe en este sistema." | Out-Null
    exit 1
}

if ($agentService.StartType -eq "Disabled") {
    try {
        Set-Service -Name "ssh-agent" -StartupType Manual
    }
    catch {
        Stop-OrWarn -Message "No se pudo cambiar ssh-agent a Manual. Ejecuta una terminal PowerShell como administrador para habilitarlo." | Out-Null
        exit 1
    }
}

if ($agentService.Status -ne "Running") {
    try {
        Start-Service -Name "ssh-agent"
    }
    catch {
        Stop-OrWarn -Message "No se pudo iniciar ssh-agent." | Out-Null
        exit 1
    }
}

$fingerprint = $null
$fpLine = (& ssh-keygen -lf $KeyPath 2>$null | Select-Object -First 1)
if (-not [string]::IsNullOrWhiteSpace($fpLine)) {
    $fpParts = $fpLine -split "\s+"
    if ($fpParts.Count -ge 2) {
        $fingerprint = $fpParts[1]
    }
}

$alreadyLoaded = $false
$listOutput = & ssh-add -l 2>$null
if ($LASTEXITCODE -eq 0) {
    $listText = ($listOutput | Out-String)
    if (-not [string]::IsNullOrWhiteSpace($fingerprint) -and $listText -match [regex]::Escape($fingerprint)) {
        $alreadyLoaded = $true
    }
}

if ($alreadyLoaded) {
    Write-Host "[SSH] Llave ya cargada en ssh-agent." -ForegroundColor DarkCyan
    exit 0
}

Write-Host "[SSH] Cargando llave en ssh-agent (pedira passphrase una sola vez)..." -ForegroundColor Cyan
& ssh-add $KeyPath
if ($LASTEXITCODE -ne 0) {
    Stop-OrWarn -Message "No se pudo cargar la llave en ssh-agent (codigo $LASTEXITCODE)." | Out-Null
    exit 1
}

Write-Host "[SSH] Llave cargada en memoria para esta sesion." -ForegroundColor Green
exit 0
