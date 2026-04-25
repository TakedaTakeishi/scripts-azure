#!/usr/bin/env bash
set -euo pipefail

log_info() {
  echo "[INFO] $1"
}

log_warn() {
  echo "[WARN] $1"
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

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

run_as_user() {
  local user_name="$1"
  shift

  if [[ "$(id -u)" -eq 0 ]]; then
    runuser -u "$user_name" -- "$@"
  else
    sudo -u "$user_name" "$@"
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

ensure_package() {
  local package_name="$1"
  if dpkg -s "$package_name" >/dev/null 2>&1; then
    log_info "Paquete ya instalado: $package_name"
    return 1
  fi

  return 0
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

assert_strong_password() {
  local value="$1"
  local label="$2"

  if [[ ${#value} -lt 12 ]]; then
    log_error "$label debe tener al menos 12 caracteres."
    exit 1
  fi

  if [[ ! "$value" =~ [A-Z] ]]; then
    log_error "$label debe contener al menos una mayuscula."
    exit 1
  fi

  if [[ ! "$value" =~ [a-z] ]]; then
    log_error "$label debe contener al menos una minuscula."
    exit 1
  fi

  if [[ ! "$value" =~ [0-9] ]]; then
    log_error "$label debe contener al menos un numero."
    exit 1
  fi

  if [[ ! "$value" =~ [^A-Za-z0-9] ]]; then
    log_error "$label debe contener al menos un simbolo."
    exit 1
  fi
}

ENV_FILE=""
DEPLOY_USER=""
SITE_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    *)
      log_error "Parametro no soportado: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$DEPLOY_USER" ]]; then
  if has_cmd whoami; then
    DEPLOY_USER="$(whoami)"
  else
    log_error "No se pudo detectar DEPLOY_USER."
    exit 1
  fi
fi

if [[ ! "$DEPLOY_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  log_error "deploy-user invalido: $DEPLOY_USER"
  exit 1
fi

if [[ -z "$ENV_FILE" ]]; then
  ENV_FILE="/home/$DEPLOY_USER/deploy/web-stack/web-stack.env"
fi

if [[ ! -f "$ENV_FILE" ]]; then
  log_error "No existe env-file: $ENV_FILE"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

MYSQL_DB_NAME="$(normalize_env_value "${MYSQL_DB_NAME:-school}")"
MYSQL_ADMIN_USER="$(normalize_env_value "${MYSQL_ADMIN_USER:-admin}")"
MYSQL_ADMIN_PASSWORD="$(normalize_env_value "${MYSQL_ADMIN_PASSWORD:-}")"
MYSQL_GESTION_USER="$(normalize_env_value "${MYSQL_GESTION_USER:-gestion}")"
MYSQL_GESTION_PASSWORD="$(normalize_env_value "${MYSQL_GESTION_PASSWORD:-}")"
WEB_SITE_NAME="$(normalize_env_value "${WEB_SITE_NAME:-web-static}")"
WEB_DEPLOY_BASE="$(normalize_env_value "${WEB_DEPLOY_BASE:-/home/$DEPLOY_USER/deploy/sites}")"
WEB_ROOT_BASE="$(normalize_env_value "${WEB_ROOT_BASE:-/var/www/sites}")"

if [[ -n "$SITE_NAME" ]]; then
  WEB_SITE_NAME="$SITE_NAME"
fi

if [[ ! "$MYSQL_DB_NAME" =~ ^[A-Za-z0-9_]+$ ]]; then
  log_error "MYSQL_DB_NAME invalido: $MYSQL_DB_NAME"
  exit 1
fi

if [[ ! "$MYSQL_ADMIN_USER" =~ ^[A-Za-z0-9_]+$ ]]; then
  log_error "MYSQL_ADMIN_USER invalido: $MYSQL_ADMIN_USER"
  exit 1
fi

if [[ ! "$MYSQL_GESTION_USER" =~ ^[A-Za-z0-9_]+$ ]]; then
  log_error "MYSQL_GESTION_USER invalido: $MYSQL_GESTION_USER"
  exit 1
fi

if [[ ! "$WEB_SITE_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  log_error "WEB_SITE_NAME invalido: $WEB_SITE_NAME"
  exit 1
fi

if [[ -z "$MYSQL_ADMIN_PASSWORD" || "$MYSQL_ADMIN_PASSWORD" == "CHANGE_ME" ]]; then
  log_error "MYSQL_ADMIN_PASSWORD no puede estar vacio ni en CHANGE_ME."
  exit 1
fi

if [[ -z "$MYSQL_GESTION_PASSWORD" || "$MYSQL_GESTION_PASSWORD" == "CHANGE_ME" ]]; then
  log_error "MYSQL_GESTION_PASSWORD no puede estar vacio ni en CHANGE_ME."
  exit 1
fi

assert_strong_password "$MYSQL_ADMIN_PASSWORD" "MYSQL_ADMIN_PASSWORD"
assert_strong_password "$MYSQL_GESTION_PASSWORD" "MYSQL_GESTION_PASSWORD"

if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  log_error "El usuario de despliegue no existe: $DEPLOY_USER"
  exit 1
fi

INCOMING_DIR="$WEB_DEPLOY_BASE/incoming"
RELEASES_DIR="$WEB_DEPLOY_BASE/releases"
SHARED_DIR="$WEB_DEPLOY_BASE/shared"
LOGS_DIR="$WEB_DEPLOY_BASE/logs"
WEB_ROOT="$WEB_ROOT_BASE/$WEB_SITE_NAME"
CURRENT_LINK="$WEB_ROOT/current"

log_step "Actualizando Ubuntu"
run_as_root apt-get update -y
run_as_root DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

log_step "Instalando paquetes base y seguridad"
apt_updated=false
for package in nginx mysql-server nodejs npm ufw fail2ban unattended-upgrades rsync curl php-fpm php-mysql php-cli; do
  if ensure_package "$package"; then
    if [[ "$apt_updated" == false ]]; then
      run_as_root apt-get update -y
      apt_updated=true
    fi
    run_as_root DEBIAN_FRONTEND=noninteractive apt-get install -y "$package"
  fi
done

log_step "Instalando PM2 global"
if ! has_cmd pm2; then
  run_as_root npm install -g pm2
else
  log_info "PM2 ya esta instalado."
fi

log_step "Hardening MySQL tipo secure installation"
run_as_root systemctl enable mysql
run_as_root systemctl start mysql

run_as_root mysql <<SQL
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL

run_as_root mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`$MYSQL_DB_NAME\`;
CREATE USER IF NOT EXISTS '$MYSQL_ADMIN_USER'@'localhost' IDENTIFIED BY '$MYSQL_ADMIN_PASSWORD';
ALTER USER '$MYSQL_ADMIN_USER'@'localhost' IDENTIFIED BY '$MYSQL_ADMIN_PASSWORD';
GRANT ALL PRIVILEGES ON \`$MYSQL_DB_NAME\`.* TO '$MYSQL_ADMIN_USER'@'localhost';

CREATE USER IF NOT EXISTS '$MYSQL_GESTION_USER'@'localhost' IDENTIFIED BY '$MYSQL_GESTION_PASSWORD';
ALTER USER '$MYSQL_GESTION_USER'@'localhost' IDENTIFIED BY '$MYSQL_GESTION_PASSWORD';
GRANT SELECT, INSERT ON \`$MYSQL_DB_NAME\`.* TO '$MYSQL_GESTION_USER'@'localhost';

FLUSH PRIVILEGES;
SQL

log_step "Preparando estructura de carpetas para deploy"
run_as_root mkdir -p "$INCOMING_DIR" "$RELEASES_DIR" "$SHARED_DIR" "$LOGS_DIR" "$WEB_ROOT"
run_as_root chown -R "$DEPLOY_USER":"$DEPLOY_USER" "$WEB_DEPLOY_BASE"
run_as_root chmod 750 "$WEB_DEPLOY_BASE" "$INCOMING_DIR" "$RELEASES_DIR" "$SHARED_DIR" "$LOGS_DIR"

log_step "Instalando helper de despliegue estatico"
TMP_HELPER="$(mktemp)"
cat > "$TMP_HELPER" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Uso: deploy-static-site --source <carpeta> --site-name <nombre> [--deploy-user <usuario>]"
}

SOURCE=""
SITE_NAME=""
DEPLOY_USER=""
WEB_DEPLOY_BASE=""
WEB_ROOT_BASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE="${2:-}"
      shift 2
      ;;
    --site-name)
      SITE_NAME="${2:-}"
      shift 2
      ;;
    --deploy-user)
      DEPLOY_USER="${2:-}"
      shift 2
      ;;
    --deploy-base)
      WEB_DEPLOY_BASE="${2:-}"
      shift 2
      ;;
    --web-root-base)
      WEB_ROOT_BASE="${2:-}"
      shift 2
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$SOURCE" || -z "$SITE_NAME" || -z "$DEPLOY_USER" ]]; then
  usage
  exit 1
fi

if [[ ! -d "$SOURCE" ]]; then
  echo "[ERROR] Source no existe: $SOURCE" >&2
  exit 1
fi

if [[ -z "$WEB_DEPLOY_BASE" ]]; then
  WEB_DEPLOY_BASE="/home/$DEPLOY_USER/deploy/sites"
fi

if [[ -z "$WEB_ROOT_BASE" ]]; then
  WEB_ROOT_BASE="/var/www/sites"
fi

RELEASES_DIR="$WEB_DEPLOY_BASE/releases"
WEB_ROOT="$WEB_ROOT_BASE/$SITE_NAME"
CURRENT_LINK="$WEB_ROOT/current"
RELEASE_NAME="release_$(date +%Y%m%d_%H%M%S)"
TARGET_RELEASE="$RELEASES_DIR/$RELEASE_NAME"

sudo mkdir -p "$TARGET_RELEASE" "$WEB_ROOT"
sudo rsync -a --delete "$SOURCE/" "$TARGET_RELEASE/"
sudo chown -R root:root "$TARGET_RELEASE"
sudo find "$TARGET_RELEASE" -type d -exec chmod 755 {} +
sudo find "$TARGET_RELEASE" -type f -exec chmod 644 {} +
sudo ln -sfn "$TARGET_RELEASE" "$CURRENT_LINK"

sudo nginx -t
sudo systemctl reload nginx

if sudo -u "$DEPLOY_USER" pm2 list >/dev/null 2>&1; then
  sudo -u "$DEPLOY_USER" pm2 reload all >/dev/null 2>&1 || true
fi

echo "[OK] Sitio desplegado en $CURRENT_LINK"
SCRIPT

run_as_root install -m 0755 "$TMP_HELPER" /usr/local/bin/deploy-static-site
rm -f "$TMP_HELPER"

log_step "Creando sitio inicial (starter)"
STARTER_DIR="$INCOMING_DIR/starter-site"
run_as_root mkdir -p "$STARTER_DIR"

TMP_INDEX="$(mktemp)"
cat > "$TMP_INDEX" <<'HTML'
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Servidor listo</title>
  <link rel="stylesheet" href="/style.css">
</head>
<body>
  <main class="wrap">
    <h1>Servidor web listo</h1>
    <p>Sube tu carpeta estatica y ejecuta deploy-static-site.</p>
    <button id="ping">Verificar JS</button>
    <p id="out"></p>
  </main>
  <script src="/app.js"></script>
</body>
</html>
HTML

TMP_CSS="$(mktemp)"
cat > "$TMP_CSS" <<'CSS'
:root {
  --bg: #f4f7ff;
  --panel: #ffffff;
  --ink: #1b263b;
  --accent: #0f766e;
}
body {
  margin: 0;
  font-family: "Segoe UI", Tahoma, Geneva, Verdana, sans-serif;
  background: radial-gradient(circle at top right, #dbeafe, var(--bg));
  color: var(--ink);
}
.wrap {
  max-width: 720px;
  margin: 10vh auto;
  background: var(--panel);
  border-radius: 14px;
  padding: 28px;
  box-shadow: 0 12px 34px rgba(15, 23, 42, 0.1);
}
button {
  border: 0;
  background: var(--accent);
  color: #fff;
  padding: 10px 14px;
  border-radius: 8px;
  cursor: pointer;
}
CSS

TMP_JS="$(mktemp)"
cat > "$TMP_JS" <<'JS'
const btn = document.getElementById("ping");
const out = document.getElementById("out");
btn?.addEventListener("click", () => {
  const now = new Date().toISOString();
  if (out) {
    out.textContent = `JS listo. Hora del servidor-cliente: ${now}`;
  }
});
JS

run_as_root install -m 0644 "$TMP_INDEX" "$STARTER_DIR/index.html"
run_as_root install -m 0644 "$TMP_CSS" "$STARTER_DIR/style.css"
run_as_root install -m 0644 "$TMP_JS" "$STARTER_DIR/app.js"
rm -f "$TMP_INDEX" "$TMP_CSS" "$TMP_JS"

log_step "Configurando Nginx para sitio estatico"
PHP_FPM_SOCK="$(ls /run/php/php*-fpm.sock 2>/dev/null | head -n1 || true)"
if [[ -z "$PHP_FPM_SOCK" ]]; then
  log_error "No se encontro socket de PHP-FPM en /run/php."
  exit 1
fi

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

run_as_root install -m 0644 "$TMP_NGINX" "/etc/nginx/sites-available/$WEB_SITE_NAME.conf"
rm -f "$TMP_NGINX"
run_as_root ln -sfn "/etc/nginx/sites-available/$WEB_SITE_NAME.conf" "/etc/nginx/sites-enabled/$WEB_SITE_NAME.conf"
if [[ -f "/etc/nginx/sites-enabled/default" ]]; then
  run_as_root rm -f /etc/nginx/sites-enabled/default
fi

log_step "Hardening de SSH, UFW y Fail2Ban"
TMP_SSH="$(mktemp)"
cat > "$TMP_SSH" <<'SSHCFG'
PermitRootLogin no
PasswordAuthentication no
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
SSHCFG
run_as_root install -m 0644 "$TMP_SSH" /etc/ssh/sshd_config.d/99-web-stack-hardening.conf
rm -f "$TMP_SSH"

run_as_root ufw --force reset
run_as_root ufw default deny incoming
run_as_root ufw default allow outgoing
run_as_root ufw allow 22/tcp
run_as_root ufw allow 80/tcp
run_as_root ufw allow 443/tcp
run_as_root ufw --force enable

TMP_FAIL2BAN="$(mktemp)"
cat > "$TMP_FAIL2BAN" <<'JAIL'
[sshd]
enabled = true
maxretry = 5
findtime = 10m
bantime = 30m

[nginx-http-auth]
enabled = true
JAIL
run_as_root install -m 0644 "$TMP_FAIL2BAN" /etc/fail2ban/jail.d/web-stack.local
rm -f "$TMP_FAIL2BAN"
run_as_root systemctl enable fail2ban
run_as_root systemctl restart fail2ban

log_step "Habilitando actualizaciones de seguridad"
run_as_root dpkg-reconfigure -f noninteractive unattended-upgrades || true

log_step "Inicializando PM2 para el usuario de despliegue"
run_as_root env PATH="$PATH" pm2 startup systemd -u "$DEPLOY_USER" --hp "/home/$DEPLOY_USER" || true
run_as_user "$DEPLOY_USER" pm2 save --force || true

log_step "Publicando starter inicial"
/usr/local/bin/deploy-static-site \
  --source "$STARTER_DIR" \
  --site-name "$WEB_SITE_NAME" \
  --deploy-user "$DEPLOY_USER" \
  --deploy-base "$WEB_DEPLOY_BASE" \
  --web-root-base "$WEB_ROOT_BASE"

log_step "Validaciones finales"
run_as_root nginx -t
run_as_root systemctl enable nginx
run_as_root systemctl restart nginx
php_fpm_service="$(systemctl list-unit-files 'php*-fpm.service' --no-legend 2>/dev/null | awk '{print $1}' | head -n1 || true)"
if [[ -n "$php_fpm_service" ]]; then
  run_as_root systemctl enable "$php_fpm_service"
  run_as_root systemctl restart "$php_fpm_service"
fi
run_as_root systemctl status nginx --no-pager >/dev/null
run_as_root systemctl status mysql --no-pager >/dev/null
run_as_root systemctl status fail2ban --no-pager >/dev/null

log_info "Bootstrap finalizado."
log_info "Carpeta para subir nuevos sitios: $INCOMING_DIR"
log_info "Comando de deploy rapido: deploy-static-site --source <tu-carpeta> --site-name $WEB_SITE_NAME --deploy-user $DEPLOY_USER"
log_info "PM2 instalado y listo. Si no hay procesos, pm2 reload no hara cambios."
