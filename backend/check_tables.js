const db = require('./config/db');
const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all();
console.log('Tables:', tables.map(t => t.name));

const cols = db.prepare("PRAGMA table_info(ignored_sheet_names)").all();
console.log('ignored_sheet_names columns:', cols);