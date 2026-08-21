// Clears customer/transaction/sync data so you can start fresh.
// Owner/Worker logins are NOT touched.
//
// Run from the backend folder:  node reset_data.js

const { db, initDb } = require('./config/db');

const tables = [
  'transactions',
  'staged_entries',
  'pending_sheet_syncs',
  'synced_rows',
  'expenses',
  'sync_log',
  'customers',
];

(async () => {
  await initDb();

  const tx = await db.transaction('write');
  try {
    for (const table of tables) {
      const info = await tx.execute(`DELETE FROM ${table}`);
      console.log(`Cleared ${table}: ${info.rowsAffected} rows removed`);
    }
    // Reset auto-increment counters so new records start from id=1 again
    await tx.execute({
      sql: `DELETE FROM sqlite_sequence WHERE name IN (${tables.map(() => '?').join(',')})`,
      args: tables,
    });
    await tx.commit();
  } catch (e) {
    await tx.rollback();
    throw e;
  }

  console.log('\nDone. Customers, transactions, imported/pending entries, and expenses are all cleared.');
  console.log('Your Owner/Worker logins are untouched.');
  process.exit(0);
})().catch((err) => {
  console.error('Reset failed:', err);
  process.exit(1);
});
