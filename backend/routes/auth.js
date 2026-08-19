const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('../config/db');
const { authenticate, ownerOnly } = require('../middleware/auth');

const router = express.Router();

// POST /api/auth/login
router.post('/login', (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password required' });
  }

  const user = db.prepare('SELECT * FROM users WHERE username = ?').get(username);
  if (!user) return res.status(401).json({ error: 'Invalid credentials' });

  const valid = bcrypt.compareSync(password, user.password_hash);
  if (!valid) return res.status(401).json({ error: 'Invalid credentials' });

  const token = jwt.sign(
    { id: user.id, name: user.name, role: user.role },
    process.env.JWT_SECRET,
    { expiresIn: '30d' }
  );

  res.json({ token, user: { id: user.id, name: user.name, role: user.role } });
});

// POST /api/auth/create-worker  (Owner only - creates worker logins)
router.post('/create-worker', authenticate, ownerOnly, (req, res) => {
  const { name, username, password } = req.body;
  if (!name || !username || !password) {
    return res.status(400).json({ error: 'name, username, password required' });
  }

  const existing = db.prepare('SELECT id FROM users WHERE username = ?').get(username);
  if (existing) return res.status(409).json({ error: 'Username already exists' });

  const hash = bcrypt.hashSync(password, 10);
  const info = db
    .prepare('INSERT INTO users (name, username, password_hash, role) VALUES (?, ?, ?, ?)')
    .run(name, username, hash, 'worker');

  res.status(201).json({ id: info.lastInsertRowid, name, username, role: 'worker' });
});

// GET /api/auth/workers - Owner only, list all worker accounts
router.get('/workers', authenticate, ownerOnly, (req, res) => {
  const workers = db
    .prepare("SELECT id, name, username, created_at FROM users WHERE role = 'worker' ORDER BY created_at DESC")
    .all();
  res.json(workers);
});

// DELETE /api/auth/workers/:id - Owner only
router.delete('/workers/:id', authenticate, ownerOnly, (req, res) => {
  const worker = db.prepare("SELECT * FROM users WHERE id = ? AND role = 'worker'").get(req.params.id);
  if (!worker) return res.status(404).json({ error: 'Worker not found' });

  db.prepare('DELETE FROM users WHERE id = ?').run(req.params.id);
  res.json({ message: 'Worker account deleted' });
});

// POST /api/auth/change-password - any logged-in user can change their OWN password
router.post('/change-password', authenticate, (req, res) => {
  const { currentPassword, newPassword } = req.body;
  if (!currentPassword || !newPassword) {
    return res.status(400).json({ error: 'currentPassword and newPassword required' });
  }
  if (newPassword.length < 4) {
    return res.status(400).json({ error: 'New password must be at least 4 characters' });
  }

  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
  const valid = bcrypt.compareSync(currentPassword, user.password_hash);
  if (!valid) return res.status(401).json({ error: 'Current password is incorrect' });

  const newHash = bcrypt.hashSync(newPassword, 10);
  db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(newHash, req.user.id);

  res.json({ message: 'Password changed successfully' });
});

module.exports = router;
