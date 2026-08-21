// Adds customers who had a ZERO/empty balance in the spreadsheet (so they
// weren't part of the main import). These get added with balance=0 and no
// opening transaction - just a customer record for future tracking.
//
// Run from the backend folder, AFTER import_customers.js:
//   node import_zero_balance_customers.js

const fs = require('fs');
const path = require('path');
const { db, initDb } = require('./config/db');
const { nowLocal } = require('./config/timeHelper');

const names = JSON.parse(fs.readFileSync(path.join(__dirname, 'zero_balance_import.json'), 'utf-8'));

(async () => {
  await initDb();

  const tx = await db.transaction('write');
  let count = 0;
  try {
    for (const name of names) {
      await tx.execute({
        sql: 'INSERT INTO customers (name, phone, balance, created_at) VALUES (?, NULL, 0, ?)',
        args: [name, nowLocal()],
      });
      count++;
    }
    await tx.commit();
  } catch (e) {
    await tx.rollback();
    throw e;
  }

  console.log(`\nZero-balance customers added: ${count}`);
  console.log('These have Rs 0 balance and no transaction history yet.');
  process.exit(0);
})().catch((err) => {
  console.error('Import failed:', err);
  process.exit(1);
});
