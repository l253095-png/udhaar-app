const db = require('./config/db');
const type = 'udhaar';
const period = 'month';

let query = `SELECT t.*, c.name as customer_name FROM transactions t
             JOIN customers c ON c.id = t.customer_id WHERE 1=1`;
const params = [];

if (type === 'udhaar' || type === 'wasooli') {
  query += ' AND t.type = ?';
  params.push(type);
}
if (period === 'month') {
  query += " AND strftime('%Y-%m', t.created_at) = strftime('%Y-%m', 'now')";
}

console.log('QUERY:', query);
console.log('PARAMS:', params);
const rows = db.prepare(query).all(...params);
console.log('RESULT COUNT:', rows.length);
console.log('FIRST ROW:', rows[0]);