# 🌐 Diagnóstico: Modelo de Despliegue de Nube
**Team Iron Cloud**

Aplicación web de diagnóstico que, a través de 10 preguntas, recomienda el modelo de nube más adecuado para una organización: **Nube Pública**, **Nube Híbrida** o **Nube Privada**.

---

## Estructura del Proyecto

```
proyecto_nube/
├── index.html              # Interfaz principal del quiz
├── css/
│   └── styles.css          # Estilos (tema terminal / cyberpunk)
├── js/
│   └── main.js             # Lógica del frontend (validación, envío, resultados)
├── api/
│   └── submit.php          # Backend: valida respuestas, calcula recomendación y guarda en BD
├── config/
│   └── db.php              # Conexión PDO a MySQL/MariaDB
└── quiz_db_final.sql       # Esquema completo de la base de datos
```

---

## Requisitos

| Herramienta | Versión mínima |
|-------------|----------------|
| XAMPP       | 8.x (incluye PHP 8+ y MariaDB) |
| Navegador   | Chrome, Firefox, Edge (moderno) |

---

## Instalación paso a paso

### 1. Copiar el proyecto
Coloca la carpeta `proyecto_nube` dentro de:
```
C:\xampp\htdocs\
```

### 2. Crear la base de datos
1. Abre **XAMPP Control Panel** e inicia **Apache** y **MySQL**.
2. Abre tu navegador y ve a: `http://localhost/phpmyadmin`
3. En el menú lateral haz clic en **Nueva** (para crear BD) — o directamente ve a la pestaña **SQL**.
4. Copia y pega el contenido del archivo `quiz_db_final.sql` en el editor SQL y ejecuta.

   > Esto crea automáticamente la BD `quiz_db`, las tablas `recomendaciones` e `intentos`, carga los 3 datos de recomendaciones y crea la vista `vista_intentos`.

   **Alternativa por terminal:**
   ```bash
   mysql -u root -p < C:\xampp\htdocs\proyecto_nube\quiz_db_final.sql
   ```

### 3. Verificar la conexión
Abre `config/db.php` y confirma que los datos coincidan con tu XAMPP:

```php
$host = 'localhost';
$db   = 'quiz_db';
$user = 'root';
$pass = '';          // En XAMPP local la contraseña es vacía por defecto
```

### 4. Abrir la aplicación
Con Apache activo, abre en el navegador:
```
http://localhost/proyecto_nube/
```

---

## Cómo funciona

### Flujo general

```
Usuario responde 10 preguntas
        ↓
Validación en el navegador (main.js)
        ↓
POST JSON → api/submit.php
        ↓
Motor de recomendación (PHP)
        ↓
Guarda en BD (tabla intentos)
        ↓
Devuelve JSON con la recomendación
        ↓
Frontend muestra tarjeta de resultado
```

### Motor de recomendación
Las respuestas se clasifican en 4 perfiles (a, b, c, d) y se aplican estas reglas **en orden**:

| Recomendación | Condición |
|---------------|-----------|
| 🏛 **Nube Privada** | ≥ 6 respuestas C+D **y** preguntas 1, 3, 5 respondidas con C o D |
| 🔀 **Nube Híbrida** | ≥ 5 respuestas B+C **y** (pregunta 4 = C **o** pregunta 10 = C/D) |
| 🌐 **Nube Pública** | Por defecto (si ninguna regla anterior aplica) |

La misma lógica existe en `main.js` (vista previa en tiempo real desde la pregunta 5) y en `submit.php` (resultado final guardado en BD).

### Base de datos

**`recomendaciones`** — Catálogo con los 3 tipos de nube (datos fijos).

**`intentos`** — Un registro por cada envío del formulario:

| Campo | Descripción |
|-------|-------------|
| `equipo` | Nombre del equipo |
| `ip_cliente` | IP del usuario |
| `recomendacion_id` | Qué tipo de nube se recomendó |
| `conteo_a/b/c/d` | Cuántas veces eligió cada opción |
| `creado_en` | Fecha y hora del envío |

**`vista_intentos`** — Vista que une `intentos` con `recomendaciones` para reportes rápidos.

---

## Integrantes

| ID | Nombre | Rol |
|----|--------|-----|
| @dev_01 | Bustillos Cruz Jonatan | Máquina Virtual |
| @dev_02 | Enríquez Miranda Leonardo Andrés | Backend Dev |
| @dev_03 | Frem Cortés José Angel | Frontend Dev |
| @dev_04 | Posadas Villegas Octavio | Documentación |
| @dev_05 | Yañez Torres Ethan Axel | Documentación |
