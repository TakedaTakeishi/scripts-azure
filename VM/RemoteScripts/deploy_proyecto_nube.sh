#!/usr/bin/env bash
set -euo pipefail

log_info() {
  echo "[INFO] $1"
}

log_error() {
  echo "[ERROR] $1" >&2
}

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

normalize_env_value() {
  local value="$1"
  value="${value%$'\r'}"

  if [[ ${#value} -ge 2 ]]; then
    local first="${value:0:1}"
    local last="${value: -1}"
    if [[ "$first" == '"' && "$last" == '"' ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$first" == "'" && "$last" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi
  fi

  printf '%s' "$value"
}

SOURCE_DIR=""
SQL_FILE=""
ENV_FILE=""
DEPLOY_USER=""
SITE_NAME=""
DEPLOY_BASE=""
WEB_ROOT_BASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-dir)
      SOURCE_DIR="${2:-}"
      shift 2
      ;;
    --sql-file)
      SQL_FILE="${2:-}"
      shift 2
      ;;
    --env-file)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    --deploy-user)
      DEPLOY_USER="${2:-}"
      shift 2
      ;;
    --site-name)
      SITE_NAME="${2:-}"
      shift 2
      ;;
    --deploy-base)
      DEPLOY_BASE="${2:-}"
      shift 2
      ;;
    --web-root-base)
      WEB_ROOT_BASE="${2:-}"
      shift 2
      ;;
    *)
      log_error "Parametro no soportado: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$SOURCE_DIR" || -z "$SQL_FILE" || -z "$ENV_FILE" || -z "$DEPLOY_USER" ]]; then
  log_error "Uso: deploy_proyecto_nube.sh --source-dir <dir> --sql-file <sql> --env-file <env> --deploy-user <user> [--site-name <name>]"
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  log_error "No existe source-dir: $SOURCE_DIR"
  exit 1
fi

if [[ ! -f "$SQL_FILE" ]]; then
  log_error "No existe sql-file: $SQL_FILE"
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  log_error "No existe env-file: $ENV_FILE"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

MYSQL_ADMIN_USER="$(normalize_env_value "${MYSQL_ADMIN_USER:-admin}")"
MYSQL_ADMIN_PASSWORD="$(normalize_env_value "${MYSQL_ADMIN_PASSWORD:-}")"
MYSQL_GESTION_USER="$(normalize_env_value "${MYSQL_GESTION_USER:-gestion}")"
MYSQL_GESTION_PASSWORD="$(normalize_env_value "${MYSQL_GESTION_PASSWORD:-}")"
QUIZ_DB_NAME="$(normalize_env_value "${QUIZ_DB_NAME:-quiz_db}")"
QUIZ_DB_HOST="$(normalize_env_value "${QUIZ_DB_HOST:-localhost}")"
QUIZ_DB_PORT="$(normalize_env_value "${QUIZ_DB_PORT:-3306}")"
QUIZ_SITE_NAME="$(normalize_env_value "${QUIZ_SITE_NAME:-proyecto-nube}")"

if [[ -n "$SITE_NAME" ]]; then
  QUIZ_SITE_NAME="$SITE_NAME"
fi

if [[ -z "$DEPLOY_BASE" ]]; then
  DEPLOY_BASE="/home/$DEPLOY_USER/deploy/sites"
fi

if [[ -z "$WEB_ROOT_BASE" ]]; then
  WEB_ROOT_BASE="/var/www/sites"
fi

if [[ -z "$MYSQL_ADMIN_PASSWORD" || "$MYSQL_ADMIN_PASSWORD" == "CHANGE_ME" ]]; then
  log_error "MYSQL_ADMIN_PASSWORD invalido en env-file."
  exit 1
fi

if [[ -z "$MYSQL_GESTION_PASSWORD" || "$MYSQL_GESTION_PASSWORD" == "CHANGE_ME" ]]; then
  log_error "MYSQL_GESTION_PASSWORD invalido en env-file."
  exit 1
fi

if [[ ! -x "/usr/local/bin/deploy-static-site" ]]; then
  log_error "No existe helper /usr/local/bin/deploy-static-site. Ejecuta primero bootstrap_web_seguro.sh"
  exit 1
fi

log_info "Validando runtime (Nginx/PHP/MySQL)"
run_as_root apt-get update -y
run_as_root DEBIAN_FRONTEND=noninteractive apt-get install -y nginx mysql-server php-fpm php-mysql php-cli
run_as_root systemctl enable nginx mysql
run_as_root systemctl start nginx mysql

php_fpm_service="$(systemctl list-unit-files 'php*-fpm.service' --no-legend 2>/dev/null | awk '{print $1}' | head -n1 || true)"
if [[ -n "$php_fpm_service" ]]; then
  run_as_root systemctl enable "$php_fpm_service"
  run_as_root systemctl start "$php_fpm_service"
fi

PHP_FPM_SOCK="$(ls /run/php/php*-fpm.sock 2>/dev/null | head -n1 || true)"
if [[ -z "$PHP_FPM_SOCK" ]]; then
  log_error "No se encontro socket de PHP-FPM."
  exit 1
fi

WEB_ROOT="$WEB_ROOT_BASE/$QUIZ_SITE_NAME"
CURRENT_LINK="$WEB_ROOT/current"

log_info "Configurando Nginx para $QUIZ_SITE_NAME"
TMP_NGINX="$(mktemp)"
cat > "$TMP_NGINX" <<NGINX
server {
  listen 80;
  listen [::]:80;
  server_name _;

  root $CURRENT_LINK;
  index index.php index.html;

  location / {
    try_files \$uri \$uri/ /index.php?\$query_string /index.html;
  }

  location ~ \.php$ {
    include snippets/fastcgi-php.conf;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    fastcgi_pass unix:$PHP_FPM_SOCK;
  }

  location ~* \\.(?:css|js|mjs|json|map|jpg|jpeg|png|gif|svg|ico|webp|woff2?)$ {
    expires 7d;
    add_header Cache-Control "public, max-age=604800, immutable";
    try_files \$uri =404;
  }
}
NGINX
run_as_root install -m 0644 "$TMP_NGINX" "/etc/nginx/sites-available/$QUIZ_SITE_NAME.conf"
rm -f "$TMP_NGINX"
run_as_root ln -sfn "/etc/nginx/sites-available/$QUIZ_SITE_NAME.conf" "/etc/nginx/sites-enabled/$QUIZ_SITE_NAME.conf"
if [[ -f "/etc/nginx/sites-enabled/default" ]]; then
  run_as_root rm -f /etc/nginx/sites-enabled/default
fi
run_as_root nginx -t
run_as_root systemctl reload nginx

log_info "Importando esquema SQL"
run_as_root mysql < "$SQL_FILE"

log_info "Asegurando privilegios para usuario de aplicacion"
run_as_root mysql <<SQL
CREATE USER IF NOT EXISTS '$MYSQL_ADMIN_USER'@'localhost' IDENTIFIED BY '$MYSQL_ADMIN_PASSWORD';
ALTER USER '$MYSQL_ADMIN_USER'@'localhost' IDENTIFIED BY '$MYSQL_ADMIN_PASSWORD';
GRANT ALL PRIVILEGES ON \`$QUIZ_DB_NAME\`.* TO '$MYSQL_ADMIN_USER'@'localhost';

CREATE USER IF NOT EXISTS '$MYSQL_GESTION_USER'@'localhost' IDENTIFIED BY '$MYSQL_GESTION_PASSWORD';
ALTER USER '$MYSQL_GESTION_USER'@'localhost' IDENTIFIED BY '$MYSQL_GESTION_PASSWORD';
GRANT SELECT, INSERT ON \`$QUIZ_DB_NAME\`.* TO '$MYSQL_GESTION_USER'@'localhost';

FLUSH PRIVILEGES;
SQL

log_info "Ajustando config/db.php para entorno remoto"
cat > "$SOURCE_DIR/config/db.php" <<PHP
<?php
declare(strict_types=1);

define('DB_HOST', '$QUIZ_DB_HOST');
define('DB_PORT', '$QUIZ_DB_PORT');
define('DB_NAME', '$QUIZ_DB_NAME');
define('DB_USER', '$MYSQL_GESTION_USER');
define('DB_PASS', '$MYSQL_GESTION_PASSWORD');
define('DB_CHARSET', 'utf8mb4');

function getDB(): PDO {
    static $pdo = null;

    if ($pdo === null) {
        $dsn = sprintf(
            'mysql:host=%s;port=%s;dbname=%s;charset=%s',
            DB_HOST, DB_PORT, DB_NAME, DB_CHARSET
        );

        $options = [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ];

        try {
            $pdo = new PDO($dsn, DB_USER, DB_PASS, $options);
        } catch (PDOException $e) {
            http_response_code(500);
            header('Content-Type: application/json');
            echo json_encode(['ok' => false, 'error' => 'Error de conexion a la base de datos.']);
            exit;
        }
    }

    return $pdo;
}
PHP

log_info "Publicando proyecto con deploy-static-site"
/usr/local/bin/deploy-static-site \
  --source "$SOURCE_DIR" \
  --site-name "$QUIZ_SITE_NAME" \
  --deploy-user "$DEPLOY_USER" \
  --deploy-base "$DEPLOY_BASE" \
  --web-root-base "$WEB_ROOT_BASE"

log_info "Validando sintaxis PHP"
php -l "$SOURCE_DIR/api/submit.php" >/dev/null
php -l "$SOURCE_DIR/config/db.php" >/dev/null

log_info "Despliegue listo."
log_info "URL esperada: http://<IP_PUBLICA>/"
log_info "Endpoint API: http://<IP_PUBLICA>/api/submit.php"
