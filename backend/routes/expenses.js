const express = require('express');
const db = require('../config/db');
const { authenticate, ownerOnly } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate, ownerOnly); // entire module is Owner-only

const VALID_CATEGORIES = ['monthly_expense', 'daily_online', 'daily_main_branch_purchase'];

// GET /api/expenses/monthly-total/:category
// Returns the sum of expenses for the current month
router.get('/monthly-total/:category', (req, res) => {
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

  const result = db
    .prepare(
      'SELECT SUM(amount) as total FROM expenses WHERE category = ? AND entry_date BETWEEN ? AND ?'
    )
    .get(category, monthStart, monthEnd);

  const total = result.total || 0;
  res.json({ 
    category, 
    total, 
    monthStart, 
    monthEnd,
    month: `${month}/${year}` 
  });
});

// GET /api/expenses/daily-total/:category
// Returns the sum of expenses for today
router.get('/daily-total/:category', (req, res) => {
  const { category } = req.params;
  if (!VALID_CATEGORIES.includes(category)) {
    return res.status(400).json({ error: 'Invalid category' });
  }

  const today = new Date().toISOString().split('T')[0];

  const result = db
    .prepare(
      'SELECT SUM(amount) as total FROM expenses WHERE category = ? AND entry_date = ?'
    )
    .get(category, today);

  const total = result.total || 0;
  res.json({ 
    category, 
    total, 
    date: today
  });
});

// GET /api/expenses/:category
router.get('/:category', (req, res) => {
  const { category } = req.params;
  if (!VALID_CATEGORIES.includes(category)) {
    return res.status(400).json({ error: 'Invalid category' });
  }
  const rows = db
    .prepare('SELECT * FROM expenses WHERE category = ? ORDER BY entry_date DESC, created_at DESC')
    .all(category);
  res.json(rows);
});

// POST /api/expenses/:category
router.post('/:category', (req, res) => {
  const { category } = req.params;
  if (!VALID_CATEGORIES.includes(category)) {
    return res.status(400).json({ error: 'Invalid category' });
  }
  const { amount, note, entry_date } = req.body;
  if (!amount) return res.status(400).json({ error: 'amount is required' });

  const info = db
    .prepare('INSERT INTO expenses (category, amount, note, entry_date, created_by) VALUES (?, ?, ?, ?, ?)')
    .run(category, amount, note || null, entry_date || new Date().toISOString().slice(0, 10), req.user.id);

  res.status(201).json({ id: info.lastInsertRowid });
});

// PUT /api/expenses/entry/:id
router.put('/entry/:id', (req, res) => {
  const existing = db.prepare('SELECT * FROM expenses WHERE id = ?').get(req.params.id);
  if (!existing) return res.status(404).json({ error: 'Entry not found' });

  const { amount, note, entry_date } = req.body;
  db.prepare('UPDATE expenses SET amount = ?, note = ?, entry_date = ? WHERE id = ?').run(
    amount ?? existing.amount,
    note ?? existing.note,
    entry_date ?? existing.entry_date,
    req.params.id
  );
  res.json({ message: 'Entry updated' });
});

// DELETE /api/expenses/entry/:id
router.delete('/entry/:id', (req, res) => {
  const existing = db.prepare('SELECT * FROM expenses WHERE id = ?').get(req.params.id);
  if (!existing) return res.status(404).json({ error: 'Entry not found' });

  db.prepare('DELETE FROM expenses WHERE id = ?').run(req.params.id);
  res.json({ message: 'Entry deleted' });
});

module.exports = router;
