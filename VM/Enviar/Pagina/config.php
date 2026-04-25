<?php
declare(strict_types=1);

const APP_ENV_FILE = '/home/joni/deploy/school/db-school.env';

function parseEnvFile(string $envPath): array
{
    if (!is_file($envPath)) {
        throw new RuntimeException("No existe el archivo de entorno: $envPath");
    }

    $lines = file($envPath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if ($lines === false) {
        throw new RuntimeException("No se pudo leer el archivo de entorno: $envPath");
    }

    $values = [];
    foreach ($lines as $line) {
        $line = trim($line);
        if ($line === '' || str_starts_with($line, '#')) {
            continue;
        }

        $parts = explode('=', $line, 2);
        if (count($parts) !== 2) {
            continue;
        }

        $key = trim($parts[0]);
        $value = trim($parts[1]);
        $value = trim($value, "\"'");

        if ($key !== '') {
            $values[$key] = $value;
        }
    }

    return $values;
}

function getDbConfig(): array
{
    static $config = null;

    if (is_array($config)) {
        return $config;
    }

    $env = parseEnvFile(APP_ENV_FILE);

    $host = trim((string)($env['MYSQL_DB_HOST'] ?? 'localhost'));
    $name = trim((string)($env['MYSQL_DB_NAME'] ?? ''));
    $user = trim((string)($env['MYSQL_ADMIN_USER'] ?? ''));
    $pass = (string)($env['MYSQL_ADMIN_PASSWORD'] ?? '');

    if ($name === '' || $user === '' || $pass === '') {
        throw new RuntimeException('Faltan MYSQL_DB_NAME, MYSQL_ADMIN_USER o MYSQL_ADMIN_PASSWORD en el env file.');
    }

    $config = [
        'host' => $host,
        'name' => $name,
        'user' => $user,
        'pass' => $pass,
    ];

    return $config;
}

function getPdoConnection(): PDO
{
    static $pdo = null;

    if ($pdo instanceof PDO) {
        return $pdo;
    }

    $cfg = getDbConfig();
    $dsn = 'mysql:host=' . $cfg['host'] . ';dbname=' . $cfg['name'] . ';charset=utf8mb4';

    $pdo = new PDO(
        $dsn,
        $cfg['user'],
        $cfg['pass'],
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]
    );

    return $pdo;
}
