<?php
declare(strict_types=1);

session_start();
require_once __DIR__ . '/config.php';

if (!isset($_SESSION['csrf_token'])) {
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
}

$errors = [];
$success = '';
$dbUnavailable = false;

function textLength(string $value): int
{
    if (function_exists('mb_strlen')) {
        return mb_strlen($value);
    }

    return strlen($value);
}

try {
    getPdoConnection();
} catch (Throwable $e) {
    $dbUnavailable = true;
    $errors[] = 'No hay conexion a la base de datos en este momento. Verifica despliegue y env file.';
}

$teacherData = [
    'name' => '',
    'age' => '',
    'email' => '',
    'pass' => '',
];

$studentData = [
    'name' => '',
    'age' => '',
    'grade' => '',
];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if ($dbUnavailable) {
        $errors[] = 'No se puede procesar el formulario sin conexion a MySQL.';
    }

    $formType = $_POST['form_type'] ?? '';
    $token = $_POST['csrf_token'] ?? '';

    if (!hash_equals($_SESSION['csrf_token'], $token)) {
        $errors[] = 'Token CSRF invalido. Recarga la pagina e intenta de nuevo.';
    }

    if ($formType === 'teacher' && !$dbUnavailable) {
        $teacherData['name'] = trim((string) ($_POST['teacher_name'] ?? ''));
        $teacherData['age'] = trim((string) ($_POST['teacher_age'] ?? ''));
        $teacherData['email'] = trim((string) ($_POST['teacher_email'] ?? ''));
        $teacherData['pass'] = trim((string) ($_POST['teacher_pass'] ?? ''));

        if ($teacherData['name'] === '') {
            $errors[] = 'El nombre del teacher es obligatorio.';
        } elseif (textLength($teacherData['name']) > 50) {
            $errors[] = 'El nombre del teacher no puede superar 50 caracteres.';
        }

        if ($teacherData['age'] !== '' && filter_var($teacherData['age'], FILTER_VALIDATE_INT) === false) {
            $errors[] = 'La edad del teacher debe ser un numero entero.';
        }

        if ($teacherData['email'] === '') {
            $errors[] = 'El email del teacher es obligatorio.';
        } elseif (!filter_var($teacherData['email'], FILTER_VALIDATE_EMAIL)) {
            $errors[] = 'El email del teacher no es valido.';
        } elseif (textLength($teacherData['email']) > 100) {
            $errors[] = 'El email del teacher no puede superar 100 caracteres.';
        }

        if ($teacherData['pass'] === '') {
            $errors[] = 'El campo pass del teacher es obligatorio.';
        } elseif (textLength($teacherData['pass']) > 32) {
            $errors[] = 'El campo pass del teacher no puede superar 32 caracteres.';
        }

        if (empty($errors)) {
            try {
                $pdo = getPdoConnection();
                $stmt = $pdo->prepare('INSERT INTO teachers (name, age, email, pass) VALUES (:name, :age, :email, :pass)');
                $stmt->execute([
                    ':name' => $teacherData['name'],
                    ':age' => $teacherData['age'] === '' ? null : (int) $teacherData['age'],
                    ':email' => $teacherData['email'],
                    ':pass' => $teacherData['pass'],
                ]);

                $success = 'Teacher guardado correctamente.';
                $teacherData = ['name' => '', 'age' => '', 'email' => '', 'pass' => ''];
            } catch (PDOException $e) {
                $errors[] = 'No se pudo guardar el teacher. Verifica conexion, tabla y datos.';
            }
        }
    } elseif ($formType === 'student' && !$dbUnavailable) {
        $studentData['name'] = trim((string) ($_POST['student_name'] ?? ''));
        $studentData['age'] = trim((string) ($_POST['student_age'] ?? ''));
        $studentData['grade'] = trim((string) ($_POST['student_grade'] ?? ''));

        if ($studentData['name'] === '') {
            $errors[] = 'El nombre del student es obligatorio.';
        } elseif (textLength($studentData['name']) > 50) {
            $errors[] = 'El nombre del student no puede superar 50 caracteres.';
        }

        if ($studentData['age'] !== '' && filter_var($studentData['age'], FILTER_VALIDATE_INT) === false) {
            $errors[] = 'La edad del student debe ser un numero entero.';
        }

        if ($studentData['grade'] !== '' && filter_var($studentData['grade'], FILTER_VALIDATE_INT) === false) {
            $errors[] = 'El grade del student debe ser un numero entero.';
        }

        if (empty($errors)) {
            try {
                $pdo = getPdoConnection();
                $stmt = $pdo->prepare('INSERT INTO students (name, age, grade) VALUES (:name, :age, :grade)');
                $stmt->execute([
                    ':name' => $studentData['name'],
                    ':age' => $studentData['age'] === '' ? null : (int) $studentData['age'],
                    ':grade' => $studentData['grade'] === '' ? null : (int) $studentData['grade'],
                ]);

                $success = 'Student guardado correctamente.';
                $studentData = ['name' => '', 'age' => '', 'grade' => ''];
            } catch (PDOException $e) {
                $errors[] = 'No se pudo guardar el student. Verifica conexion, tabla y datos.';
            }
        }
    } elseif (!$dbUnavailable) {
        $errors[] = 'Formulario no reconocido.';
    }
}
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>School App - Teachers y Students</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <main class="page">
        <header class="hero">
            <p class="eyebrow">Practica PHP + MySQL</p>
            <h1>Registro de Teachers y Students</h1>
            <p>Usa los formularios para insertar datos directamente en las tablas de <strong>school</strong>.</p>
        </header>

        <?php if (!empty($errors)): ?>
            <section class="panel error" aria-live="polite">
                <h2>Errores</h2>
                <ul>
                    <?php foreach ($errors as $error): ?>
                        <li><?= htmlspecialchars($error, ENT_QUOTES, 'UTF-8') ?></li>
                    <?php endforeach; ?>
                </ul>
            </section>
        <?php endif; ?>

        <?php if ($success !== ''): ?>
            <section class="panel success" aria-live="polite">
                <p><?= htmlspecialchars($success, ENT_QUOTES, 'UTF-8') ?></p>
            </section>
        <?php endif; ?>

        <section class="grid">
            <article class="card">
                <h2>Formulario Teachers</h2>
                <form method="post" novalidate>
                    <input type="hidden" name="form_type" value="teacher">
                    <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($_SESSION['csrf_token'], ENT_QUOTES, 'UTF-8') ?>">

                    <label for="teacher_name">Name *</label>
                    <input id="teacher_name" name="teacher_name" type="text" maxlength="50" required value="<?= htmlspecialchars($teacherData['name'], ENT_QUOTES, 'UTF-8') ?>">

                    <label for="teacher_age">Age</label>
                    <input id="teacher_age" name="teacher_age" type="number" value="<?= htmlspecialchars($teacherData['age'], ENT_QUOTES, 'UTF-8') ?>">

                    <label for="teacher_email">Email *</label>
                    <input id="teacher_email" name="teacher_email" type="email" maxlength="100" required value="<?= htmlspecialchars($teacherData['email'], ENT_QUOTES, 'UTF-8') ?>">

                    <label for="teacher_pass">Pass *</label>
                    <input id="teacher_pass" name="teacher_pass" type="text" maxlength="32" required value="<?= htmlspecialchars($teacherData['pass'], ENT_QUOTES, 'UTF-8') ?>">

                    <button type="submit">Guardar Teacher</button>
                </form>
            </article>

            <article class="card">
                <h2>Formulario Students</h2>
                <form method="post" novalidate>
                    <input type="hidden" name="form_type" value="student">
                    <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($_SESSION['csrf_token'], ENT_QUOTES, 'UTF-8') ?>">

                    <label for="student_name">Name *</label>
                    <input id="student_name" name="student_name" type="text" maxlength="50" required value="<?= htmlspecialchars($studentData['name'], ENT_QUOTES, 'UTF-8') ?>">

                    <label for="student_age">Age</label>
                    <input id="student_age" name="student_age" type="number" value="<?= htmlspecialchars($studentData['age'], ENT_QUOTES, 'UTF-8') ?>">

                    <label for="student_grade">Grade</label>
                    <input id="student_grade" name="student_grade" type="number" value="<?= htmlspecialchars($studentData['grade'], ENT_QUOTES, 'UTF-8') ?>">

                    <button type="submit">Guardar Student</button>
                </form>
            </article>
        </section>
    </main>
</body>
</html>
