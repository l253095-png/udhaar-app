// Imports customers with their opening balances from customer_import_data.json
// (generated from the shop's Excel export). Each customer gets one opening
// transaction so the balance has a visible origin in their history.
//
// Run from the backend folder, AFTER reset_data.js:
//   node import_customers.js

const fs = require('fs');
const path = require('path');
const { db, initDb } = require('./config/db');
const { nowLocal } = require('./config/timeHelper');

const entries = JSON.parse(fs.readFileSync(path.join(__dirname, 'customer_import_data.json'), 'utf-8'));

(async () => {
  await initDb();

  const tx = await db.transaction('write');
  let count = 0;
  try {
    for (const entry of entries) {
      // Wasooli entries mean the customer overpaid / is owed money back,
      // so their balance starts negative.
      const startingBalance = entry.type === 'wasooli' ? -entry.amount : entry.amount;
      const now = nowLocal();

      const info = await tx.execute({
        sql: 'INSERT INTO customers (name, phone, balance, created_at) VALUES (?, NULL, ?, ?)',
        args: [entry.name, startingBalance, now],
      });
      const customerId = Number(info.lastInsertRowid);

      await tx.execute({
        sql: `INSERT INTO transactions (customer_id, type, amount, note, source, created_at)
              VALUES (?, ?, ?, 'Opening balance (imported)', 'import', ?)`,
        args: [customerId, entry.type, entry.amount, now],
      });
      count++;
    }
    await tx.commit();
  } catch (e) {
    await tx.rollback();
    throw e;
  }

  const udhaar = entries.filter((e) => e.type === 'udhaar').reduce((s, e) => s + e.amount, 0);
  const wasooli = entries.filter((e) => e.type === 'wasooli').reduce((s, e) => s + e.amount, 0);

  console.log(`\nImport complete!`);
  console.log(`Customers added: ${count}`);
  console.log(`Total Udhaar (owed to shop): Rs ${udhaar.toLocaleString('en-US', { minimumFractionDigits: 2 })}`);
  console.log(`Total Wasooli (paid back/advance): Rs ${wasooli.toLocaleString('en-US', { minimumFractionDigits: 2 })}`);
  console.log(`\nEach customer's phone number is empty — add it later via Edit`);
  console.log(`if you want WhatsApp reminders to work for them.`);
  process.exit(0);
})().catch((err) => {
  console.error('Import failed:', err);
  process.exit(1);
});
