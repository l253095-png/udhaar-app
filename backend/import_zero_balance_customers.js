// Adds customers who had a ZERO/empty balance in the spreadsheet (so they
// weren't part of the main import). These get added with balance=0 and no
// opening transaction - just a customer record for future tracking.
//
// Run this from the backend folder, AFTER the main import_customers.js:
//   node import_zero_balance_customers.js

const fs = require('fs');
const path = require('path');
const db = require('./config/db');

const dataPath = path.join(__dirname, 'zero_balance_import.json');
const names = JSON.parse(fs.readFileSync(dataPath, 'utf-8'));

const insertCustomer = db.prepare('INSERT INTO customers (name, phone, balance) VALUES (?, NULL, 0)');

const runImport = db.transaction(() => {
  let count = 0;
  for (const name of names) {
    insertCustomer.run(name);
    count++;
  }
  return count;
});

const imported = runImport();

console.log(`\nZero-balance customers added: ${imported}`);
console.log(`These have Rs 0 balance and no transaction history yet.`);
