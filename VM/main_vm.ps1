param(
    [switch]$RefreshIp
)

$menu = Join-Path -Path $PSScriptRoot -ChildPath "Upload-Menu.ps1"
& $menu -RefreshIp:$RefreshIp
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
