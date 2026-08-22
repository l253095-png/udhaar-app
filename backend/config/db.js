require('dotenv').config(); // Make sure env vars are loaded
const dns = require('dns');

// Fix for Windows / Node.js 18+ DNS lookup bug (prevents getaddrinfo ENOTFOUND)
if (dns.setDefaultResultOrder) {
  dns.setDefaultResultOrder('ipv4first');
}

const { createClient } = require('@libsql/client');

// Initialize the Turso client
const db = createClient({
  url: process.env.TURSO_DATABASE_URL,
  authToken: process.env.TURSO_AUTH_TOKEN,
});

// All schema and migrations must now be async
async function initDb() {
  console.log('[DB] Initializing Turso database connection and schema...');

  // ---- Schema ----
  await db.executeMultiple(`
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      role TEXT NOT NULL CHECK(role IN ('owner', 'worker')),
      created_at TEXT DEFAULT (datetime('now', 'localtime'))
    );

    CREATE TABLE IF NOT EXISTS customers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      phone TEXT,
      balance REAL DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now', 'localtime'))
    );

    CREATE TABLE IF NOT EXISTS transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL,
      type TEXT NOT NULL CHECK(type IN ('udhaar', 'wasooli')),
      amount REAL NOT NULL,
      note TEXT,
      source TEXT DEFAULT 'app',
      sync_tab TEXT,
      created_by INTEGER,
      created_at TEXT DEFAULT (datetime('now', 'localtime')),
      FOREIGN KEY (customer_id) REFERENCES customers(id),
      FOREIGN KEY (created_by) REFERENCES users(id)
    );

    CREATE TABLE IF NOT EXISTS sync_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tab_name TEXT,
      rows_synced INTEGER DEFAULT 0,
      new_customers_flagged INTEGER DEFAULT 0,
      synced_by INTEGER,
      synced_at TEXT DEFAULT (datetime('now', 'localtime'))
    );

    CREATE TABLE IF NOT EXISTS expenses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      category TEXT NOT NULL CHECK(category IN ('monthly_expense', 'daily_online', 'daily_main_branch_purchase')),
      amount REAL NOT NULL,
      note TEXT,
      entry_date TEXT DEFAULT (date('now', 'localtime')),
      source TEXT DEFAULT 'app',
      sync_tab TEXT,
      created_by INTEGER,
      created_at TEXT DEFAULT (datetime('now', 'localtime')),
      FOREIGN KEY (created_by) REFERENCES users(id)
    );

    CREATE TABLE IF NOT EXISTS pending_sheet_syncs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sheet_name TEXT NOT NULL,
      phone TEXT,
      amount REAL NOT NULL,
      type TEXT NOT NULL CHECK(type IN ('udhaar', 'wasooli')),
      note TEXT,
      tab_name TEXT,
      sheet_id TEXT,
      marker_cell TEXT,
      row_key TEXT,
      suggested_customer_id INTEGER,
      suggested_customer_name TEXT,
      created_at TEXT DEFAULT (datetime('now', 'localtime')),
      FOREIGN KEY (suggested_customer_id) REFERENCES customers(id)
    );

    CREATE TABLE IF NOT EXISTS synced_rows (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tab_name TEXT NOT NULL,
      row_key TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now', 'localtime')),
      UNIQUE(tab_name, row_key)
    );

    CREATE TABLE IF NOT EXISTS ignored_sheet_names (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      normalized_name TEXT UNIQUE NOT NULL,
      original_name TEXT NOT NULL,
      created_by INTEGER,
      created_at TEXT DEFAULT (datetime('now', 'localtime'))
    );

    CREATE TABLE IF NOT EXISTS staged_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL,
      type TEXT NOT NULL CHECK(type IN ('udhaar', 'wasooli')),
      amount REAL NOT NULL,
      note TEXT,
      tab_name TEXT,
      sheet_id TEXT,
      marker_cell TEXT,
      row_key TEXT,
      created_by INTEGER,
      created_at TEXT DEFAULT (datetime('now', 'localtime')),
      FOREIGN KEY (customer_id) REFERENCES customers(id)
    );
        CREATE TABLE IF NOT EXISTS audit_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL,
      entity_id INTEGER,
      action TEXT NOT NULL,
      description TEXT,
      performed_by INTEGER,
      created_at TEXT DEFAULT (datetime('now', 'localtime')),
      FOREIGN KEY (performed_by) REFERENCES users(id)
    );
  `);

  // ---- Lightweight migrations ----
  async function addColumnIfMissing(table, column, definition) {
    const rs = await db.execute(`PRAGMA table_info(${table})`);
    const existingColumns = rs.rows.map((c) => c.name);
    if (!existingColumns.includes(column)) {
      await db.execute(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
    }
  }

  await addColumnIfMissing('transactions', 'sync_tab', 'TEXT');
  await addColumnIfMissing('expenses', 'sync_tab', 'TEXT');
  await addColumnIfMissing('sync_log', 'tab_name', 'TEXT');
  await addColumnIfMissing('pending_sheet_syncs', 'row_key', 'TEXT');
  await addColumnIfMissing('pending_sheet_syncs', 'sheet_id', 'TEXT');
  await addColumnIfMissing('pending_sheet_syncs', 'marker_cell', 'TEXT');
  await addColumnIfMissing('pending_sheet_syncs', 'tab_name', 'TEXT');
  await addColumnIfMissing('customers', 'public_token', 'TEXT');

  // ---- Fix ignored_sheet_names ----
  async function fixIgnoredSheetNamesSchema() {
    const rsTable = await db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='ignored_sheet_names'");
    if (rsTable.rows.length === 0) return;

    const rsColumns = await db.execute('PRAGMA table_info(ignored_sheet_names)');
    const columns = rsColumns.rows.map((c) => c.name);
    if (columns.includes('normalized_name')) return;

    console.log('[DB Migration] Rebuilding ignored_sheet_names with the correct schema...');
    await db.execute('ALTER TABLE ignored_sheet_names RENAME TO ignored_sheet_names_old');
    await db.execute(`
      CREATE TABLE ignored_sheet_names (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        normalized_name TEXT UNIQUE NOT NULL,
        original_name TEXT NOT NULL,
        created_by INTEGER,
        created_at TEXT DEFAULT (datetime('now', 'localtime'))
      );
    `);

    if (columns.includes('name')) {
      const oldRows = await db.execute('SELECT * FROM ignored_sheet_names_old');
      for (const row of oldRows.rows) {
        const normalized = (row.name || '').toString().trim().toLowerCase();
        if (normalized) {
          await db.execute({
            sql: 'INSERT OR IGNORE INTO ignored_sheet_names (normalized_name, original_name) VALUES (?, ?)',
            args: [normalized, row.name]
          });
        }
      }
    }
    await db.execute('DROP TABLE ignored_sheet_names_old');
  }

  await fixIgnoredSheetNamesSchema();
  console.log('[DB] Init and Migrations complete.');
}

// We now export BOTH the client (db) and the initializer (initDb)
module.exports = { db, initDb };
