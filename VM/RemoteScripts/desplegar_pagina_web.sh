#!/usr/bin/env bash
set -euo pipefail

log_info() {
  echo "[INFO] $1"
}

log_error() {
  echo "[ERROR] $1" >&2
}

log_step() {
  echo
  echo "=============================="
  echo "$1"
  echo "=============================="
}

SOURCE_DIR=""
ENV_FILE=""
WEB_ROOT=""

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-dir)
      if [[ -z "${2:-}" ]]; then
        log_error "Error: --source-dir requiere un argumento."
        exit 1
      fi
      SOURCE_DIR="$2"
      shift 2
      ;;
    --env-file)
      if [[ -z "${2:-}" ]]; then
        log_error "Error: --env-file requiere un argumento."
        exit 1
      fi
      ENV_FILE="$2"
      shift 2
      ;;
    --web-root)
      if [[ -z "${2:-}" ]]; then
        log_error "Error: --web-root requiere un argumento."
        exit 1
      fi
      WEB_ROOT="$2"
      shift 2
      ;;
    *)
      log_error "Parametro no soportado: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$SOURCE_DIR" ]]; then
  SOURCE_DIR="$HOME/deploy/school/webapp"
fi

if [[ -z "$ENV_FILE" ]]; then
  ENV_FILE="$HOME/deploy/school/db-school.env"
fi

if [[ -z "$WEB_ROOT" ]]; then
  WEB_ROOT="/var/www/html/school"
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  log_error "No existe source-dir: $SOURCE_DIR"
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  log_error "No existe env-file: $ENV_FILE"
  exit 1
fi

for file in config.php index.php style.css; do
  if [[ ! -f "$SOURCE_DIR/$file" ]]; then
    log_error "Falta archivo requerido en source-dir: $file"
    exit 1
  fi
done

ensure_package() {
  local package_name="$1"
  if dpkg -s "$package_name" >/dev/null 2>&1; then
    log_info "Paquete ya instalado: $package_name"
    return 1
  fi

  return 0
}

log_step "Instalando dependencias web (Apache + PHP)"
apt_needed=false
for package in apache2 php libapache2-mod-php php-mysql php-mbstring; do
  if ensure_package "$package"; then
    if [[ "$apt_needed" == false ]]; then
      log_info "Actualizando indice de paquetes..."
      run_as_root apt-get update -y
      apt_needed=true
    fi
    log_info "Instalando: $package"
    run_as_root apt-get install -y "$package"
  fi
done

log_step "Publicando archivos en Apache"
run_as_root mkdir -p "$WEB_ROOT"

for file in config.php index.php style.css; do
  run_as_root install -m 0644 "$SOURCE_DIR/$file" "$WEB_ROOT/$file"
done

run_as_root chown -R www-data:www-data "$WEB_ROOT"
run_as_root find "$WEB_ROOT" -type d -exec chmod 755 {} +
run_as_root find "$WEB_ROOT" -type f -exec chmod 644 {} +

log_step "Habilitando acceso minimo al env para www-data"
run_as_root chmod o+x /home/joni
run_as_root chmod o+x /home/joni/deploy
run_as_root chmod o+x /home/joni/deploy/school
run_as_root chmod 664 "$ENV_FILE"

log_step "Reiniciando Apache"
run_as_root systemctl enable apache2 >/dev/null 2>&1 || true
run_as_root systemctl restart apache2

log_step "Validando conexion PDO usando env-file"
php -r '
$envFile = $argv[1] ?? "";
if ($envFile === "" || !is_file($envFile)) {
    fwrite(STDERR, "[ERROR] env file no valido\n");
    exit(1);
}
$vars = [];
foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
    $line = trim($line);
    if ($line === "" || str_starts_with($line, "#")) {
        continue;
    }
    $parts = explode("=", $line, 2);
    if (count($parts) !== 2) {
        continue;
    }
    $value = trim($parts[1]);
    if (strlen($value) >= 2) {
      $first = $value[0];
      $last = $value[strlen($value) - 1];
      if (($first === "\"" && $last === "\"") || ($first === chr(39) && $last === chr(39))) {
        $value = substr($value, 1, -1);
      }
    }
    $vars[trim($parts[0])] = $value;
}
$db = $vars["MYSQL_DB_NAME"] ?? "";
$user = $vars["MYSQL_ADMIN_USER"] ?? "";
$pass = $vars["MYSQL_ADMIN_PASSWORD"] ?? "";
$host = $vars["MYSQL_DB_HOST"] ?? "localhost";
if ($db === "" || $user === "" || $pass === "") {
    fwrite(STDERR, "[ERROR] faltan variables MYSQL_DB_NAME/MYSQL_ADMIN_USER/MYSQL_ADMIN_PASSWORD\n");
    exit(1);
}
$dsn = "mysql:host={$host};dbname={$db};charset=utf8mb4";
new PDO($dsn, $user, $pass, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
echo "[OK] Conexion PDO validada\n";
' "$ENV_FILE"

log_info "Despliegue completado. Abre: http://<IP_PUBLICA>/school"
