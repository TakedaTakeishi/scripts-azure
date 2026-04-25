# Configuración central para crear y conectar a la VM
$RG = "ProyectoParcial01"
$LOC = "mexicocentral"
$VNET = "RedProyecto01"
$SUBNET = "Principal"
$IP_NAME = "IP01"
$NSG = "NSG01"
$NIC = "NIC01"
$VM_NAME = "Maquina01"
$USER = "joni"
$SO = "Canonical:ubuntu-24_04-lts:server:latest"
$SIZE = "Standard_B2s_v2"

# Si es $true, al final de CrearVM.ps1 se borra el grupo de recursos.
$AUTO_DELETE = $false

# Archivo local de hosts conocidos para no modificar el global de ~/.ssh.
$SSH_KNOWN_HOSTS_PATH = Join-Path -Path $PSScriptRoot -ChildPath "known_hosts_vm"

# Llaves SSH (rutas relativas a esta carpeta Scripts)
$KEY_PRIVATE_RELATIVE = "..\Llaves\Llave_AZ"
$KEY_PUBLIC_RELATIVE = "..\Llaves\Llave_AZ.pub"

if ([System.IO.Path]::IsPathRooted($KEY_PRIVATE_RELATIVE)) {
    $KEY_PRIVATE_PATH = [System.IO.Path]::GetFullPath($KEY_PRIVATE_RELATIVE)
}
else {
    $KEY_PRIVATE_PATH = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath $KEY_PRIVATE_RELATIVE))
}

if ([System.IO.Path]::IsPathRooted($KEY_PUBLIC_RELATIVE)) {
    $KEY_PUBLIC_PATH = [System.IO.Path]::GetFullPath($KEY_PUBLIC_RELATIVE)
}
else {
    $KEY_PUBLIC_PATH = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath $KEY_PUBLIC_RELATIVE))
}

$STATE_PATH = Join-Path -Path $PSScriptRoot -ChildPath "vm-connection.json"
