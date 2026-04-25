#!/usr/bin/env bash
set -euo pipefail

log_info() {
  echo "[INFO] $1"
}

log_error() {
  echo "[ERROR] $1" >&2
}

normalize_env_value() {
  local value="$1"

  # Quita CR cuando el .env fue creado con finales de linea Windows (CRLF).
  value="${value%$'\r'}"

  # Quita comillas envolventes simples o dobles en caso de que existan.
  if [[ "$value" =~ ^".*"$ ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" =~ ^\'.*\'$ ]]; then
    value="${value:1:${#value}-2}"
  fi

  printf '%s' "$value"
}

ENV_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    *)
      log_error "Parametro no soportado: $1"
      exit 1
      ;;
  esac
done

if [[ -n "$ENV_FILE" ]]; then
  if [[ ! -f "$ENV_FILE" ]]; then
    log_error "No existe archivo de entorno: $ENV_FILE"
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

DB_NAME="$(normalize_env_value "${MYSQL_DB_NAME:-school}")"
ADMIN_USER="$(normalize_env_value "${MYSQL_ADMIN_USER:-admin}")"
ADMIN_PASSWORD="$(normalize_env_value "${MYSQL_ADMIN_PASSWORD:-}")"
GESTION_USER="$(normalize_env_value "${MYSQL_GESTION_USER:-gestion}")"
GESTION_PASSWORD="$(normalize_env_value "${MYSQL_GESTION_PASSWORD:-}")"

if [[ ! "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]]; then
  log_error "MYSQL_DB_NAME invalido: '$DB_NAME'. Usa solo letras, numeros y guion bajo."
  exit 1
fi

if [[ ! "$ADMIN_USER" =~ ^[A-Za-z0-9_]+$ ]]; then
  log_error "MYSQL_ADMIN_USER invalido: '$ADMIN_USER'. Usa solo letras, numeros y guion bajo."
  exit 1
fi

if [[ ! "$GESTION_USER" =~ ^[A-Za-z0-9_]+$ ]]; then
  log_error "MYSQL_GESTION_USER invalido: '$GESTION_USER'. Usa solo letras, numeros y guion bajo."
  exit 1
fi

if [[ -z "$ADMIN_PASSWORD" || -z "$GESTION_PASSWORD" ]]; then
  log_error "Debes definir MYSQL_ADMIN_PASSWORD y MYSQL_GESTION_PASSWORD en el env file."
  exit 1
fi

if [[ "$ADMIN_PASSWORD" == "CHANGE_ME" || "$GESTION_PASSWORD" == "CHANGE_ME" ]]; then
  log_error "Actualiza las contrasenas del env file (no uses CHANGE_ME)."
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  log_error "sudo no esta disponible en la VM."
  exit 1
fi

log_info "Instalando MySQL Server (idempotente)..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
sudo systemctl enable mysql
sudo systemctl start mysql

log_info "Aplicando hardening equivalente a mysql_secure_installation..."
sudo mysql <<SQL
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL

log_info "Creando base, tablas, usuarios y privilegios..."
sudo mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
USE \`$DB_NAME\`;

CREATE TABLE IF NOT EXISTS teachers (
  ID INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(50) NOT NULL,
  age INT,
  email VARCHAR(100) NOT NULL,
  pass VARCHAR(32) NOT NULL
);

CREATE TABLE IF NOT EXISTS students (
  ID INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(50) NOT NULL,
  age INT,
  grade INT
);

CREATE USER IF NOT EXISTS '$ADMIN_USER'@'localhost' IDENTIFIED BY '$ADMIN_PASSWORD';
ALTER USER '$ADMIN_USER'@'localhost' IDENTIFIED BY '$ADMIN_PASSWORD';

CREATE USER IF NOT EXISTS '$GESTION_USER'@'localhost' IDENTIFIED BY '$GESTION_PASSWORD';
ALTER USER '$GESTION_USER'@'localhost' IDENTIFIED BY '$GESTION_PASSWORD';

GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$ADMIN_USER'@'localhost';
GRANT INSERT, SELECT ON \`$DB_NAME\`.students TO '$GESTION_USER'@'localhost';
GRANT INSERT, SELECT ON \`$DB_NAME\`.teachers TO '$GESTION_USER'@'localhost';
FLUSH PRIVILEGES;
SQL

log_info "Verificando instalacion de BD..."
sudo mysql -e "SHOW DATABASES LIKE '$DB_NAME';"

log_info "Listo. BD school provisionada correctamente."
