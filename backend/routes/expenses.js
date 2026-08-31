const express = require('express');
const { db } = require('../config/db');
const { authenticate, ownerOnly } = require('../middleware/auth');
const { logAudit } = require('../utils/auditLog');

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
router.get('/net-summary', async (req, res) => {
  try {
    const now = new Date();
    const year = parseInt(req.query.year) || now.getFullYear();
    const month = parseInt(req.query.month) || (now.getMonth() + 1);
    const ym = `${year}-${String(month).padStart(2, '0')}`;

    const result = await db.execute({
      sql: `SELECT
              SUM(CASE WHEN category='daily_online' THEN amount ELSE 0 END) as online,
              SUM(CASE WHEN category='daily_main_branch_purchase' THEN amount ELSE 0 END) as mainBranch,
              SUM(CASE WHEN category='monthly_expense' THEN amount ELSE 0 END) as expense
            FROM expenses
            WHERE strftime('%Y-%m', entry_date) = ? AND settled_at IS NULL`,
      args: [ym]
    });

    const row = result.rows[0] || {};
    const online = row.online || 0;
    const mainBranch = row.mainBranch || 0;
    const expense = row.expense || 0;
    const net = online - mainBranch - expense;

    // Is this the current, still-in-progress month?
    const isCurrentMonth = year === now.getFullYear() && month === (now.getMonth() + 1);
    const lastDayOfMonth = new Date(year, month, 0).getDate();
    const isLastDay = isCurrentMonth && now.getDate() === lastDayOfMonth;

    res.json({ year, month, ym, online, mainBranch, expense, net, isCurrentMonth, isLastDay });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error fetching net summary' });
  }
});

// POST /api/expenses/net-summary/settle
// "Clear balance" icon on the Monthly Net Summary screen.
// Marks all of THIS MONTH'S currently-unsettled entries as settled (settled_at = now),
// so the live "This Month" total goes back to Rs 0 going forward — WITHOUT deleting
// any rows, so "Previous Months" history and the audit log stay accurate forever.
// Nothing here is destructive: it's a checkpoint, not a delete.
router.post('/net-summary/settle', async (req, res) => {
  try {
    const now = new Date();
    const ym = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;

    const result = await db.execute({
      sql: `SELECT
              SUM(CASE WHEN category='daily_online' THEN amount ELSE 0 END) as online,
              SUM(CASE WHEN category='daily_main_branch_purchase' THEN amount ELSE 0 END) as mainBranch,
              SUM(CASE WHEN category='monthly_expense' THEN amount ELSE 0 END) as expense
            FROM expenses
            WHERE strftime('%Y-%m', entry_date) = ? AND settled_at IS NULL`,
      args: [ym]
    });
    const row = result.rows[0] || {};
    const online = row.online || 0;
    const mainBranch = row.mainBranch || 0;
    const expense = row.expense || 0;
    const net = online - mainBranch - expense;

    if (online === 0 && mainBranch === 0 && expense === 0) {
      return res.status(400).json({ error: 'Nothing to clear — this month already has no unsettled entries.' });
    }

    await db.execute({
      sql: `UPDATE expenses SET settled_at = datetime('now', 'localtime')
            WHERE strftime('%Y-%m', entry_date) = ? AND settled_at IS NULL`,
      args: [ym]
    });

    await logAudit(
      'net_summary',
      null,
      'settle',
      `Monthly Net Summary cleared for ${ym}: Online Rs ${online.toFixed(0)}, Main Branch Rs ${mainBranch.toFixed(0)}, Expenses Rs ${expense.toFixed(0)}, Net Rs ${net.toFixed(0)} settled`,
      req.user.id
    );

    res.json({ message: 'Cleared', ym, online, mainBranch, expense, net });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error settling net summary' });
  }
});

// GET /api/expenses/net-summary-history
// Past months' net totals (excludes current month), most recent first
router.get('/net-summary-history', async (req, res) => {
  try {
    const now = new Date();
    const currentYm = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;

    const result = await db.execute(`
      SELECT
        strftime('%Y-%m', entry_date) as ym,
        SUM(CASE WHEN category='daily_online' THEN amount ELSE 0 END) as online,
        SUM(CASE WHEN category='daily_main_branch_purchase' THEN amount ELSE 0 END) as mainBranch,
        SUM(CASE WHEN category='monthly_expense' THEN amount ELSE 0 END) as expense
      FROM expenses
      GROUP BY ym
      ORDER BY ym DESC
      LIMIT 13
    `);

    const history = result.rows
      .filter(r => r.ym !== currentYm)
      .map(r => ({
        ym: r.ym,
        online: r.online || 0,
        mainBranch: r.mainBranch || 0,
        expense: r.expense || 0,
        net: (r.online || 0) - (r.mainBranch || 0) - (r.expense || 0)
      }));

    res.json(history);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error fetching history' });
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
// GET /api/expenses/net-summary?year=2026&month=8
// Breakdown for one month: online - mainBranch - expense = net

module.exports = router;