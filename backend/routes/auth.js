const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

// IMPORT UPDATE: Ab hum destructured db le rahe hain
const { db } = require('../config/db');
const { authenticate, ownerOnly } = require('../middleware/auth');

const router = express.Router();

// POST /api/auth/login
router.post('/login', async (req, res) => {
  try {
    const { username, password } = req.body;
    if (!username || !password) {
      return res.status(400).json({ error: 'Username and password required' });
    }

    const result = await db.execute({
      sql: 'SELECT * FROM users WHERE username = ?',
      args: [username]
    });
    const user = result.rows[0];
    
    if (!user) return res.status(401).json({ error: 'Invalid credentials' });

    const valid = bcrypt.compareSync(password, user.password_hash);
    if (!valid) return res.status(401).json({ error: 'Invalid credentials' });

    const token = jwt.sign(
      { id: user.id, name: user.name, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    res.json({ token, user: { id: user.id, name: user.name, role: user.role } });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error during login' });
  }
});

// POST /api/auth/create-worker  (Owner only - creates worker logins)
router.post('/create-worker', authenticate, ownerOnly, async (req, res) => {
  try {
    const { name, username, password } = req.body;
    if (!name || !username || !password) {
      return res.status(400).json({ error: 'name, username, password required' });
    }

    const existResult = await db.execute({
      sql: 'SELECT id FROM users WHERE username = ?',
      args: [username]
    });
    if (existResult.rows.length > 0) return res.status(409).json({ error: 'Username already exists' });

    const hash = bcrypt.hashSync(password, 10);
    const info = await db.execute({
      sql: 'INSERT INTO users (name, username, password_hash, role) VALUES (?, ?, ?, ?)',
      args: [name, username, hash, 'worker']
    });

    res.status(201).json({ id: Number(info.lastInsertRowid), name, username, role: 'worker' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error creating worker' });
  }
});

// GET /api/auth/workers - Owner only, list all worker accounts
router.get('/workers', authenticate, ownerOnly, async (req, res) => {
  try {
    const result = await db.execute(
      "SELECT id, name, username, created_at FROM users WHERE role = 'worker' ORDER BY created_at DESC"
    );
    res.json(result.rows);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error fetching workers' });
  }
});

// DELETE /api/auth/workers/:id - Owner only
router.delete('/workers/:id', authenticate, ownerOnly, async (req, res) => {
  try {
    const result = await db.execute({
      sql: "SELECT * FROM users WHERE id = ? AND role = 'worker'",
      args: [req.params.id]
    });
    const worker = result.rows[0];
    
    if (!worker) return res.status(404).json({ error: 'Worker not found' });

    await db.execute({
      sql: 'DELETE FROM users WHERE id = ?',
      args: [req.params.id]
    });
    res.json({ message: 'Worker account deleted' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error deleting worker' });
  }
});

// POST /api/auth/change-password - any logged-in user can change their OWN password
router.post('/change-password', authenticate, async (req, res) => {
  try {
    const { currentPassword, newPassword } = req.body;
    if (!currentPassword || !newPassword) {
      return res.status(400).json({ error: 'currentPassword and newPassword required' });
    }
    if (newPassword.length < 4) {
      return res.status(400).json({ error: 'New password must be at least 4 characters' });
    }

    const result = await db.execute({
      sql: 'SELECT * FROM users WHERE id = ?',
      args: [req.user.id]
    });
    const user = result.rows[0];

    const valid = bcrypt.compareSync(currentPassword, user.password_hash);
    if (!valid) return res.status(401).json({ error: 'Current password is incorrect' });

    const newHash = bcrypt.hashSync(newPassword, 10);
    await db.execute({
      sql: 'UPDATE users SET password_hash = ? WHERE id = ?',
      args: [newHash, req.user.id]
    });

    res.json({ message: 'Password changed successfully' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error changing password' });
  }
});

module.exports = router;