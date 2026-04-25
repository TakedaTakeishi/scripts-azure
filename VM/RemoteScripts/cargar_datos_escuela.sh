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

log_step() {
  echo
  echo "=============================="
  echo "$1"
  echo "=============================="
}

ENV_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      # Validamos que exista un segundo argumento para evitar que shift falle
      if [[ -z "${2:-}" ]]; then
        log_error "Error: --env-file requiere un argumento (nombre del archivo)."
        exit 1
      fi
      ENV_FILE="$2"
      shift 2
      ;;
    *)
      log_error "Parametro no soportado: $1"
      exit 1
      ;;
  esac
done

# Carga del archivo de entorno
if [[ -n "$ENV_FILE" ]]; then
  if [[ ! -f "$ENV_FILE" ]]; then
    log_error "No existe archivo de entorno: $ENV_FILE"
    exit 1
  fi

  log_info "Cargando variables desde $ENV_FILE..."
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

DB_NAME="$(normalize_env_value "${MYSQL_DB_NAME:-school}")"
DB_HOST="$(normalize_env_value "${MYSQL_DB_HOST:-localhost}")"
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

admin_sql() {
  MYSQL_PWD="$ADMIN_PASSWORD" mysql -u "$ADMIN_USER" -h "$DB_HOST" -D "$DB_NAME" --table -e "$1"
}

gestion_sql() {
  MYSQL_PWD="$GESTION_PASSWORD" mysql -u "$GESTION_USER" -h "$DB_HOST" -D "$DB_NAME" --table -e "$1"
}

insert_teacher_if_missing() {
  local name="$1"
  local age="$2"
  local email="$3"
  local pass_hash="$4"

  admin_sql "INSERT INTO teachers (name, age, email, pass)
SELECT '$name', $age, '$email', '$pass_hash'
WHERE NOT EXISTS (
  SELECT 1 FROM teachers WHERE email = '$email'
);"
}

insert_student_if_missing() {
  local name="$1"
  local age="$2"
  local grade="$3"

  gestion_sql "INSERT INTO students (name, age, grade)
SELECT '$name', $age, $grade
WHERE NOT EXISTS (
  SELECT 1 FROM students WHERE name = '$name' AND age = $age AND grade = $grade
);"
}

log_info "Probando conexion con usuario admin..."
admin_sql "SELECT 'admin conectado' AS estado;" >/dev/null

log_info "Probando conexion con usuario gestion..."
gestion_sql "SELECT 'gestion conectado' AS estado;" >/dev/null

log_step "Paso 9: Insertar 4 teachers con admin"
insert_teacher_if_missing "John Smith" 35 "john.smith@example.com" "32a7f64e4c7d6e5efacca2ec9c7c8f7b"
insert_teacher_if_missing "Sarah Johnson" 28 "sarah.johnson@example.com" "a8e8e726dff1e57c93a4387b4e64898b"
insert_teacher_if_missing "Michael Brown" 40 "michael.brown@example.com" "9d6b7e10dd4b7b22fddfda46693332d9"
insert_teacher_if_missing "Emily Davis" 33 "emily.davis@example.com" "8c1d09738c34872b686334566173786b"
admin_sql "SELECT ID, name, age, email, pass FROM teachers ORDER BY ID;"


log_step "Paso 11: Insertar 1 teacher con gestion"
gestion_sql "INSERT INTO teachers (name, age, email, pass)
SELECT 'William Lee', 45, 'william.lee@example.com', '5f634cbe4a2769c3f7b3b8b7a4b6c8b0'
WHERE NOT EXISTS (
  SELECT 1 FROM teachers WHERE email = 'william.lee@example.com'
);"
gestion_sql "SELECT ID, name, age, email, pass FROM teachers ORDER BY ID;"

log_step "Paso 13: Insertar 5 students con gestion"
insert_student_if_missing "Emma Johnson" 14 9
insert_student_if_missing "Liam Smith" 15 10
insert_student_if_missing "Olivia Brown" 16 11
insert_student_if_missing "Noah Davis" 14 9
insert_student_if_missing "Sophia Lee" 15 10
gestion_sql "SELECT ID, name, age, grade FROM students ORDER BY ID;"

log_step "Paso 15: Query gestion (grade >= 10)"
gestion_sql "SELECT ID, name, age, grade FROM students WHERE grade >= 10 ORDER BY grade, name;"

log_step "Paso 17: Query admin (teachers <= 35)"
admin_sql "SELECT ID, name, age, email FROM teachers WHERE age <= 35 ORDER BY age, name;"

log_info "Listo. Toma captura de cada bloque de salida para tu evidencia."
