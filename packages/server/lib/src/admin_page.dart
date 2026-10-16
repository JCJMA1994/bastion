/// Panel de administración: una sola página que consulta `/admin/summary` y
/// `/admin/logs` con el token guardado en el navegador.
const adminPageHtml = r'''<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Bastión · Panel</title>
<style>
:root{--bg:#101316;--panel:#1f242b;--line:#2c333c;--ink:#eeeae2;--muted:#a9b0b8;--brass:#e3a33b;--brass-ink:#1a1206;--danger:#ef7766;--ok:#6cc08a}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.45 system-ui,"Segoe UI",sans-serif}
header{display:flex;gap:12px;align-items:center;padding:12px 16px;border-bottom:1px solid var(--line);background:#171b20;flex-wrap:wrap}
h1{font-size:18px;margin:0;letter-spacing:.06em}main{padding:16px;display:grid;gap:16px}
input,select,button{font:inherit;color:var(--ink);background:var(--panel);border:1px solid #3d4652;border-radius:8px;padding:8px 10px;min-height:40px}
button{background:var(--brass);color:var(--brass-ink);border:0;font-weight:700;cursor:pointer}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:12px}
.card h2{font-size:11px;letter-spacing:.08em;color:var(--muted);margin:0 0 6px;text-transform:uppercase}
.big{font:600 24px ui-monospace,monospace}
table{width:100%;border-collapse:collapse;background:var(--panel);border-radius:8px;overflow:hidden}
th,td{padding:6px 8px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}
th{font-size:11px;letter-spacing:.08em;color:var(--muted);text-transform:uppercase}
td.mono{font-family:ui-monospace,monospace;font-size:12px;white-space:pre-wrap;word-break:break-word}
.error{color:var(--danger)}.warn{color:var(--brass)}.muted{color:var(--muted)}
.filters{display:flex;gap:8px;flex-wrap:wrap}
.scroll{overflow-x:auto}
</style>
</head>
<body>
<header>
  <h1>BASTIÓN · PANEL</h1>
  <input id="token" type="password" placeholder="Token de administración" aria-label="Token de administración">
  <button id="save">Entrar</button>
  <span id="status" class="muted" role="status"></span>
</header>
<main>
  <section class="cards" aria-label="Resumen de las últimas 24 horas">
    <div class="card"><h2>Instalaciones</h2><div class="big" id="installs">—</div></div>
    <div class="card"><h2>Partidas online</h2><div class="big" id="matches">—</div></div>
    <div class="card"><h2>Entradas</h2><div class="big" id="entries">—</div></div>
    <div class="card"><h2>Versiones</h2><div id="versions" class="mono">—</div></div>
  </section>
  <section class="cards">
    <div class="card"><h2>Eventos</h2><div id="events" class="mono">—</div></div>
    <div class="card"><h2>Errores frecuentes</h2><div id="errors" class="mono error">—</div></div>
    <div class="card"><h2>Victorias por perfil (partidas reales)</h2><div id="profiles" class="mono">—</div></div>
  </section>
  <section>
    <div class="filters">
      <select id="kind" aria-label="Tipo"><option value="">Todo</option><option value="log">Logs</option><option value="error">Errores</option><option value="event">Eventos</option></select>
      <select id="level" aria-label="Nivel"><option value="">Cualquier nivel</option><option>debug</option><option>info</option><option>warning</option><option>error</option></select>
      <select id="env" aria-label="Entorno"><option value="">Todos los entornos</option><option>dev</option><option>qa</option><option>prod</option></select>
      <input id="q" placeholder="Buscar texto" aria-label="Buscar texto">
      <input id="install" placeholder="Instalación" aria-label="Instalación">
      <button id="refresh">Actualizar</button>
    </div>
  </section>
  <section class="scroll">
    <table>
      <thead><tr><th>Hora (UTC)</th><th>Tipo</th><th>Nombre</th><th>Mensaje y datos</th><th>Entorno · versión</th><th>Instalación</th></tr></thead>
      <tbody id="rows"><tr><td colspan="6" class="muted">Introduce el token para ver los registros.</td></tr></tbody>
    </table>
  </section>
</main>
<script>
const $ = (id) => document.getElementById(id);
$('token').value = localStorage.getItem('bastionAdmin') || '';
$('save').onclick = () => { localStorage.setItem('bastionAdmin', $('token').value); load(); };
$('refresh').onclick = load;
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
async function api(path) {
  const r = await fetch(path, { headers: { authorization: 'Bearer ' + $('token').value } });
  if (!r.ok) throw new Error(r.status === 401 ? 'Token incorrecto' : 'Error ' + r.status);
  return r.json();
}
function list(items) {
  return items.length ? items.map((i) => esc(i.count + ' · ' + i.name)).join('\n') : 'Sin datos';
}
async function load() {
  $('status').textContent = 'Cargando…';
  try {
    const s = await api('/admin/summary?hours=24');
    $('installs').textContent = s.installs;
    $('matches').textContent = s.matches;
    $('entries').textContent = s.entries;
    $('versions').textContent = list(s.versions);
    $('events').textContent = list(s.events);
    $('errors').textContent = list(s.errors);
    const p = Object.entries(s.profiles).sort((a, b) => b[1].battles - a[1].battles);
    $('profiles').textContent = p.length
      ? p.map(([id, v]) => id.padEnd(14) + String(Math.round(v.winRate * 100)).padStart(3) + '% de ' + v.battles).join('\n')
      : 'Sin batallas';
    const params = new URLSearchParams();
    for (const k of ['kind', 'level', 'env', 'q', 'install']) if ($(k).value) params.set(k, $(k).value);
    params.set('limit', '300');
    const logs = await api('/admin/logs?' + params);
    $('rows').innerHTML = logs.entries.map((e) => {
      const cls = e.kind === 'error' || e.level === 'error' ? 'error' : (e.level === 'warning' ? 'warn' : '');
      const detail = [e.message, e.data ? JSON.stringify(e.data) : ''].filter(Boolean).join('\n');
      return '<tr class="' + cls + '"><td class="mono">' + esc(e.time.replace('T', ' ').slice(0, 19)) +
        '</td><td>' + esc(e.kind + (e.level ? ' · ' + e.level : '')) + '</td><td>' + esc(e.name) +
        '</td><td class="mono">' + esc(detail) + '</td><td>' + esc(e.env + ' · ' + e.version) +
        '</td><td class="mono">' + esc(e.install.slice(0, 8)) + '</td></tr>';
    }).join('') || '<tr><td colspan="6" class="muted">Sin registros con esos filtros.</td></tr>';
    $('status').textContent = 'Actualizado ' + new Date().toLocaleTimeString();
  } catch (err) {
    $('status').textContent = err.message;
  }
}
if ($('token').value) load();
setInterval(() => { if ($('token').value) load(); }, 15000);
</script>
</body>
</html>
''';
