const fs = require('fs');
const path = require('path');
const { db } = require('./config/db');

async function runCorrectImport() {
  try {
    const dataPath = path.join(__dirname, 'customer_import_data.json');
    if (!fs.existsSync(dataPath)) {
      console.error('Error: customer_import_data.json file nahi mili!');
      return;
    }

    const entries = JSON.parse(fs.readFileSync(dataPath, 'utf-8'));

    console.log('Purana data saaf kiya ja raha hai...');
    await db.execute('DELETE FROM transactions');
    await db.execute('DELETE FROM customers');

    let imported = 0;
    let totalBalance = 0;

    console.log('Asli data import ho raha hai...');

    for (const entry of entries) {
      const balance = entry.balance || 0;

      // 1. Customer insert karein
      const customerResult = await db.execute({
        sql: 'INSERT INTO customers (name, phone, balance) VALUES (?, NULL, ?)',
        args: [entry.name, balance]
      });

      const customerId = Number(customerResult.lastInsertRowid);

      // 2. Agar balance 0 nahi hai toh transaction insert karein (Sahi order: customerId, txnType, amount)
      if (balance !== 0) {
        const txnType = balance > 0 ? 'udhaar' : 'wasooli';
        await db.execute({
          sql: `INSERT INTO transactions (customer_id, type, amount, note, source) VALUES (?, ?, ?, 'Opening balance (corrected data)', 'import')`,
          args: [customerId, txnType, Math.abs(balance)]
        });
      }

      totalBalance += balance;
      imported++;
    }

    console.log(`\nImport successfully mukammal ho gayi!`);
    console.log(`Total Customers added: ${imported}`);
    console.log(`Total Balance Amount: Rs ${totalBalance.toLocaleString()}`);

  } catch (error) {
    console.error('Import ke dauran error aa gaya:', error);
  }
}

runCorrectImport();