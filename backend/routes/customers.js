const express = require('express');
const { db } = require('../config/db');
const { authenticate, ownerOnly } = require('../middleware/auth');
const crypto = require('crypto');
const PDFDocument = require('pdfkit');
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
// GET /api/customers/balances/pdf
// Simple snapshot: name + phone + current balance for every customer.
// NO transaction history — just the final number per customer.
router.get('/balances/pdf', ownerOnly, async (req, res) => {
  try {
    const result = await db.execute(`
      SELECT name, phone, balance FROM customers
      WHERE balance != 0
      ORDER BY balance DESC
    `);
    const customers = result.rows;

    const doc = new PDFDocument({ margin: 40, size: 'A4' });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="all_balances.pdf"`);
    doc.pipe(res);

    doc.fontSize(18).text('All Customer Balances', { align: 'center' });
    doc.moveDown(0.3);
    const today = new Date().toISOString().split('T')[0];
    doc.fontSize(11).fillColor('#555').text(`As of ${today}`, { align: 'center' });
    doc.moveDown(1);

    const totalOutstanding = customers.reduce((sum, c) => sum + (c.balance || 0), 0);
    doc.fontSize(12).fillColor('#000')
      .text(`Total Customers Listed: ${customers.length}`)
      .text(`Total Outstanding: Rs ${totalOutstanding.toFixed(0)}`);
    doc.moveDown(1);

    let y = doc.y;
    doc.fontSize(10).fillColor('#000');
    doc.text('Name', 40, y, { width: 220 });
    doc.text('Phone', 270, y, { width: 130 });
    doc.text('Balance', 420, y, { width: 100 });
    y += 16;
    doc.moveTo(40, y).lineTo(555, y).stroke();
    y += 6;

    for (const c of customers) {
      if (y > 770) {
        doc.addPage();
        y = 40;
      }
      const bal = c.balance || 0;
      doc.fontSize(9).fillColor('#000').text(c.name || '', 40, y, { width: 220 });
      doc.text(c.phone || 'No phone', 270, y, { width: 130 });
      doc.fillColor(bal > 0 ? '#c0392b' : '#27ae60')
        .text(`Rs ${bal.toFixed(0)}`, 420, y, { width: 100 });
      y += 16;
    }

    // Total row
    y += 6;
    doc.moveTo(40, y).lineTo(555, y).stroke();
    y += 8;
    doc.fontSize(10).fillColor('#000').text('Total', 40, y, { width: 220 });
    doc.text(`Rs ${totalOutstanding.toFixed(0)}`, 420, y, { width: 100 });

    doc.end();
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error generating balances PDF' });
  }
});
module.exports = router;