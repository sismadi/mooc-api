// ============================================================
// worker.js — Worker API generik di atas D1 untuk MOOC IPWIJA
// ============================================================
// wrangler.toml perlu binding:
//   [[d1_databases]]
//   binding = "DB"
//   database_name = "<NAMA_DB>"
//   database_id = "<ID_DB>"
//
// Route generik (berlaku utk 7 tabel: users, courses, progress,
// passwordResets, quizzes, quizAttempts, certificates):
//   GET    /api/:table               -> semua baris
//   GET    /api/:table/:id           -> satu baris (atau null)
//   POST   /api/:table               -> insert (body = row, id opsional)
//   PATCH  /api/:table/:id           -> update sebagian (merge)
//   DELETE /api/:table/:id           -> hapus
//
// Field JSON (categories, viewed, questions) otomatis di-serialize/
// deserialize di worker ini, sehingga db.js di frontend tetap menerima/
// mengirim array/object JS biasa, bukan string JSON.
// ============================================================

const TABLES = {
  users: { jsonCols: [] },
  courses: { jsonCols: ['categories'] },
  progress: { jsonCols: ['viewed'] },
  passwordResets: { jsonCols: [] },
  quizzes: { jsonCols: ['questions'] },
  quizAttempts: { jsonCols: [] },
  certificates: { jsonCols: [] },
};

function genId(table) {
  return table + '_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
}

function serializeRow(table, row) {
  const out = { ...row };
  for (const col of TABLES[table].jsonCols) {
    if (col in out) out[col] = JSON.stringify(out[col] ?? []);
  }
  return out;
}

function deserializeRow(table, row) {
  if (!row) return row;
  const out = { ...row };
  for (const col of TABLES[table].jsonCols) {
    if (col in out) {
      try { out[col] = JSON.parse(out[col]); } catch { out[col] = []; }
    }
  }
  return out;
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    },
  });
}

async function handleApi(request, env) {
  const url = new URL(request.url);
  const parts = url.pathname.split('/').filter(Boolean); // ['api', table, id?]

  if (parts[0] !== 'api' || !parts[1]) return json({ error: 'Not found' }, 404);
  const table = parts[1];
  const id = parts[2];
  if (!(table in TABLES)) return json({ error: `Tabel '${table}' tidak dikenal` }, 400);

  const db = env.DB;

  if (request.method === 'GET') {
    if (id) {
      const row = await db.prepare(`SELECT * FROM ${table} WHERE id = ?`).bind(id).first();
      return json(deserializeRow(table, row) || null);
    }
    const { results } = await db.prepare(`SELECT * FROM ${table}`).all();
    return json(results.map(r => deserializeRow(table, r)));
  }

  if (request.method === 'POST' && !id) {
    const body = await request.json();
    const record = { id: body.id || genId(table), ...body };
    const row = serializeRow(table, record);
    const cols = Object.keys(row);
    await db
      .prepare(`INSERT INTO ${table} (${cols.join(', ')}) VALUES (${cols.map(() => '?').join(', ')})`)
      .bind(...cols.map(c => row[c]))
      .run();
    return json(record, 201);
  }

  if (request.method === 'PATCH' && id) {
    const patch = await request.json();
    const existing = await db.prepare(`SELECT * FROM ${table} WHERE id = ?`).bind(id).first();
    if (!existing) return json(null, 404);
    const merged = { ...deserializeRow(table, existing), ...patch };
    const row = serializeRow(table, merged);
    const cols = Object.keys(row).filter(c => c !== 'id');
    await db
      .prepare(`UPDATE ${table} SET ${cols.map(c => `${c} = ?`).join(', ')} WHERE id = ?`)
      .bind(...cols.map(c => row[c]), id)
      .run();
    return json(merged);
  }

  if (request.method === 'DELETE' && id) {
    await db.prepare(`DELETE FROM ${table} WHERE id = ?`).bind(id).run();
    return json({ ok: true });
  }

  return json({ error: 'Method not allowed' }, 405);
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET,POST,PATCH,DELETE,OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
        },
      });
    }
    try {
      return await handleApi(request, env);
    } catch (err) {
      return json({ error: err.message }, 500);
    }
  },
};
