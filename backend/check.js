const db = require('./config/db');
console.log('By type:', db.prepare('SELECT type, COUNT(*) as count FROM transactions GROUP BY type').all());
console.log('Server today:', db.prepare("SELECT date('now') as today, strftime('%Y-%m','now') as month").get());
console.log('Sample udhaar:', db.prepare("SELECT * FROM transactions WHERE type='udhaar' LIMIT 3").all());