const express = require('express');
const db = require('../config/db');
const { authenticate, ownerOnly } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate);

// WhatsApp is optional — if the package isn't installed yet (npm install not run
// with the new dependency) or WhatsApp isn't linked, this quietly does nothing.
let sendWhatsAppMessage = async () => {};
try {
  sendWhatsAppMessage = require('../services/whatsapp').sendWhatsAppMessage;
} catch (e) {
  console.log('WhatsApp module not active yet (run `npm install` to enable it).');
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
// Optional query params: ?type=udhaar|wasooli  &period=today|month
router.get('/', (req, res) => {
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
    query += " AND date(t.created_at, 'localtime') = date('now', 'localtime')";
  } else if (period === 'month') {
    query += " AND strftime('%Y-%m', t.created_at, 'localtime') = strftime('%Y-%m', 'now', 'localtime')";
  }

  query += ' ORDER BY t.created_at DESC LIMIT 500';

  const transactions = db.prepare(query).all(...params);

  const total = transactions.reduce((sum, t) => sum + t.amount, 0);
  res.json({ transactions, total, count: transactions.length });
});

// POST /api/transactions - Owner only
router.post('/', ownerOnly, (req, res) => {
  const { customer_id, type, amount, note } = req.body;
  if (!customer_id || !type || !amount) {
    return res.status(400).json({ error: 'customer_id, type, and amount are required' });
  }
  if (!['udhaar', 'wasooli'].includes(type)) {
    return res.status(400).json({ error: 'type must be udhaar or wasooli' });
  }

  const customer = db.prepare('SELECT * FROM customers WHERE id = ?').get(customer_id);
  if (!customer) return res.status(404).json({ error: 'Customer not found' });

  const balanceChange = type === 'udhaar' ? amount : -amount;

  const insertTxn = db.prepare(
    'INSERT INTO transactions (customer_id, type, amount, note, source, created_by) VALUES (?, ?, ?, ?, ?, ?)'
  );
  const updateBalance = db.prepare('UPDATE customers SET balance = balance + ? WHERE id = ?');

  const runTransaction = db.transaction(() => {
    const info = insertTxn.run(customer_id, type, amount, note || null, 'app', req.user.id);
    updateBalance.run(balanceChange, customer_id);
    return info.lastInsertRowid;
  });

  const id = runTransaction();
  const updatedCustomer = db.prepare('SELECT * FROM customers WHERE id = ?').get(customer_id);
  notifyCustomer(customer, type, amount, updatedCustomer.balance);

  res.status(201).json({ id, message: 'Transaction recorded' });
});

// PUT /api/transactions/:id - Owner only (edit an existing entry)
router.put('/:id', ownerOnly, (req, res) => {
  const { type, amount, note } = req.body;
  const txn = db.prepare('SELECT * FROM transactions WHERE id = ?').get(req.params.id);
  if (!txn) return res.status(404).json({ error: 'Transaction not found' });

  const newType = type || txn.type;
  const newAmount = amount !== undefined ? amount : txn.amount;
  if (!['udhaar', 'wasooli'].includes(newType)) {
    return res.status(400).json({ error: 'type must be udhaar or wasooli' });
  }

  const oldEffect = txn.type === 'udhaar' ? -txn.amount : txn.amount; // undo old
  const newEffect = newType === 'udhaar' ? newAmount : -newAmount; // apply new

  const runUpdate = db.transaction(() => {
    db.prepare('UPDATE customers SET balance = balance + ? WHERE id = ?').run(oldEffect, txn.customer_id);
    db.prepare('UPDATE transactions SET type = ?, amount = ?, note = ? WHERE id = ?').run(
      newType,
      newAmount,
      note ?? txn.note,
      req.params.id
    );
    db.prepare('UPDATE customers SET balance = balance + ? WHERE id = ?').run(newEffect, txn.customer_id);
  });
  runUpdate();

  res.json({ message: 'Transaction updated' });
});

// DELETE /api/transactions/:id - Owner only
router.delete('/:id', ownerOnly, (req, res) => {
  const txn = db.prepare('SELECT * FROM transactions WHERE id = ?').get(req.params.id);
  if (!txn) return res.status(404).json({ error: 'Transaction not found' });

  const balanceChange = txn.type === 'udhaar' ? -txn.amount : txn.amount;

  const runDelete = db.transaction(() => {
    db.prepare('DELETE FROM transactions WHERE id = ?').run(req.params.id);
    db.prepare('UPDATE customers SET balance = balance + ? WHERE id = ?').run(
      balanceChange,
      txn.customer_id
    );
  });
  runDelete();

  res.json({ message: 'Transaction deleted and balance adjusted' });
});

module.exports = router;
