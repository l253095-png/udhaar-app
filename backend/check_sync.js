const db = require('./config/db');
const rows = db.prepare('SELECT id, tab_name, rows_synced, synced_at FROM sync_log ORDER BY synced_at DESC LIMIT 10').all();
console.log(rows);