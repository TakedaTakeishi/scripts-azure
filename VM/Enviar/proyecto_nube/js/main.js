/* ============================================================
   main.js — Quiz con recomendación en tiempo real
   ============================================================ */

const API_URL = 'api/submit.php';
const TOTAL   = 10;

// ── Catálogo de recomendaciones (lógica espejo del PHP) ──────
// Se usa para mostrar la sugerencia ANTES de enviar (en vivo).
// El PHP es la fuente de verdad final al guardar en BD.
const RECOMENDACIONES = {
  publica: {
    titulo:      'Nube Pública',
    subtitulo:   'Public Cloud',
    icono:       '🌐',
    color:       '#00d4ff',
    perfil:      'Startups, PYMES o empresas digitales modernas.',
    razon:       'Buscan agilidad, bajo costo inicial (OpEx), elasticidad para picos impredecibles y no tienen restricciones legales fuertes ni equipos grandes de infraestructura.',
    tecnologias: 'AWS · Azure · Google Cloud — PaaS y Serverless.',
  },
  hibrida: {
    titulo:      'Nube Híbrida',
    subtitulo:   'Hybrid Cloud',
    icono:       '🔀',
    color:       '#f0c040',
    perfil:      'Grandes corporativos, Banca, Retail con sucursales.',
    razon:       'Tienen sistemas heredados (Legacy) que no pueden mover fácilmente, pero necesitan la agilidad de la nube para aplicaciones nuevas. Core en sitio + nuevas apps en Nube Pública vía VPN/Interconnect.',
    tecnologias: 'Azure Arc · AWS Outposts · VMware Cloud Foundation.',
  },
  privada: {
    titulo:      'Nube Privada',
    subtitulo:   'On-Premises / Private Cloud',
    icono:       '🏛',
    color:       '#39d353',
    perfil:      'Gobierno, Defensa, Salud, Industria pesada.',
    razon:       'La regulación, la latencia ultra-baja o la depreciación de activos ya comprados hacen que la nube pública sea inviable o más cara.',
    tecnologias: 'Hiperconvergencia (HCI) · OpenStack · Nutanix · VMware vSphere.',
  },
};

// ── Motor de recomendación (espejo de la lógica PHP) ─────────
function calcularRecomendacion(resp) {
  const cnt = { a:0, b:0, c:0, d:0 };
  Object.values(resp).forEach(v => { if (cnt[v] !== undefined) cnt[v]++; });

  const mayoriaCD  = (cnt.c + cnt.d) >= 6;
  const mayoriaBC  = (cnt.b + cnt.c) >= 5;

  const claveOnPrem = ['c','d'].includes(resp.q1||'')
                   && ['c','d'].includes(resp.q3||'')
                   && ['c','d'].includes(resp.q5||'');

  const claveHibrida = (resp.q4||'') === 'c'
                    || ['c','d'].includes(resp.q10||'');

  if (mayoriaCD && claveOnPrem) return 'privada';
  if (mayoriaBC && claveHibrida) return 'hibrida';
  return 'publica';
}

// ── Recolectar respuestas actuales ───────────────────────────
function collectAnswers() {
  const a = {};
  for (let i = 1; i <= TOTAL; i++) {
    const c = document.querySelector(`input[name="q${i}"]:checked`);
    if (c) a[`q${i}`] = c.value;
  }
  return a;
}

// ============================================================
// RELOJ
// ============================================================
function updateClock() {
  const now = new Date();
  const p   = n => String(n).padStart(2,'0');
  document.getElementById('clock').textContent =
    `${p(now.getHours())}:${p(now.getMinutes())}:${p(now.getSeconds())}`;
}
setInterval(updateClock, 1000);
updateClock();

// ============================================================
// PROGRESO + RECOMENDACIÓN EN TIEMPO REAL
// ============================================================
function updateProgress() {
  let count = 0;
  for (let i = 1; i <= TOTAL; i++) {
    const block   = document.querySelector(`.question-block[data-q="${i}"]`);
    const checked = document.querySelector(`input[name="q${i}"]:checked`);
    if (!block) continue;
    block.classList.toggle('answered', !!checked);
    if (checked) { count++; block.classList.remove('has-error'); }
  }

  const pct = Math.round((count / TOTAL) * 100);
  document.getElementById('answered').textContent     = count;
  document.getElementById('progressFill').style.width = `${pct}%`;
  document.getElementById('sideAnswered').textContent = count;
  document.getElementById('sidePct').textContent      = `${pct}%`;
  document.getElementById('miniFill').style.width     = `${pct}%`;

  // Actualizar panel de recomendación en tiempo real
  updateRecomendacionWidget(count);
}

// ── Widget de recomendación en el sidebar ───────────────────
function updateRecomendacionWidget(count) {
  const widget = document.getElementById('recWidget');
  if (!widget) return;

  if (count < 5) {
    // Todavía pocas respuestas — mostrar estado neutro
    widget.innerHTML = `
      <div class="rec-pending">
        <span class="rec-wait-icon">◌</span>
        <span>Responde al menos 5 preguntas para ver tu recomendación…</span>
        <div class="rec-mini-bar">
          <div class="rec-mini-fill" style="width:${Math.round((count/TOTAL)*100)}%"></div>
        </div>
      </div>`;
    return;
  }

  const resp  = collectAnswers();
  const clave = calcularRecomendacion(resp);
  const rec   = RECOMENDACIONES[clave];

  widget.innerHTML = `
    <div class="rec-card" style="--rec-color:${rec.color}">
      <div class="rec-header">
        <span class="rec-icono">${rec.icono}</span>
        <div class="rec-titulos">
          <span class="rec-titulo">${rec.titulo}</span>
          <span class="rec-subtitulo">${rec.subtitulo}</span>
        </div>
        <span class="rec-badge">${count === TOTAL ? 'FINAL' : 'PARCIAL'}</span>
      </div>
      <div class="rec-body">
        <div class="rec-bloque">
          <span class="rec-label">// perfil</span>
          <p class="rec-text">${rec.perfil}</p>
        </div>
        <div class="rec-bloque">
          <span class="rec-label">// por qué</span>
          <p class="rec-text">${rec.razon}</p>
        </div>
        <div class="rec-bloque">
          <span class="rec-label">// tecnologías</span>
          <p class="rec-text rec-tech">${rec.tecnologias}</p>
        </div>
      </div>
    </div>`;
}

document.querySelectorAll('input[type="radio"]').forEach(r => {
  r.addEventListener('change', updateProgress);
});

// ============================================================
// VALIDACIÓN CLIENT-SIDE
// ============================================================
function validateForm() {
  let valid = true, firstError = null;
  for (let i = 1; i <= TOTAL; i++) {
    const block   = document.querySelector(`.question-block[data-q="${i}"]`);
    const checked = document.querySelector(`input[name="q${i}"]:checked`);
    if (!checked) {
      block.classList.add('has-error');
      if (!firstError) firstError = block;
      valid = false;
    } else {
      block.classList.remove('has-error');
    }
  }
  if (firstError) firstError.scrollIntoView({ behavior:'smooth', block:'center' });
  return valid;
}

// ============================================================
// ESTADO DEL BOTÓN
// ============================================================
function setLoading(loading) {
  const btn  = document.getElementById('submitBtn');
  const text = btn.querySelector('.btn-text');
  btn.disabled       = loading;
  text.textContent   = loading ? 'ENVIANDO...' : 'ENVIAR RESPUESTAS';
  btn.style.opacity  = loading ? '0.6' : '1';
}

// ============================================================
// SUBMIT → fetch al PHP
// ============================================================
document.getElementById('quizForm').addEventListener('submit', async function(e) {
  e.preventDefault();
  if (!validateForm()) return;
  setLoading(true);

  try {
    const response = await fetch(API_URL, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify(collectAnswers()),
    });
    const result = await response.json();

    if (!response.ok || !result.ok) {
      const msg = result.error || (result.errores ? result.errores.join('\n') : 'Error desconocido');
      showServerError(msg);
      setLoading(false);
      return;
    }

    showSuccess(result);

  } catch (err) {
    showServerError('No se pudo conectar con el servidor. Verifica que el backend esté activo.');
    setLoading(false);
  }
});

// ============================================================
// PANTALLA DE ÉXITO — usa datos reales del PHP
// ============================================================
function showSuccess(result) {
  const form    = document.getElementById('quizForm');
  const success = document.getElementById('successScreen');
  const rec     = result.recomendacion || {};
  const now     = new Date();

  // Bloque de código con stats
  const codeBlock = document.querySelector('.success-code');
  if (codeBlock) {
    codeBlock.innerHTML = `
      <span class="sc-line"><span class="sc-key">status</span>: <span class="sc-val">"200 OK"</span>,</span>
      <span class="sc-line"><span class="sc-key">intento_id</span>: <span class="sc-val">${result.intento_id ?? '-'}</span>,</span>
      <span class="sc-line"><span class="sc-key">timestamp</span>: <span class="sc-val">"${now.toISOString()}"</span></span>
    `;
  }

  // Tarjeta de recomendación en la pantalla de éxito
  const recFinal = document.getElementById('recFinal');
  if (recFinal && rec.titulo) {
    const color = rec.color || '#00d4ff';
    recFinal.innerHTML = `
      <div class="rec-final-card" style="--rec-color:${color}">
        <div class="rec-final-header">
          <span class="rec-final-icono">${rec.icono || '☁'}</span>
          <div>
            <div class="rec-final-titulo">${rec.titulo}</div>
            <div class="rec-final-sub">Recomendación basada en tus respuestas</div>
          </div>
        </div>
        <div class="rec-final-bloques">
          <div class="rec-final-bloque">
            <span class="rec-label">// perfil</span>
            <p>${rec.perfil}</p>
          </div>
          <div class="rec-final-bloque">
            <span class="rec-label">// por qué</span>
            <p>${rec.razon}</p>
          </div>
          <div class="rec-final-bloque">
            <span class="rec-label">// tecnologías recomendadas</span>
            <p class="rec-tech">${rec.tecnologias}</p>
          </div>
        </div>
      </div>`;
  }

  form.style.display = 'none';
  success.classList.add('show');
  success.scrollIntoView({ behavior:'smooth', block:'start' });

  document.getElementById('sideAnswered').textContent = TOTAL;
  document.getElementById('sidePct').textContent      = '100%';
  document.getElementById('miniFill').style.width     = '100%';
  // Sidebar también muestra recomendación final
  updateRecomendacionWidget(TOTAL);
  setLoading(false);
}

// ============================================================
// ERROR DEL SERVIDOR
// ============================================================
function showServerError(msg) {
  const existing = document.getElementById('serverErrorMsg');
  if (existing) existing.remove();
  const errDiv = document.createElement('div');
  errDiv.id = 'serverErrorMsg';
  errDiv.style.cssText = `margin:1rem 1.5rem;padding:.8rem 1rem;border:1px solid #ff4444;
    border-radius:4px;background:rgba(255,68,68,.07);color:#ff4444;font-size:.8rem;
    letter-spacing:.04em;white-space:pre-line;`;
  errDiv.innerHTML = `<strong>⚠ ERROR DEL SERVIDOR</strong><br>${msg}`;
  document.querySelector('.submit-zone').insertAdjacentElement('beforebegin', errDiv);
  errDiv.scrollIntoView({ behavior:'smooth', block:'center' });
  setTimeout(() => errDiv.remove(), 8000);
}

// ============================================================
// RESET
// ============================================================
function resetForm() {
  const form    = document.getElementById('quizForm');
  const success = document.getElementById('successScreen');

  document.querySelectorAll('input[type="radio"]').forEach(r => r.checked = false);
  document.querySelectorAll('.question-block').forEach(b => b.classList.remove('answered','has-error'));

  success.classList.remove('show');
  form.style.display = 'flex';

  ['answered','sideAnswered'].forEach(id => document.getElementById(id).textContent = '0');
  document.getElementById('sidePct').textContent      = '0%';
  document.getElementById('progressFill').style.width = '0%';
  document.getElementById('miniFill').style.width     = '0%';

  // Limpiar widget de recomendación
  const widget = document.getElementById('recWidget');
  if (widget) widget.innerHTML = `<div class="rec-pending"><span class="rec-wait-icon">◌</span><span>Responde al menos 5 preguntas para ver tu recomendación…</span><div class="rec-mini-bar"><div class="rec-mini-fill" style="width:0%"></div></div></div>`;

  setLoading(false);
  window.scrollTo({ top:0, behavior:'smooth' });
}
