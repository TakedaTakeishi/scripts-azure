<?php
// ============================================================
// api/submit.php — Quiz con motor de recomendaciones
// ============================================================
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['ok'=>false,'error'=>'Método no permitido.']);
    exit;
}

require_once __DIR__ . '/../config/db.php';

const TOTAL_PREGUNTAS = 10;
const EQUIPO          = 'Team Alpha';

// ============================================================
// MOTOR DE RECOMENDACIÓN
// Reglas evaluadas en orden — gana la primera que se cumple.
//
// PRIVADA  : mayoría de C+D (>=6) Y Q1,Q3,Q5 = c|d
// HÍBRIDA  : mezcla B+C (>=5)    Y (Q4=c  O  Q10=c|d)
// PÚBLICA  : default (domina A o no se cumplió otra regla)
// ============================================================
function calcularRecomendacion(array $resp): string
{
    $cnt = ['a'=>0,'b'=>0,'c'=>0,'d'=>0];
    foreach ($resp as $v) $cnt[$v] = ($cnt[$v]??0)+1;

    $mayoriaCD  = ($cnt['c'] + $cnt['d']) >= 6;
    $mayoriaBC  = ($cnt['b'] + $cnt['c']) >= 5;

    $claveOnPrem = in_array($resp[1]??'', ['c','d'])
                && in_array($resp[3]??'', ['c','d'])
                && in_array($resp[5]??'', ['c','d']);

    $claveHibrida = ($resp[4]??'') === 'c'
                 || in_array($resp[10]??'', ['c','d']);

    if ($mayoriaCD && $claveOnPrem) return 'privada';
    if ($mayoriaBC && $claveHibrida) return 'hibrida';
    return 'publica';
}

// ============================================================
// Validar input
// ============================================================
$raw = file_get_contents('php://input');
if (empty($raw)) {
    http_response_code(400);
    echo json_encode(['ok'=>false,'error'=>'Body vacío.']);
    exit;
}
$data = json_decode($raw, true);
if (json_last_error() !== JSON_ERROR_NONE) {
    http_response_code(400);
    echo json_encode(['ok'=>false,'error'=>'JSON inválido.']);
    exit;
}

$errores = [];
$respuestas_usuario = [];
for ($i = 1; $i <= TOTAL_PREGUNTAS; $i++) {
    $key = "q{$i}";
    if (!isset($data[$key]) || $data[$key] === '') { $errores[] = "Pregunta {$i} sin responder."; continue; }
    $v = strtolower(trim($data[$key]));
    if (!in_array($v, ['a','b','c','d'], true)) { $errores[] = "Pregunta {$i}: valor inválido."; continue; }
    $respuestas_usuario[$i] = $v;
}
if (!empty($errores)) {
    http_response_code(422);
    echo json_encode(['ok'=>false,'errores'=>$errores]);
    exit;
}

// ============================================================
// Conteo de opciones seleccionadas
// ============================================================
$conteos = ['a'=>0,'b'=>0,'c'=>0,'d'=>0];
foreach ($respuestas_usuario as $v) $conteos[$v]++;

// ============================================================
// Recomendación
// ============================================================
$clave_rec = calcularRecomendacion($respuestas_usuario);

// ============================================================
// BD
// ============================================================
$ip = substr($_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? 'desconocida', 0, 45);
$ua = substr($_SERVER['HTTP_USER_AGENT'] ?? '', 0, 255);

try {
    $pdo = getDB();

    $stmtRec = $pdo->prepare("SELECT id,titulo,perfil,razon,tecnologias,icono,color_hex FROM recomendaciones WHERE clave=:c");
    $stmtRec->execute([':c'=>$clave_rec]);
    $rec = $stmtRec->fetch();
    if (!$rec) { http_response_code(500); echo json_encode(['ok'=>false,'error'=>"Recomendación no encontrada."]); exit; }

    $stmt = $pdo->prepare("
        INSERT INTO intentos (equipo,ip_cliente,user_agent,recomendacion_id,conteo_a,conteo_b,conteo_c,conteo_d)
        VALUES (:eq,:ip,:ua,:ri,:ca,:cb,:cc,:cd)
    ");
    $stmt->execute([':eq'=>EQUIPO,':ip'=>$ip,':ua'=>$ua,':ri'=>$rec['id'],
        ':ca'=>$conteos['a'],':cb'=>$conteos['b'],':cc'=>$conteos['c'],':cd'=>$conteos['d']]);
    $intento_id = (int)$pdo->lastInsertId();

} catch (PDOException $e) {
    error_log('[quiz] '.$e->getMessage());
    http_response_code(500);
    echo json_encode(['ok'=>false,'error'=>'Error de base de datos.']);
    exit;
}

http_response_code(200);
echo json_encode([
    'ok'            => true,
    'intento_id'    => $intento_id,
    'conteos'       => $conteos,
    'recomendacion' => [
        'clave'       => $clave_rec,
        'titulo'      => $rec['titulo'],
        'perfil'      => $rec['perfil'],
        'razon'       => $rec['razon'],
        'tecnologias' => $rec['tecnologias'],
        'icono'       => $rec['icono'],
        'color'       => $rec['color_hex'],
    ],
]);
