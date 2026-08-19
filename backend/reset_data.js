// One-time cleanup script: clears test/demo data so you can start fresh
// with your real Google Sheet data. Owner/Worker logins are NOT touched.
//
// Run this from the backend folder:  node reset_data.js

const db = require('./config/db');

const tables = ['transactions', 'pending_sheet_syncs', 'synced_rows', 'expenses', 'sync_log', 'customers'];

const runReset = db.transaction(() => {
  for (const table of tables) {
    const info = db.prepare(`DELETE FROM ${table}`).run();
    console.log(`Cleared ${table}: ${info.changes} rows removed`);
  }
  // Reset auto-increment counters so new records start from id=1 again
  db.prepare(`DELETE FROM sqlite_sequence WHERE name IN (${tables.map(() => '?').join(',')})`).run(...tables);
});

runReset();

console.log('\nDone. Customers, transactions, pending approvals, and expense entries are all cleared.');
console.log('Your Owner/Worker logins are untouched.');
