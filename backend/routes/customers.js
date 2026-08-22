const express = require('express');
const { db } = require('../config/db');
const { authenticate, ownerOnly } = require('../middleware/auth');
const crypto = require('crypto');
const { logAudit } = require('../utils/auditLog');
const router = express.Router();
router.use(authenticate); // all customer routes require login

// GET /api/customers/stats/total-balance
// Returns total outstanding balance across all customers
router.get('/stats/total-balance', async (req, res) => {
  try {
    const result = await db.execute('SELECT SUM(balance) as totalBalance FROM customers');
    const totalBalance = result.rows[0]?.totalBalance || 0;
    res.json({ totalBalance });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error fetching total balance' });
  }
});

// GET /api/customers - Owner and Worker can view. Optional ?search=name-or-phone
router.get('/', async (req, res) => {
  try {
    const { search } = req.query;
    let result;
    if (search && search.trim()) {
      const term = `%${search.trim()}%`;
      result = await db.execute({
        sql: `SELECT c.*, 
                (SELECT MAX(created_at) FROM transactions WHERE customer_id = c.id) as last_transaction_at 
              FROM customers c 
              WHERE c.name LIKE ? OR c.phone LIKE ? 
              ORDER BY c.name`,
        args: [term, term]
      });
    } else {
      result = await db.execute(`
        SELECT c.*, 
          (SELECT MAX(created_at) FROM transactions WHERE customer_id = c.id) as last_transaction_at 
        FROM customers c 
        ORDER BY c.name
      `);
    }
    res.json(result.rows);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error fetching customers' });
  }
});

// GET /api/customers/:id - single customer with transaction history
router.get('/:id', async (req, res) => {
  try {
    const custResult = await db.execute({
      sql: 'SELECT * FROM customers WHERE id = ?',
      args: [req.params.id]
    });
    const customer = custResult.rows[0];
    if (!customer) return res.status(404).json({ error: 'Customer not found' });

    const txResult = await db.execute({
      sql: 'SELECT * FROM transactions WHERE customer_id = ? ORDER BY created_at DESC',
      args: [req.params.id]
    });

    res.json({ ...customer, transactions: txResult.rows });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error fetching customer details' });
  }
});

// POST /api/customers - Owner only. Only Name + Phone required.
router.post('/', ownerOnly, async (req, res) => {
  try {
    const { name, phone } = req.body;
    if (!name || !phone) {
      return res.status(400).json({ error: 'Customer name and phone number are required' });
    }

    const info = await db.execute({
      sql: 'INSERT INTO customers (name, phone) VALUES (?, ?)',
      args: [name, phone]
    });

        const newId = Number(info.lastInsertRowid);
    await logAudit('customer', newId, 'create', `Customer "${name}" created (phone: ${phone})`, req.user.id);
    res.status(201).json({ id: newId, name, phone, balance: 0 });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error creating customer' });
  }
});

// PUT /api/customers/:id - Owner only
router.put('/:id', ownerOnly, async (req, res) => {
  try {
    const { name, phone } = req.body;
    const existResult = await db.execute({
      sql: 'SELECT * FROM customers WHERE id = ?',
      args: [req.params.id]
    });
    const existing = existResult.rows[0];
    if (!existing) return res.status(404).json({ error: 'Customer not found' });

        await db.execute({
      sql: 'UPDATE customers SET name = ?, phone = ? WHERE id = ?',
      args: [name || existing.name, phone || existing.phone, req.params.id]
    });

    await logAudit(
      'customer',
      req.params.id,
      'update',
      `Customer "${existing.name}" edited: name "${existing.name}" -> "${name || existing.name}", phone "${existing.phone}" -> "${phone || existing.phone}"`,
      req.user.id
    );

    res.json({ message: 'Customer updated' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error updating customer' });
  }
});

// DELETE /api/customers/:id - Owner only
router.delete('/:id', ownerOnly, async (req, res) => {
  try {
    const existResult = await db.execute({
      sql: 'SELECT * FROM customers WHERE id = ?',
      args: [req.params.id]
    });
    const existing = existResult.rows[0];
    if (!existing) return res.status(404).json({ error: 'Customer not found' });

    await db.execute({
      sql: 'DELETE FROM transactions WHERE customer_id = ?',
      args: [req.params.id]
    });
      await db.execute({
      sql: 'DELETE FROM customers WHERE id = ?',
      args: [req.params.id]
    });

    await logAudit('customer', req.params.id, 'delete', `Customer "${existing.name}" deleted (balance was Rs ${existing.balance})`, req.user.id);

    res.json({ message: 'Customer deleted' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error deleting customer' });
  }
});

module.exports = router;