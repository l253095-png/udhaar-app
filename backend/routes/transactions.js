const express = require('express');
const { db } = require('../config/db');
const { authenticate, ownerOnly } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate);

// WhatsApp is optional — if the package isn't installed yet or WhatsApp isn't linked, this quietly does nothing.
let sendWhatsAppMessage = async () => {};
try {
  sendWhatsAppMessage = require('../services/whatsapp').sendWhatsAppMessage;
} catch (e) {
  console.log('WhatsApp module not active yet.');
}

function notifyCustomer(customer, type, amount, newBalance) {
  const typeLabel = type === 'udhaar' ? 'Udhaar (Debit)' : 'Wasooli (Credit)';
  const message =
    `Assalam-o-Alaikum ${customer.name},\n` +
    `Aaj aap ne Rs ${amount} ka ${typeLabel} kiya.\n` +
    `Aapka remaining balance: Rs ${newBalance}\n` +
    `- Shukriya`;
  sendWhatsAppMessage(customer.phone, message).catch(() => {});
}

// GET /api/transactions - Owner and Worker can view all transactions
router.get('/', async (req, res) => {
  try {
    const { type, period } = req.query;

    let query = `SELECT t.*, c.name as customer_name, c.phone as customer_phone
                 FROM transactions t
                 JOIN customers c ON c.id = t.customer_id
                 WHERE 1=1`;
    const params = [];

    if (type === 'udhaar' || type === 'wasooli') {
      query += ' AND t.type = ?';
      params.push(type);
    }

    if (period === 'today') {
      query += " AND date(t.created_at) = date('now', 'localtime')";
    } else if (period === 'month') {
      query += " AND strftime('%Y-%m', t.created_at) = strftime('%Y-%m', 'now', 'localtime')";
    }

    query += ' ORDER BY t.created_at DESC LIMIT 500';

    const result = await db.execute({ sql: query, args: params });
    const transactions = result.rows;

    const total = transactions.reduce((sum, t) => sum + t.amount, 0);
    res.json({ transactions, total, count: transactions.length });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error fetching transactions' });
  }
});

// POST /api/transactions - Owner only
router.post('/', ownerOnly, async (req, res) => {
  try {
    const { customer_id, type, amount, note } = req.body;
    if (!customer_id || !type || !amount) {
      return res.status(400).json({ error: 'customer_id, type, and amount are required' });
    }
    if (!['udhaar', 'wasooli'].includes(type)) {
      return res.status(400).json({ error: 'type must be udhaar or wasooli' });
    }

    const custResult = await db.execute({
      sql: 'SELECT * FROM customers WHERE id = ?',
      args: [customer_id]
    });
    const customer = custResult.rows[0];
    if (!customer) return res.status(404).json({ error: 'Customer not found' });

    const balanceChange = type === 'udhaar' ? amount : -amount;

    // Execute using Turso transaction batch
    const batchResult = await db.batch([
      {
        sql: 'INSERT INTO transactions (customer_id, type, amount, note, source, created_by) VALUES (?, ?, ?, ?, ?, ?)',
        args: [customer_id, type, amount, note || null, 'app', req.user.id]
      },
      {
        sql: 'UPDATE customers SET balance = balance + ? WHERE id = ?',
        args: [balanceChange, customer_id]
      }
    ]);

    const insertResult = batchResult[0];
    const id = Number(insertResult.lastInsertRowid);

    const updatedCustResult = await db.execute({
      sql: 'SELECT * FROM customers WHERE id = ?',
      args: [customer_id]
    });
    const updatedCustomer = updatedCustResult.rows[0];
    
    notifyCustomer(customer, type, amount, updatedCustomer.balance);

    res.status(201).json({ id, message: 'Transaction recorded' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error creating transaction' });
  }
});

// PUT /api/transactions/:id - Owner only
router.put('/:id', ownerOnly, async (req, res) => {
  try {
    const { type, amount, note } = req.body;
    const txnResult = await db.execute({
      sql: 'SELECT * FROM transactions WHERE id = ?',
      args: [req.params.id]
    });
    const txn = txnResult.rows[0];
    if (!txn) return res.status(404).json({ error: 'Transaction not found' });

    const newType = type || txn.type;
    const newAmount = amount !== undefined ? amount : txn.amount;
    if (!['udhaar', 'wasooli'].includes(newType)) {
      return res.status(400).json({ error: 'type must be udhaar or wasooli' });
    }

    const oldEffect = txn.type === 'udhaar' ? -txn.amount : txn.amount; // undo old
    const newEffect = newType === 'udhaar' ? newAmount : -newAmount; // apply new

    await db.batch([
      {
        sql: 'UPDATE customers SET balance = balance + ? WHERE id = ?',
        args: [oldEffect, txn.customer_id]
      },
      {
        sql: 'UPDATE transactions SET type = ?, amount = ?, note = ? WHERE id = ?',
        args: [newType, newAmount, note ?? txn.note, req.params.id]
      },
      {
        sql: 'UPDATE customers SET balance = balance + ? WHERE id = ?',
        args: [newEffect, txn.customer_id]
      }
    ]);

    res.json({ message: 'Transaction updated' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error updating transaction' });
  }
});

// DELETE /api/transactions/:id - Owner only
router.delete('/:id', ownerOnly, async (req, res) => {
  try {
    const txnResult = await db.execute({
      sql: 'SELECT * FROM transactions WHERE id = ?',
      args: [req.params.id]
    });
    const txn = txnResult.rows[0];
    if (!txn) return res.status(404).json({ error: 'Transaction not found' });

    const balanceChange = txn.type === 'udhaar' ? -txn.amount : txn.amount;

    await db.batch([
      {
        sql: 'DELETE FROM transactions WHERE id = ?',
        args: [req.params.id]
      },
      {
        sql: 'UPDATE customers SET balance = balance + ? WHERE id = ?',
        args: [balanceChange, txn.customer_id]
      }
    ]);

    res.json({ message: 'Transaction deleted and balance adjusted' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error deleting transaction' });
  }
});

module.exports = router;