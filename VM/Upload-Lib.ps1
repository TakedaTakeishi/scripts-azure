$script:VmRoot = $PSScriptRoot
$script:ScriptsRoot = Join-Path -Path $script:VmRoot -ChildPath ".."
$script:CoreConfigPath = Join-Path -Path $script:ScriptsRoot -ChildPath "VMConfig.ps1"
$script:RefreshStatePath = Join-Path -Path $script:ScriptsRoot -ChildPath "AZ\GuardarEstadoVM.ps1"

function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Default = $null
    )

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        return $Default
    }

    return $prop.Value
}

function Resolve-Template {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][hashtable]$Map
    )

    $resolved = $Text
    foreach ($k in $Map.Keys) {
        $resolved = $resolved.Replace("{$k}", [string]$Map[$k])
    }

    return $resolved
}

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path $script:VmRoot -ChildPath $Path))
}

function Ensure-PrivateKeyPermissions {
    param([Parameter(Mandatory = $true)][string]$KeyPath)

    if (-not $IsWindows) {
        return
    }

    if (-not (Test-Path -LiteralPath $KeyPath)) {
        throw "No existe la llave privada: $KeyPath"
    }

    $icacls = Get-Command icacls.exe -ErrorAction SilentlyContinue
    if (-not $icacls) {
        Write-Host "[SSH] icacls no esta disponible; no se pueden ajustar permisos de la llave." -ForegroundColor Yellow
        return
    }

    $currentUser = $env:USERNAME
    if ([string]::IsNullOrWhiteSpace($currentUser)) {
        throw "No se pudo determinar el usuario actual para ajustar permisos de la llave."
    }

    $inheritanceResult = & icacls.exe $KeyPath /inheritance:r /grant:r "$currentUser:F" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudieron corregir los permisos de la llave privada (codigo $LASTEXITCODE)."
    }

    try {
        $acl = Get-Acl -LiteralPath $KeyPath
        $allowedAccounts = @($currentUser, 'SYSTEM', 'Administrators')
        foreach ($rule in @($acl.Access)) {
            $identity = [string]$rule.IdentityReference
            if ($allowedAccounts -notcontains $identity) {
                $acl.RemoveAccessRule($rule) | Out-Null
            }
        }

        Set-Acl -LiteralPath $KeyPath -AclObject $acl
    }
    catch {
        Write-Host "[SSH] No se pudo depurar ACLs extra de la llave; se continuo con icacls." -ForegroundColor Yellow
    }

    Write-Host "[SSH] Permisos de la llave privada verificados para $currentUser." -ForegroundColor DarkCyan
}

function Get-VmConnectionContext {
    param([switch]$RefreshIp)

    . $script:CoreConfigPath
    Ensure-PrivateKeyPermissions -KeyPath $KEY_PRIVATE_PATH

    if ($RefreshIp -or -not (Test-Path -LiteralPath $STATE_PATH)) {
        & $script:RefreshStatePath
        if ($LASTEXITCODE -ne 0) {
            throw "No se pudo actualizar vm-connection.json (codigo $LASTEXITCODE)."
        }
    }

    if (-not (Test-Path -LiteralPath $STATE_PATH)) {
        throw "No existe estado de conexion en: $STATE_PATH"
    }

    $state = Get-Content -LiteralPath $STATE_PATH -Raw | ConvertFrom-Json

    if ([string]::IsNullOrWhiteSpace($state.publicIp)) {
        throw "El estado no contiene publicIp valida."
    }

    return [PSCustomObject]@{
        User = $state.user
        PublicIp = $state.publicIp
        KeyPrivatePath = $KEY_PRIVATE_PATH
        KnownHostsPath = $SSH_KNOWN_HOSTS_PATH
        StatePath = $STATE_PATH
    }
}

function Get-UploadTaskConfigs {
    param([string]$TaskFolder = (Join-Path -Path $script:VmRoot -ChildPath "Enviar"))

    if (-not (Test-Path -LiteralPath $TaskFolder)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $TaskFolder -Filter "*.json" | Sort-Object Name)
}

function Read-TaskConfig {
    param([Parameter(Mandatory = $true)][string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "No existe config: $ConfigPath"
    }

    $task = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

    $taskName = Get-ObjectPropertyValue -Object $task -Name "taskName" -Default ""
    if ([string]::IsNullOrWhiteSpace([string]$taskName)) {
        throw "Config invalida ($ConfigPath): falta taskName"
    }

    if (-not (Get-ObjectPropertyValue -Object $task -Name "sources" -Default $null)) {
        $task | Add-Member -NotePropertyName sources -NotePropertyValue @()
    }

    return $task
}

function Invoke-SshCommand {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$Command
    )

    $args = @(Get-SshCommonArgs -Context $Context)
    $args += @(
        "$($Context.User)@$($Context.PublicIp)",
        $Command
    )

    & ssh @args
    if ($LASTEXITCODE -ne 0) {
        throw "Comando remoto fallo (codigo $LASTEXITCODE): $Command"
    }
}

function Get-SshCommonArgs {
    param(
        [Parameter(Mandatory = $true)]$Context
    )

    $args = @(
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=20",
        "-o", "ConnectionAttempts=1",
        "-o", "ServerAliveInterval=10",
        "-o", "ServerAliveCountMax=3",
        "-o", "TCPKeepAlive=yes",
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "UserKnownHostsFile=$($Context.KnownHostsPath)",
        "-o", "LogLevel=ERROR",
        "-i", $Context.KeyPrivatePath
    )

    $controlPath = Get-ObjectPropertyValue -Object $Context -Name "ControlPath" -Default ""
    if (-not [string]::IsNullOrWhiteSpace([string]$controlPath)) {
        $args += @(
            "-o", "ControlMaster=auto",
            "-o", "ControlPersist=600",
            "-o", "ControlPath=$controlPath"
        )
    }

    return $args
}

function Start-SshMasterConnection {
    param(
        [Parameter(Mandatory = $true)]$Context
    )

    if ($IsWindows) {
        Write-Host "[SSH] Multiplexado omitido en Windows para evitar errores de socket. Se usara modo normal." -ForegroundColor DarkCyan
        $existingControlPath = Get-ObjectPropertyValue -Object $Context -Name "ControlPath" -Default ""
        if (-not [string]::IsNullOrWhiteSpace([string]$existingControlPath)) {
            $Context.ControlPath = ""
        }
        return
    }

    $baseTemp = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($baseTemp)) {
        $baseTemp = [System.IO.Path]::GetTempPath()
    }

    $muxDir = Join-Path -Path $baseTemp -ChildPath "vm_ssh_mux"
    if (-not (Test-Path -LiteralPath $muxDir)) {
        New-Item -ItemType Directory -Path $muxDir | Out-Null
    }

    $safeHost = ([string]$Context.PublicIp) -replace "[^A-Za-z0-9._-]", "_"
    $controlPath = Join-Path -Path $muxDir -ChildPath "mux-$($Context.User)-$safeHost-22"
    $controlPath = $controlPath -replace "\\", "/"

    $existingControlPath = Get-ObjectPropertyValue -Object $Context -Name "ControlPath" -Default ""
    if ([string]::IsNullOrWhiteSpace([string]$existingControlPath)) {
        $Context | Add-Member -NotePropertyName ControlPath -NotePropertyValue $controlPath
    }
    else {
        $Context.ControlPath = $controlPath
    }

    Write-Host "[SSH] Abriendo conexion persistente para esta tarea..." -ForegroundColor DarkCyan

    $args = @(
        "-o", "BatchMode=no",
        "-o", "ConnectTimeout=20",
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "UserKnownHostsFile=$($Context.KnownHostsPath)",
        "-o", "LogLevel=ERROR",
        "-o", "ControlMaster=yes",
        "-o", "ControlPersist=600",
        "-o", "ControlPath=$controlPath",
        "-i", $Context.KeyPrivatePath,
        "-Nf",
        "$($Context.User)@$($Context.PublicIp)"
    )

    & ssh @args
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[SSH] No se pudo abrir conexion persistente (codigo $LASTEXITCODE). Se usara modo normal." -ForegroundColor Yellow
        $Context.ControlPath = ""
        return
    }
}

function Stop-SshMasterConnection {
    param(
        [Parameter(Mandatory = $true)]$Context
    )

    $controlPath = Get-ObjectPropertyValue -Object $Context -Name "ControlPath" -Default ""
    if ([string]::IsNullOrWhiteSpace([string]$controlPath)) {
        return
    }

    $args = @(
        "-o", "ControlPath=$controlPath",
        "-O", "exit",
        "$($Context.User)@$($Context.PublicIp)"
    )

    & ssh @args 2>$null | Out-Null
}

function Ensure-SshAgentKey {
    param(
        [Parameter(Mandatory = $true)]$Context
    )

    Ensure-PrivateKeyPermissions -KeyPath $Context.KeyPrivatePath

    $sshAdd = Get-Command ssh-add -ErrorAction SilentlyContinue
    if (-not $sshAdd) {
        Write-Host "[SSH] ssh-add no disponible; se pedira passphrase en cada conexion." -ForegroundColor Yellow
        return
    }

    $agentService = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
    if (-not $agentService) {
        Write-Host "[SSH] Servicio ssh-agent no disponible; se pedira passphrase en cada conexion." -ForegroundColor Yellow
        return
    }

    if ($agentService.Status -ne "Running") {
        try {
            Start-Service -Name "ssh-agent"
        }
        catch {
            try {
                Set-Service -Name "ssh-agent" -StartupType Manual
                Start-Service -Name "ssh-agent"
            }
            catch {
                Write-Host "[SSH] No se pudo iniciar ssh-agent (probablemente falta permiso de administrador)." -ForegroundColor Yellow
                Write-Host "[SSH] Se pedira passphrase en cada conexion." -ForegroundColor Yellow
                return
            }
        }
    }

    $fingerprint = $null
    try {
        $fpLine = (& ssh-keygen -lf $Context.KeyPrivatePath 2>$null | Select-Object -First 1)
        if (-not [string]::IsNullOrWhiteSpace($fpLine)) {
            $fpParts = $fpLine -split "\s+"
            if ($fpParts.Count -ge 2) {
                $fingerprint = $fpParts[1]
            }
        }
    }
    catch {
        $fingerprint = $null
    }

    $alreadyLoaded = $false
    try {
        $listOutput = & ssh-add -l 2>$null
        if ($LASTEXITCODE -eq 0) {
            $listText = ($listOutput | Out-String)
            if (-not [string]::IsNullOrWhiteSpace($fingerprint) -and $listText -match [regex]::Escape($fingerprint)) {
                $alreadyLoaded = $true
            }
        }
    }
    catch {
        $alreadyLoaded = $false
    }

    if ($alreadyLoaded) {
        Write-Host "[SSH] Llave ya cargada en ssh-agent." -ForegroundColor DarkCyan
        return
    }

    Write-Host "[SSH] Cargando llave en ssh-agent (pedira passphrase una sola vez)..." -ForegroundColor Cyan
    & ssh-add $Context.KeyPrivatePath
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo cargar la llave en ssh-agent (codigo $LASTEXITCODE)."
    }

    Write-Host "[SSH] Llave cargada en memoria para esta sesion." -ForegroundColor Green
}

function Send-FileToVm {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [Parameter(Mandatory = $true)][string]$RemotePath
    )

    if (-not (Test-Path -LiteralPath $LocalPath)) {
        throw "No existe archivo local: $LocalPath"
    }

    $remoteDir = Split-Path -Path $RemotePath -Parent
    if ([string]::IsNullOrWhiteSpace($remoteDir)) {
        $remoteDir = "."
    }

    Invoke-SshCommand -Context $Context -Command "mkdir -p '$remoteDir'"

    $target = "$($Context.User)@$($Context.PublicIp):$RemotePath"
    $args = @(Get-SshCommonArgs -Context $Context)
    $args += @(
        $LocalPath,
        $target
    )

    & scp @args
    if ($LASTEXITCODE -ne 0) {
        throw "Fallo SCP (codigo $LASTEXITCODE): $LocalPath -> $RemotePath"
    }
}

function Invoke-UploadTask {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [switch]$RunPostCommands,
        [switch]$RefreshIp,
        [bool]$UseSshAgent = $true
    )

    $task = Read-TaskConfig -ConfigPath $ConfigPath
    $context = Get-VmConnectionContext -RefreshIp:$RefreshIp

    if ($UseSshAgent) {
        Ensure-SshAgentKey -Context $context
    }

    Start-SshMasterConnection -Context $context

    try {

    $taskRemoteBase = [string](Get-ObjectPropertyValue -Object $task -Name "remoteBasePath" -Default "")
    $remoteBaseTemplate = if ([string]::IsNullOrWhiteSpace($taskRemoteBase)) {
        "/home/{user}/deploy"
    }
    else {
        $taskRemoteBase
    }

    $map = @{
        user = $context.User
        ip = $context.PublicIp
    }

    $remoteBase = Resolve-Template -Text $remoteBaseTemplate -Map $map
    $map["remoteBasePath"] = $remoteBase

    $taskName = [string](Get-ObjectPropertyValue -Object $task -Name "taskName" -Default "Sin nombre")
    $taskDescription = [string](Get-ObjectPropertyValue -Object $task -Name "description" -Default "")
    Write-Host "[TASK] $taskName" -ForegroundColor Cyan
    if (-not [string]::IsNullOrWhiteSpace($taskDescription)) {
        Write-Host "       $taskDescription" -ForegroundColor DarkCyan
    }

    $preCommands = Get-ObjectPropertyValue -Object $task -Name "preUploadCommands" -Default @()
    if ($preCommands) {
        foreach ($cmd in $preCommands) {
            $resolvedPreCmd = Resolve-Template -Text ([string]$cmd) -Map $map
            Write-Host "[PRE] $resolvedPreCmd"
            Invoke-SshCommand -Context $context -Command $resolvedPreCmd
        }
    }

    Invoke-SshCommand -Context $context -Command "mkdir -p '$remoteBase'"

    $taskEnvLocal = [string](Get-ObjectPropertyValue -Object $task -Name "envFileLocal" -Default "")
    $taskEnvRemote = [string](Get-ObjectPropertyValue -Object $task -Name "envFileRemote" -Default "")
    if (-not [string]::IsNullOrWhiteSpace($taskEnvLocal) -and -not [string]::IsNullOrWhiteSpace($taskEnvRemote)) {
        $envLocal = Resolve-LocalPath -Path $taskEnvLocal
        $envRemote = Resolve-Template -Text $taskEnvRemote -Map $map
        Write-Host "[UPLOAD] $envLocal -> $envRemote"
        Send-FileToVm -Context $context -LocalPath $envLocal -RemotePath $envRemote
    }

    $taskSources = Get-ObjectPropertyValue -Object $task -Name "sources" -Default @()
    foreach ($src in $taskSources) {
        $srcLocal = [string](Get-ObjectPropertyValue -Object $src -Name "local" -Default "")
        $srcRemote = [string](Get-ObjectPropertyValue -Object $src -Name "remote" -Default "")

        if ([string]::IsNullOrWhiteSpace($srcLocal) -or [string]::IsNullOrWhiteSpace($srcRemote)) {
            throw "Config invalida en ${ConfigPath}: cada source requiere local y remote."
        }

        $localFile = Resolve-LocalPath -Path $srcLocal
        $remoteFile = Resolve-Template -Text $srcRemote -Map $map
        Write-Host "[UPLOAD] $localFile -> $remoteFile"
        Send-FileToVm -Context $context -LocalPath $localFile -RemotePath $remoteFile

        $srcChmod = [string](Get-ObjectPropertyValue -Object $src -Name "chmod" -Default "")
        if (-not [string]::IsNullOrWhiteSpace($srcChmod)) {
            Invoke-SshCommand -Context $context -Command "chmod $srcChmod '$remoteFile'"
        }
    }

    $postCommands = Get-ObjectPropertyValue -Object $task -Name "postUploadCommands" -Default @()
    if ($RunPostCommands -and $postCommands) {
        foreach ($cmd in $postCommands) {
            $resolvedCmd = Resolve-Template -Text ([string]$cmd) -Map $map
            Write-Host "[REMOTE] $resolvedCmd"
            Invoke-SshCommand -Context $context -Command $resolvedCmd
        }
    }

    Write-Host "[OK] Tarea completada: $taskName" -ForegroundColor Green
    }
    finally {
        Stop-SshMasterConnection -Context $context
    }
}
