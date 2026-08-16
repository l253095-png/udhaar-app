const express = require('express');
const db = require('../config/db');
const { authenticate, ownerOnly } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate); // all customer routes require login

// GET /api/customers - Owner and Worker can view
router.get('/', (req, res) => {
  const customers = db.prepare('SELECT * FROM customers ORDER BY name').all();
  res.json(customers);
});

// GET /api/customers/:id - single customer with transaction history
router.get('/:id', (req, res) => {
  const customer = db.prepare('SELECT * FROM customers WHERE id = ?').get(req.params.id);
  if (!customer) return res.status(404).json({ error: 'Customer not found' });

  const transactions = db
    .prepare('SELECT * FROM transactions WHERE customer_id = ? ORDER BY created_at DESC')
    .all(req.params.id);

  res.json({ ...customer, transactions });
});

// POST /api/customers - Owner only
router.post('/', ownerOnly, (req, res) => {
  const { name, phone, house_number, address } = req.body;
  if (!name) return res.status(400).json({ error: 'Customer name is required' });

  const info = db
    .prepare('INSERT INTO customers (name, phone, house_number, address) VALUES (?, ?, ?, ?)')
    .run(name, phone || null, house_number || null, address || null);

  res.status(201).json({ id: info.lastInsertRowid, name, phone, house_number, address, balance: 0 });
});

// PUT /api/customers/:id - Owner only
router.put('/:id', ownerOnly, (req, res) => {
  const { name, phone, house_number, address } = req.body;
  const existing = db.prepare('SELECT * FROM customers WHERE id = ?').get(req.params.id);
  if (!existing) return res.status(404).json({ error: 'Customer not found' });

  db.prepare(
    'UPDATE customers SET name = ?, phone = ?, house_number = ?, address = ? WHERE id = ?'
  ).run(
    name || existing.name,
    phone ?? existing.phone,
    house_number ?? existing.house_number,
    address ?? existing.address,
    req.params.id
  );

  res.json({ message: 'Customer updated' });
});

// DELETE /api/customers/:id - Owner only
router.delete('/:id', ownerOnly, (req, res) => {
  const existing = db.prepare('SELECT * FROM customers WHERE id = ?').get(req.params.id);
  if (!existing) return res.status(404).json({ error: 'Customer not found' });

  db.prepare('DELETE FROM transactions WHERE customer_id = ?').run(req.params.id);
  db.prepare('DELETE FROM customers WHERE id = ?').run(req.params.id);

  res.json({ message: 'Customer deleted' });
});

module.exports = router;
