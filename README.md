# Scripts de Computo en la Nube (Azure + despliegues en VM)

Este repositorio automatiza dos capas de trabajo:

1. Infraestructura en Azure (crear/redes/VM, estado de conexion, SSH).
2. Despliegues dentro de la VM (base de datos, app PHP, bootstrap seguro Nginx+MySQL+PM2, proyecto final).

La idea es ejecutar primero la capa `AZ` para tener VM accesible, y despues la capa `VM` para subir y ejecutar tareas remotas.

## Estructura general

```text
Scripts/
├─ VMConfig.ps1                      # Configuracion central (RG, VM, usuario, llaves, estado)
├─ vm-connection.json                # Estado single-VM (generado automaticamente)
├─ vm-connections-multired.json      # Estado multi-VM (generado automaticamente)
├─ AZ/                               # Automatizacion de Azure CLI
│  ├─ main.ps1
│  ├─ CrearVM.ps1
│  ├─ CrearRedVirtual.ps1
│  ├─ ConectarVM.ps1
│  ├─ ConectarVMMenu.ps1
│  ├─ GuardarEstadoVM.ps1
│  ├─ RegenerarEstadoVMs.ps1
│  ├─ UnirRedesPrincipales.ps1
│  └─ BorrarVM.ps1
└─ VM/                               # Subida de archivos y ejecucion remota por tareas JSON
   ├─ main_vm.ps1
   ├─ Upload-Menu.ps1
   ├─ Upload-Lib.ps1
   ├─ Enable-SshAgent.ps1
   ├─ Enviar/*.json                  # Definiciones de tareas
   ├─ RemoteScripts/*.sh             # Scripts bash que corren dentro de la VM
   └─ Templates/*.env(.example)      # Variables de entorno para tareas
```

## Prerequisitos

### En Windows (maquina local)

- PowerShell 5.1+ (o PowerShell 7).
- Azure CLI instalado y autenticado.
- OpenSSH client (`ssh`, `scp`, `ssh-add`, `ssh-keygen`) disponible en PATH.
- Llave SSH publica/privada existente.
- Permisos para iniciar servicio `ssh-agent` (idealmente consola con permisos elevados la primera vez).

### En Azure

- Suscripcion activa.
- Cuota disponible para VMs en las regiones que uses.

### En la VM (se instala automaticamente segun tarea)

- Ubuntu (el default es Ubuntu 24.04 LTS).
- Los scripts remotos instalan Apache o Nginx/PHP/MySQL segun el escenario.

## Configuracion inicial

### 1) Ajustar VMConfig.ps1

Edita `VMConfig.ps1` y valida al menos:

- `RG`, `LOC`, `VM_NAME`, `USER`, `SIZE`.
- `SO` (URN valida de imagen o alias soportado).
- `KEY_PRIVATE_RELATIVE` y `KEY_PUBLIC_RELATIVE`.
- `AUTO_DELETE` (normalmente en `false`).

Notas:

- `SSH_KNOWN_HOSTS_PATH` usa un `known_hosts` local del proyecto para no tocar el global.
- `STATE_PATH` apunta a `vm-connection.json` en la raiz.

### 2) Login de Azure

```powershell
az login
az account show --output table
```

### 3) Preparar archivos .env para tareas VM

```powershell
Copy-Item .\VM\Templates\db-school.env.example .\VM\Templates\db-school.env
Copy-Item .\VM\Templates\web-stack.env.example .\VM\Templates\web-stack.env
```

Despues, edita:

- `VM/Templates/db-school.env`
- `VM/Templates/web-stack.env`

Cambia todas las contrasenas `CHANGE_ME` por valores fuertes.

## Flujo recomendado (camino rapido)

### Paso A: Crear VM y conectar

```powershell
.\AZ\main.ps1
```

`AZ/main.ps1` hace, por defecto:

1. Valida contexto de Azure.
2. Crea infraestructura y VM (`CrearVM.ps1`).
3. Guarda IP/estado (`GuardarEstadoVM.ps1`).
4. Intenta conexion SSH (`ConectarVM.ps1`).

Parametros utiles:

```powershell
.\AZ\main.ps1 -SkipCreate
.\AZ\main.ps1 -SkipConnect
.\AZ\main.ps1 -RefreshIp
.\AZ\main.ps1 -RebuildState
.\AZ\main.ps1 -MultiNet
```

### Paso B: Subir y ejecutar tareas en la VM

```powershell
.\VM\main_vm.ps1
```

Abre un menu interactivo para elegir tareas (`VM/Enviar/*.json`), con modo:

- Solo subir.
- Subir y ejecutar.

Tambien puedes ejecutar de forma no interactiva:

```powershell
.\VM\Upload-Menu.ps1 -SelectedIndexes 1,2 -ExecutionMode upload-run
```

## Scripts principales de AZ

- `AZ/CrearVM.ps1`: crea RG, VNet, subnet, IP publica, NSG (22/80/443), NIC y VM.
- `AZ/GuardarEstadoVM.ps1`: consulta IP y actualiza `vm-connection.json`.
- `AZ/ConectarVM.ps1`: conecta por SSH usando estado local o consulta Azure.
- `AZ/ConectarVMMenu.ps1`: menu para elegir VM desde estado multi/single.
- `AZ/CrearRedVirtual.ps1`: crea 3 redes + 3 VMs y actualiza estados.
- `AZ/UnirRedesPrincipales.ps1`: crea VNet peering y reglas ICMP en NSG.
- `AZ/RegenerarEstadoVMs.ps1`: reconstruye JSONs de estado desde Azure.
- `AZ/BorrarVM.ps1`: elimina RG completo (con confirmacion salvo `-Force`).

## Scripts principales de VM

- `VM/Upload-Lib.ps1`:
  - Lee configuraciones JSON de tareas.
  - Resuelve placeholders (`{user}`, `{remoteBasePath}`, etc.).
  - Sube archivos por `scp`.
  - Ejecuta comandos remotos por `ssh`.
  - Gestiona `ssh-agent` y permisos de llave en Windows.
- `VM/Upload-Menu.ps1`: UI de seleccion de tareas.
- `VM/Enable-SshAgent.ps1`: arranca/corrige `ssh-agent` y carga la llave.

## Tareas JSON incluidas

En `VM/Enviar`:

1. `01-crear-bd-escuela.json`
   - Sube y ejecuta `RemoteScripts/crear_BD_escuela.sh`.
   - Usa `Templates/db-school.env`.

2. `02-cargar-datos-escuela.json`
   - Reusa creacion BD.
   - Carga datos y queries de evidencia con `cargar_datos_escuela.sh`.

3. `03-pagina-web.json`
   - Sube app PHP simple (`Pagina/`).
   - Ejecuta `desplegar_pagina_web.sh`.
   - Publica en `/var/www/html/school`.

4. `04-bootstrap-web-seguro.json`
   - Ejecuta `bootstrap_web_seguro.sh`.
   - Instala Nginx, MySQL, PHP-FPM, PM2, UFW, Fail2Ban, unattended upgrades.
   - Crea helper `/usr/local/bin/deploy-static-site`.

5. `05-desplegar-proyecto-nube.json`
   - Sube `Enviar/proyecto_nube/`.
   - Importa SQL.
   - Ajusta `config/db.php` remoto.
   - Publica con Nginx + PHP-FPM usando `deploy-static-site`.

6. `99-template-futuro.json`
   - Plantilla para nuevas tareas.

## Variables de entorno

### db-school.env

Base usada por tareas 01-03.

Variables esperadas:

- `MYSQL_DB_NAME`
- `MYSQL_ADMIN_USER`
- `MYSQL_ADMIN_PASSWORD`
- `MYSQL_GESTION_USER`
- `MYSQL_GESTION_PASSWORD`

### web-stack.env

Base usada por tareas 04-05.

Incluye, ademas de credenciales:

- `WEB_SITE_NAME`
- `WEB_DEPLOY_BASE`
- `WEB_ROOT_BASE`
- `QUIZ_DB_NAME`
- `QUIZ_DB_HOST`
- `QUIZ_DB_PORT`
- `QUIZ_SITE_NAME`

## Estados JSON (auto-generados)

- `vm-connection.json`: contexto principal de conexion (`rg`, `vmName`, `user`, `publicIp`, rutas de llaves).
- `vm-connections-multired.json`: lista de VMs para menu multi.

No se recomienda editar estos archivos manualmente.

Para regenerarlos:

```powershell
.\AZ\RegenerarEstadoVMs.ps1
```

## Escenario multi-red

1. Crear 3 redes + 3 VMs:

```powershell
.\AZ\main.ps1 -MultiNet -SkipConnect
```

2. Unir redes por peering y habilitar ICMP:

```powershell
.\AZ\UnirRedesPrincipales.ps1
```

3. Conectar a una VM desde menu:

```powershell
.\AZ\ConectarVMMenu.ps1
```

## Limpieza de recursos

Eliminar el grupo de recursos completo:

```powershell
.\AZ\BorrarVM.ps1 -ResourceGroup ProyectoParcial01
```

Opciones:

- `-Force`: no pedir confirmacion.
- `-Wait`: esperar fin de borrado.
- `-ClearState`: borra `vm-connection.json` local.

## Solucion de problemas (troubleshooting)

### 1) Error de autenticacion Azure CLI

- Ejecuta `az login`.
- Verifica suscripcion activa con `az account show`.

### 2) No conecta por SSH

- Regenera estado: `AZ/GuardarEstadoVM.ps1` o `AZ/RegenerarEstadoVMs.ps1`.
- Reintenta con refresh: `AZ/ConectarVM.ps1 -RefreshIp`.
- Verifica NSG puerto 22 y que la VM este encendida.
- Revisa ruta de llaves en `VMConfig.ps1`.

### 3) Passphrase pedida muchas veces

- Ejecuta `VM/Enable-SshAgent.ps1` antes del menu.
- Confirma que `UseSshAgent` este en `true`.

### 4) Fallan tareas por variables vacias

- Revisa `.env` en `VM/Templates`.
- No dejes `CHANGE_ME`.
- Evita caracteres invalidos para nombres de DB/usuarios.

### 5) Sitio no carga en HTTP

- Verifica servicios en VM: `nginx`, `apache2`, `php-fpm`, `mysql` segun tarea.
- Confirma reglas NSG para 80/443.
- Revisa paths de despliegue (`/var/www/html/school` o `/var/www/sites/<site>/current`).

## Buenas practicas

- Mantener `AUTO_DELETE = $false` durante pruebas.
- Ejecutar tareas en orden cuando dependan entre si (ej. bootstrap antes de deploy final).
- Versionar solo templates `.env.example`, no secretos reales.
- Regenerar estado JSON cuando cambie IP publica.

## Referencias utiles dentro del repo

- Proyecto web final y detalle funcional: `VM/Enviar/proyecto_nube/README.md`
- Checklist de evidencias/capturas: `VM/Templates/notas_capturas_escuela.txt`

---

Si quieres, puedo agregar una seccion extra con un "quickstart de 5 minutos" enfocado unicamente al proyecto final (`04` + `05`) y comandos exactos para validacion final.
