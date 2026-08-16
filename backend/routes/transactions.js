const express = require('express');
const db = require('../config/db');
const { authenticate, ownerOnly } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate);

// GET /api/transactions - Owner and Worker can view all transactions
router.get('/', (req, res) => {
  const transactions = db
    .prepare(
      `SELECT t.*, c.name as customer_name, c.house_number
       FROM transactions t
       JOIN customers c ON c.id = t.customer_id
       ORDER BY t.created_at DESC LIMIT 200`
    )
    .all();
  res.json(transactions);
});

// POST /api/transactions - Owner only (manual entry, e.g. correction or same-day entry made directly by owner)
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
  res.status(201).json({ id, message: 'Transaction recorded' });
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
