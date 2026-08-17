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

  CREATE TABLE IF NOT EXISTS customers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    phone TEXT NOT NULL,
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

  -- Used by the 4 dashboard modules: Monthly Expense, Daily Online,
  -- Daily Card Transaction, Daily Main Branch Purchase
  CREATE TABLE IF NOT EXISTS expenses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category TEXT NOT NULL CHECK(category IN ('monthly_expense', 'daily_online', 'daily_card', 'daily_main_branch_purchase')),
    amount REAL NOT NULL,
    note TEXT,
    entry_date TEXT DEFAULT (date('now')),
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
    suggested_customer_id INTEGER,
    suggested_customer_name TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (suggested_customer_id) REFERENCES customers(id)
  );
`);

module.exports = db;
