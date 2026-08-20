const db = require('./config/db');

console.log('=== SYNC LOG (jo tab_name Sync History screen dikhati hai) ===');
console.log(db.prepare('SELECT id, tab_name, rows_synced, synced_at FROM sync_log ORDER BY id DESC LIMIT 5').all());

console.log('\n=== RECENT TRANSACTIONS (jo sync_tab asal me save hua) ===');
console.log(db.prepare("SELECT id, customer_id, type, amount, source, sync_tab, created_at FROM transactions WHERE source='google_sheet' ORDER BY id DESC LIMIT 10").all());

console.log('\n=== STAGED (Imported) ENTRIES abhi bhi baaki hain? ===');
console.log(db.prepare('SELECT id, customer_id, amount, tab_name FROM staged_entries').all());

console.log('\n=== TIME CHECK ===');
console.log('Windows system time (JS):', new Date().toString());
console.log('SQLite localtime():', db.prepare("SELECT datetime('now','localtime') as t").get().t);
console.log('SQLite now() UTC:', db.prepare("SELECT datetime('now') as t").get().t);