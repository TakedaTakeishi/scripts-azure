param(
    [switch]$RefreshIp,
    [int[]]$SelectedIndexes,
    [ValidateSet("upload", "upload-run")]
    [string]$ExecutionMode = "upload",
    [bool]$UseSshAgent = $true
)

. "$PSScriptRoot\Upload-Lib.ps1"
$ErrorActionPreference = "Stop"

$defaultRefreshIp = $RefreshIp
$useSshAgentForTasks = $UseSshAgent

$enableAgentScript = Join-Path -Path $PSScriptRoot -ChildPath "Enable-SshAgent.ps1"
if ($UseSshAgent -and (Test-Path -LiteralPath $enableAgentScript)) {
    & $enableAgentScript
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[SSH] Continuando sin ssh-agent: se pedira passphrase en multiples conexiones." -ForegroundColor Yellow
        $useSshAgentForTasks = $false
    }
}

function Read-Selection {
    param([int]$Max)

    $raw = Read-Host "Selecciona tarea(s) por numero (ej: 1,3) o Q para salir"
    if ($raw -match "^[Qq]$") {
        return $null
    }

    $items = $raw.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    if (-not $items) {
        throw "No capturaste ninguna opcion."
    }

    $indexes = @()
    foreach ($item in $items) {
        $n = 0
        if (-not [int]::TryParse($item, [ref]$n)) {
            throw "Entrada invalida: $item"
        }

        if ($n -lt 1 -or $n -gt $Max) {
            throw "Opcion fuera de rango: $n"
        }

        $indexes += $n
    }

    return $indexes | Select-Object -Unique
}

function Invoke-SelectedConfigs {
    param(
        [array]$Configs,
        [int[]]$Indexes,
        [bool]$RunPost,
        [bool]$RefreshIp,
        [bool]$UseSshAgent
    )

    foreach ($idx in $Indexes) {
        if ($idx -lt 1 -or $idx -gt $Configs.Count) {
            throw "Opcion fuera de rango: $idx"
        }

        $path = $Configs[$idx - 1].FullName
        Invoke-UploadTask -ConfigPath $path -RunPostCommands:$RunPost -RefreshIp:$RefreshIp -UseSshAgent:$UseSshAgent
        $RefreshIp = $false
    }
}

$runPostDefault = $ExecutionMode -eq "upload-run"

if ($SelectedIndexes -and $SelectedIndexes.Count -gt 0) {
    $configs = Get-UploadTaskConfigs
    if (-not $configs -or $configs.Count -eq 0) {
        throw "No hay configs en $PSScriptRoot\Enviar (*.json)."
    }

    Invoke-SelectedConfigs -Configs $configs -Indexes $SelectedIndexes -RunPost $runPostDefault -RefreshIp $defaultRefreshIp -UseSshAgent $useSshAgentForTasks
    Write-Host "Menu finalizado." -ForegroundColor Green
    return
}

while ($true) {
    $configs = Get-UploadTaskConfigs
    if (-not $configs -or $configs.Count -eq 0) {
        throw "No hay configs en $PSScriptRoot\Enviar (*.json)."
    }

    Write-Host ""
    Write-Host "=== Menu de Envios a VM ===" -ForegroundColor Cyan
    for ($i = 0; $i -lt $configs.Count; $i++) {
        $cfg = Read-TaskConfig -ConfigPath $configs[$i].FullName
        Write-Host ("{0}. {1}" -f ($i + 1), $cfg.taskName)
    }
    Write-Host "Q. Salir"

    try {
        $selected = Read-Selection -Max $configs.Count
        if ($null -eq $selected) {
            break
        }

        $mode = Read-Host "Modo: 1) Solo subir  2) Subir y ejecutar"
        $runPost = $mode -eq "2"

        $refreshChoice = Read-Host "Refrescar IP desde Azure antes de comenzar? (s/n)"
        $refreshIp = $defaultRefreshIp -or ($refreshChoice -match "^[sS]$")

        Invoke-SelectedConfigs -Configs $configs -Indexes $selected -RunPost $runPost -RefreshIp $refreshIp -UseSshAgent $useSshAgentForTasks

        $defaultRefreshIp = $false
    }
    catch {
        Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }

    $again = Read-Host "Quieres ejecutar otra tarea? (s/n)"
    if ($again -notmatch "^[sS]$") {
        break
    }
}

Write-Host "Menu finalizado." -ForegroundColor Green
