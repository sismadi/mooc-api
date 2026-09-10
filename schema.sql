-- ============================================================
-- schema.sql — Skema Cloudflare D1 untuk MOOC IPWIJA
-- Menggantikan localStorage (db.js) di project pages_mooc_pkm
-- ============================================================
-- Jalankan:
--   wrangler d1 execute <NAMA_DB> --file=./schema.sql            (lokal)
--   wrangler d1 execute <NAMA_DB> --file=./schema.sql --remote   (production)
--
-- Sumber pemetaan tabel: db.js (header komentar) + quiz.js (komentar
-- baris 8-15) — dicek ulang lewat grep pemanggilan db.* di seluruh
-- auth.js/courses.js/dosen.js/admin.js/quiz.js.
-- ============================================================

DROP TABLE IF EXISTS certificates;
DROP TABLE IF EXISTS quizAttempts;
DROP TABLE IF EXISTS quizzes;
DROP TABLE IF EXISTS passwordResets;
DROP TABLE IF EXISTS progress;
DROP TABLE IF EXISTS courses;
DROP TABLE IF EXISTS users;

-- users : akun peserta / dosen / admin
CREATE TABLE users (
    id       TEXT PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    password TEXT NOT NULL,        -- TODO: ganti ke hash (bcrypt/argon2) sebelum production
    name     TEXT NOT NULL,
    role     TEXT NOT NULL CHECK (role IN ('peserta','dosen','admin')),
    email    TEXT UNIQUE
);

-- courses : kursus/materi tambahan dari dosen, override di atas kursus
-- statis (pages/learn.js + pages/<slug>.js) — lihat courseSvc.list()
CREATE TABLE courses (
    id                 TEXT PRIMARY KEY,
    slug               TEXT NOT NULL UNIQUE,
    title              TEXT,
    description        TEXT DEFAULT '',
    price              TEXT DEFAULT 'Gratis',   -- teks bebas, mis. "Gratis" atau "Rp 150.000"
    instructor         TEXT,
    instructorUsername TEXT REFERENCES users(username),
    period             TEXT DEFAULT 'Self-paced',
    categories         TEXT DEFAULT '[]',       -- JSON array [{name, items:[...]}]
    deleted            INTEGER DEFAULT 0        -- 1 = disembunyikan dari katalog (courseSvc.list())
);

-- progress : progres belajar per akun per kursus
CREATE TABLE progress (
    id       TEXT PRIMARY KEY,
    username TEXT NOT NULL REFERENCES users(username),
    slug     TEXT NOT NULL,
    viewed   TEXT DEFAULT '[]',   -- JSON array id modul yang sudah dilihat
    lastId   TEXT,
    UNIQUE (username, slug)
);

-- passwordResets : token reset password sekali pakai
CREATE TABLE passwordResets (
    id        TEXT PRIMARY KEY,
    username  TEXT NOT NULL REFERENCES users(username),
    token     TEXT NOT NULL UNIQUE,
    expiresAt INTEGER NOT NULL    -- epoch ms
);

-- quizzes : SATU baris per kursus (kunci: slug) — lihat quizSvc di quiz.js
CREATE TABLE quizzes (
    id           TEXT PRIMARY KEY,
    slug         TEXT NOT NULL UNIQUE,
    title        TEXT,
    passingGrade INTEGER DEFAULT 75,
    password     TEXT DEFAULT '',
    questions    TEXT DEFAULT '[]'   -- JSON array [{q, options:[...], ans: base64}]
);

-- quizAttempts : riwayat pengerjaan kuis, per akun per kursus
CREATE TABLE quizAttempts (
    id       TEXT PRIMARY KEY,
    username TEXT NOT NULL REFERENCES users(username),
    slug     TEXT NOT NULL,
    score    REAL NOT NULL,
    date     TEXT NOT NULL
);

-- certificates : sertifikat kuis, terbit otomatis saat lulus (certSvc.award)
-- id memakai kode deterministik "SLS-KUIS-<slug>-<username>" (dibuat di
-- client), BUKAN id acak — supaya 1 peserta hanya punya 1 sertifikat/kursus.
CREATE TABLE certificates (
    id        TEXT PRIMARY KEY,
    username  TEXT NOT NULL REFERENCES users(username),
    name      TEXT,
    slug      TEXT NOT NULL,
    examTitle TEXT,
    score     REAL,
    date      TEXT
);

CREATE INDEX idx_courses_instructorUsername ON courses(instructorUsername);
CREATE INDEX idx_progress_username ON progress(username);
CREATE INDEX idx_passwordResets_username ON passwordResets(username);
CREATE INDEX idx_passwordResets_token ON passwordResets(token);
CREATE INDEX idx_quizAttempts_username_slug ON quizAttempts(username, slug);
CREATE INDEX idx_certificates_username ON certificates(username);

-- --- Seed akun demo (setara db.seedIfEmpty('users', ...) di db.js lama) ---
INSERT INTO users (id, username, password, name, role, email) VALUES
    ('u_admin',   'admin',   'admin123',   'Administrator', 'admin',   'admin@sls.demo'),
    ('u_dosen',   'dosen',   'dosen123',   'Wawan Sismadi', 'dosen',   'dosen@sls.demo'),
    ('u_peserta', 'peserta', 'peserta123', 'Peserta Demo',  'peserta', 'peserta@sls.demo');

-- --- Seed kuis demo RPL (setara db.seedIfEmpty('quizzes', ...) di quiz.js) ---
INSERT INTO quizzes (id, slug, title, passingGrade, password, questions) VALUES (
    'quiz_rpl',
    'rpl',
    'Evaluasi Kompetensi: Rekayasa Perangkat Lunak',
    75,
    'DonatJS',
    '[
        {"q":"Berapakah nilai x dari persamaan 2x + 5 = 13?","options":["3","4","6","8"],"ans":"NA=="},
        {"q":"Jika 3(x - 2) = x + 10, maka nilai x adalah...","options":["4","6","8","10"],"ans":"OA=="},
        {"q":"Tentukan penyelesaian dari persamaan 5x - 7 = 2x + 8.","options":["3","5","15","2"],"ans":"NQ=="}
    ]'
);
