const express = require('express');
const { db } = require('../config/db');
const { authenticate, ownerOnly } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate, ownerOnly); // entire module is Owner-only

const VALID_CATEGORIES = ['monthly_expense', 'daily_online', 'daily_main_branch_purchase'];

// GET /api/expenses/monthly-total/:category
// Returns the sum of expenses for the current month
router.get('/monthly-total/:category', async (req, res) => {
  try {
    const { category } = req.params;
    if (!VALID_CATEGORIES.includes(category)) {
      return res.status(400).json({ error: 'Invalid category' });
    }

    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const monthStart = `${year}-${month}-01`;
    
    // Calculate month end
    const lastDay = new Date(year, now.getMonth() + 1, 0).getDate();
    const monthEnd = `${year}-${month}-${String(lastDay).padStart(2, '0')}`;

    const result = await db.execute({
      sql: 'SELECT SUM(amount) as total FROM expenses WHERE category = ? AND entry_date BETWEEN ? AND ?',
      args: [category, monthStart, monthEnd]
    });

    const total = result.rows[0]?.total || 0;
    res.json({ 
      category, 
      total, 
      monthStart, 
      monthEnd, 
      month: `${month}/${year}` 
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error fetching monthly total' });
  }
});

// GET /api/expenses/daily-total/:category
// Returns the sum of expenses for today
router.get('/daily-total/:category', async (req, res) => {
  try {
    const { category } = req.params;
    if (!VALID_CATEGORIES.includes(category)) {
      return res.status(400).json({ error: 'Invalid category' });
    }

    const today = new Date().toISOString().split('T')[0];

    const result = await db.execute({
      sql: 'SELECT SUM(amount) as total FROM expenses WHERE category = ? AND entry_date = ?',
      args: [category, today]
    });

    const total = result.rows[0]?.total || 0;
    res.json({ 
      category, 
      total, 
      date: today 
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error fetching daily total' });
  }
});

// GET /api/expenses/:category
router.get('/:category', async (req, res) => {
  try {
    const { category } = req.params;
    if (!VALID_CATEGORIES.includes(category)) {
      return res.status(400).json({ error: 'Invalid category' });
    }
    const result = await db.execute({
      sql: 'SELECT * FROM expenses WHERE category = ? ORDER BY entry_date DESC, created_at DESC',
      args: [category]
    });
    res.json(result.rows);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error fetching expenses' });
  }
});

// POST /api/expenses/:category
router.post('/:category', async (req, res) => {
  try {
    const { category } = req.params;
    if (!VALID_CATEGORIES.includes(category)) {
      return res.status(400).json({ error: 'Invalid category' });
    }
    const { amount, note, entry_date } = req.body;
    if (!amount) return res.status(400).json({ error: 'amount is required' });

    const result = await db.execute({
      sql: 'INSERT INTO expenses (category, amount, note, entry_date, created_by) VALUES (?, ?, ?, ?, ?)',
      args: [category, amount, note || null, entry_date || new Date().toISOString().slice(0, 10), req.user.id]
    });

    res.status(201).json({ id: Number(result.lastInsertRowid) });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error creating expense' });
  }
});

// PUT /api/expenses/entry/:id
router.put('/entry/:id', async (req, res) => {
  try {
    const checkResult = await db.execute({
      sql: 'SELECT * FROM expenses WHERE id = ?',
      args: [req.params.id]
    });
    const existing = checkResult.rows[0];
    if (!existing) return res.status(404).json({ error: 'Entry not found' });

    const { amount, note, entry_date } = req.body;
    await db.execute({
      sql: 'UPDATE expenses SET amount = ?, note = ?, entry_date = ? WHERE id = ?',
      args: [
        amount ?? existing.amount,
        note ?? existing.note,
        entry_date ?? existing.entry_date,
        req.params.id
      ]
    });
    res.json({ message: 'Entry updated' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error updating expense' });
  }
});

// DELETE /api/expenses/entry/:id
router.delete('/entry/:id', async (req, res) => {
  try {
    const checkResult = await db.execute({
      sql: 'SELECT * FROM expenses WHERE id = ?',
      args: [req.params.id]
    });
    const existing = checkResult.rows[0];
    if (!existing) return res.status(404).json({ error: 'Entry not found' });

    await db.execute({
      sql: 'DELETE FROM expenses WHERE id = ?',
      args: [req.params.id]
    });
    res.json({ message: 'Entry deleted' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error deleting expense' });
  }
});

module.exports = router;
