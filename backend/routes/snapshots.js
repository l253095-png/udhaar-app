const express = require('express');
const { db } = require('../config/db');
const { authenticate, ownerOnly } = require('../middleware/auth');
const { logAudit } = require('../utils/auditLog');

const router = express.Router();
router.use(authenticate, ownerOnly); // Owner-only, same as expenses.js

// GET /api/snapshots
// Full history, most recent first.
router.get('/', async (req, res) => {
  try {
    const result = await db.execute(
      'SELECT * FROM financial_snapshots ORDER BY snapshot_date DESC, created_at DESC'
    );
    res.json(result.rows);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error fetching snapshots' });
  }
});

// GET /api/snapshots/status
// Latest snapshot + how many days since + whether a new one is due (>= 15 days,
// or no snapshot has ever been taken). Used to show the reminder on Home.
router.get('/status', async (req, res) => {
  try {
    const result = await db.execute(
      'SELECT * FROM financial_snapshots ORDER BY snapshot_date DESC, created_at DESC LIMIT 1'
    );
    const latest = result.rows[0] || null;

    let daysSince = null;
    let due = true; // no snapshot ever taken -> due immediately

    if (latest) {
      const last = new Date(`${latest.snapshot_date}T00:00:00`);
      const today = new Date();
      const todayMidnight = new Date(today.getFullYear(), today.getMonth(), today.getDate());
      daysSince = Math.floor((todayMidnight - last) / (1000 * 60 * 60 * 24));
      due = daysSince >= 15;
    }

    res.json({ latest, daysSince, due });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error fetching snapshot status' });
  }
});

// POST /api/snapshots
// Body: { stockPosition, cashOnHand }
// udhaarTotal is NEVER trusted from the client — always pulled fresh from the
// customers table server-side, same query as /api/customers/stats/total-balance.
router.post('/', async (req, res) => {
  try {
    const { stockPosition, cashOnHand } = req.body;
    if (stockPosition == null || cashOnHand == null) {
      return res.status(400).json({ error: 'stockPosition and cashOnHand are required' });
    }
    const stock = Number(stockPosition);
    const cash = Number(cashOnHand);
    if (Number.isNaN(stock) || Number.isNaN(cash)) {
      return res.status(400).json({ error: 'stockPosition and cashOnHand must be numbers' });
    }

    const udhaarResult = await db.execute('SELECT SUM(balance) as totalBalance FROM customers');
    const udhaarTotal = udhaarResult.rows[0]?.totalBalance || 0;
    const total = stock + cash + udhaarTotal;

    const insertResult = await db.execute({
      sql: `INSERT INTO financial_snapshots
              (stock_position, cash_on_hand, udhaar_total, total, created_by)
            VALUES (?, ?, ?, ?, ?)`,
      args: [stock, cash, udhaarTotal, total, req.user.id]
    });

    const id = Number(insertResult.lastInsertRowid);

    await logAudit(
      'financial_snapshot',
      id,
      'create',
      `Snapshot added — Stock Rs ${stock.toFixed(0)}, Cash Rs ${cash.toFixed(0)}, Udhaar Rs ${udhaarTotal.toFixed(0)}, Total Rs ${total.toFixed(0)}`,
      req.user.id
    );

    res.status(201).json({ id, stockPosition: stock, cashOnHand: cash, udhaarTotal, total });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error creating snapshot' });
  }
});

module.exports = router;