const Database = require('better-sqlite3');
const path = require('path');

const db = new Database(path.join(__dirname, '..', 'udhaar.db'));

db.pragma('journal_mode = WAL');

// ---- Schema ----
db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL CHECK(role IN ('owner', 'worker')),
    created_at TEXT DEFAULT (datetime('now'))
  );

  -- phone is optional because customers created automatically from the
  -- Google Sheet (Udhaar/Wasooli columns) don't have a phone number there.
  CREATE TABLE IF NOT EXISTS customers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    phone TEXT,
    balance REAL DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS transactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id INTEGER NOT NULL,
    type TEXT NOT NULL CHECK(type IN ('udhaar', 'wasooli')),
    amount REAL NOT NULL,
    note TEXT,
    source TEXT DEFAULT 'app',
    created_by INTEGER,
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    FOREIGN KEY (created_by) REFERENCES users(id)
  );

  CREATE TABLE IF NOT EXISTS sync_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rows_synced INTEGER DEFAULT 0,
    new_customers_flagged INTEGER DEFAULT 0,
    synced_by INTEGER,
    synced_at TEXT DEFAULT (datetime('now'))
  );

  -- Used by the 3 dashboard modules: Monthly Expense, Daily Online, Main Branch Purchase.
  -- Card Transaction module was removed per owner's request.
  CREATE TABLE IF NOT EXISTS expenses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category TEXT NOT NULL CHECK(category IN ('monthly_expense', 'daily_online', 'daily_main_branch_purchase')),
    amount REAL NOT NULL,
    note TEXT,
    entry_date TEXT DEFAULT (date('now')),
    source TEXT DEFAULT 'app',
    created_by INTEGER,
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (created_by) REFERENCES users(id)
  );

  -- Sheet rows that didn't exactly match an existing customer.
  -- Owner reviews these and links/creates/rejects them manually.
  CREATE TABLE IF NOT EXISTS pending_sheet_syncs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sheet_name TEXT NOT NULL,
    phone TEXT,
    amount REAL NOT NULL,
    type TEXT NOT NULL CHECK(type IN ('udhaar', 'wasooli')),
    note TEXT,
    tab_name TEXT,
    suggested_customer_id INTEGER,
    suggested_customer_name TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (suggested_customer_id) REFERENCES customers(id)
  );

  -- Tracks which individual sheet rows (by tab + cell) have already been
  -- processed, so re-running sync on the same day's tab never double-counts
  -- a customer's udhaar/wasooli row.
  CREATE TABLE IF NOT EXISTS synced_rows (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tab_name TEXT NOT NULL,
    row_key TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    UNIQUE(tab_name, row_key)
  );
`);

module.exports = db;
