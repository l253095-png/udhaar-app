const express = require('express');
const { db } = require('../config/db');
const { authenticate, ownerOnly } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate);

// GET /api/audit-log - Owner only. Full history of add/edit/delete actions.
router.get('/', ownerOnly, async (req, res) => {
  try {
    const result = await db.execute(`
      SELECT a.*, u.name as performed_by_name
      FROM audit_log a
      LEFT JOIN users u ON u.id = a.performed_by
      ORDER BY a.created_at DESC
      LIMIT 500
    `);
    res.json(result.rows);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error fetching audit log' });
  }
});

module.exports = router;