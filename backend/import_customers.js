// One-time bulk import script: loads customers + their opening Udhaar balance
// from customer_import_data.json (extracted from the old Udhaar.pk app's PDF).
//
// Run this from the backend folder, AFTER running reset_data.js:
//   node import_customers.js

const fs = require('fs');
const path = require('path');
const db = require('./config/db');

const dataPath = path.join(__dirname, 'customer_import_data.json');
const entries = JSON.parse(fs.readFileSync(dataPath, 'utf-8'));

const insertCustomer = db.prepare('INSERT INTO customers (name, phone, balance) VALUES (?, NULL, ?)');
const insertTxn = db.prepare(
  "INSERT INTO transactions (customer_id, type, amount, note, source) VALUES (?, 'udhaar', ?, 'Opening balance (imported from Udhaar.pk)', 'import')"
);

const runImport = db.transaction(() => {
  let count = 0;
  for (const entry of entries) {
    const info = insertCustomer.run(entry.name, entry.amount);
    insertTxn.run(info.lastInsertRowid, entry.amount);
    count++;
  }
  return count;
});

const imported = runImport();
const total = entries.reduce((sum, e) => sum + e.amount, 0);

console.log(`\nImport complete!`);
console.log(`Customers added: ${imported}`);
console.log(`Total opening balance: Rs ${total.toLocaleString()}`);
console.log(`\nEach customer's phone number is empty — add it later via Edit`);
console.log(`if you want WhatsApp notifications to work for them.`);
