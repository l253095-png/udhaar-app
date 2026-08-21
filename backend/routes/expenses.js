const express = require('express');
const { db } = require('../config/db');
const { nowLocal, todayLocal } = require('../config/timeHelper');
const { authenticate, ownerOnly } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate, ownerOnly); // entire module is Owner-only

const VALID_CATEGORIES = ['monthly_expense', 'daily_online', 'daily_main_branch_purchase'];

// GET /api/expenses/monthly-total/:category
// Returns the sum of expenses for the current month
router.get('/monthly-total/:category', async (req, res) => {
  const { category } = req.params;
  if (!VALID_CATEGORIES.includes(category)) {
    return res.status(400).json({ error: 'Invalid category' });
  }

  try {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const monthStart = `${year}-${month}-01`;

    const lastDay = new Date(year, now.getMonth() + 1, 0).getDate();
    const monthEnd = `${year}-${month}-${String(lastDay).padStart(2, '0')}`;

    const result = await db.execute({
      sql: 'SELECT SUM(amount) as total FROM expenses WHERE category = ? AND entry_date BETWEEN ? AND ?',
      args: [category, monthStart, monthEnd],
    });

    const total = result.rows[0]?.total || 0;
    res.json({ category, total, monthStart, monthEnd, month: `${month}/${year}` });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to get monthly total', details: err.message });
  }
});

// GET /api/expenses/daily-total/:category
// Returns the sum of expenses for today
router.get('/daily-total/:category', async (req, res) => {
  const { category } = req.params;
  if (!VALID_CATEGORIES.includes(category)) {
    return res.status(400).json({ error: 'Invalid category' });
  }

  try {
    const today = todayLocal();
    const result = await db.execute({
      sql: 'SELECT SUM(amount) as total FROM expenses WHERE category = ? AND entry_date = ?',
      args: [category, today],
    });

    const total = result.rows[0]?.total || 0;
    res.json({ category, total, date: today });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to get daily total', details: err.message });
  }
});

// GET /api/expenses/:category
router.get('/:category', async (req, res) => {
  const { category } = req.params;
  if (!VALID_CATEGORIES.includes(category)) {
    return res.status(400).json({ error: 'Invalid category' });
  }
  try {
    const result = await db.execute({
      sql: 'SELECT * FROM expenses WHERE category = ? ORDER BY entry_date DESC, created_at DESC',
      args: [category],
    });
    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to list expenses', details: err.message });
  }
});

// POST /api/expenses/:category
router.post('/:category', async (req, res) => {
  const { category } = req.params;
  if (!VALID_CATEGORIES.includes(category)) {
    return res.status(400).json({ error: 'Invalid category' });
  }
  const { amount, note, entry_date } = req.body;
  if (!amount) return res.status(400).json({ error: 'amount is required' });

  try {
    const info = await db.execute({
      sql: 'INSERT INTO expenses (category, amount, note, entry_date, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?)',
      args: [category, amount, note || null, entry_date || todayLocal(), req.user.id, nowLocal()],
    });
    res.status(201).json({ id: Number(info.lastInsertRowid) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to add expense', details: err.message });
  }
});

// PUT /api/expenses/entry/:id
router.put('/entry/:id', async (req, res) => {
  try {
    const found = await db.execute({
      sql: 'SELECT * FROM expenses WHERE id = ?',
      args: [req.params.id],
    });
    const existing = found.rows[0];
    if (!existing) return res.status(404).json({ error: 'Entry not found' });

    const { amount, note, entry_date } = req.body;
    await db.execute({
      sql: 'UPDATE expenses SET amount = ?, note = ?, entry_date = ? WHERE id = ?',
      args: [
        amount ?? existing.amount,
        note ?? existing.note,
        entry_date ?? existing.entry_date,
        req.params.id,
      ],
    });
    res.json({ message: 'Entry updated' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to update entry', details: err.message });
  }
});

// DELETE /api/expenses/entry/:id
router.delete('/entry/:id', async (req, res) => {
  try {
    const found = await db.execute({
      sql: 'SELECT * FROM expenses WHERE id = ?',
      args: [req.params.id],
    });
    if (!found.rows[0]) return res.status(404).json({ error: 'Entry not found' });

    await db.execute({ sql: 'DELETE FROM expenses WHERE id = ?', args: [req.params.id] });
    res.json({ message: 'Entry deleted' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to delete entry', details: err.message });
  }
});

module.exports = router;
