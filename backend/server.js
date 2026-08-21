require('dotenv').config();
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');

// Naya import: db aur initDb dono le rahe hain
const { db, initDb } = require('./config/db');

const authRoutes = require('./routes/auth');
const customerRoutes = require('./routes/customers');
const transactionRoutes = require('./routes/transactions');
const sheetsSyncRoutes = require('./routes/sheetsSync');
const expensesRoutes = require('./routes/expenses');

const path = require('path');

const app = express();
app.use(cors());
app.use(express.json());

// API routes
app.use('/api/auth', authRoutes);
app.use('/api/customers', customerRoutes);
app.use('/api/transactions', transactionRoutes);
app.use('/api/sheets-sync', sheetsSyncRoutes);
app.use('/api/expenses', expensesRoutes);

// Serve Flutter Web release build statically
const webBuildPath = path.join(__dirname, '../frontend/build/web');
app.use(express.static(webBuildPath));

app.get('*', (req, res, next) => {
  if (req.path.startsWith('/api/')) return next();
  const indexHtml = path.join(webBuildPath, 'index.html');
  if (require('fs').existsSync(indexHtml)) {
    return res.sendFile(indexHtml);
  }
  res.json({ status: 'ok', message: 'Udhaar Management API is running' });
});

const PORT = process.env.PORT || 3000;

// Naya async startup sequence
async function startServer() {
  try {
    // 1. Database schema aur migrations ko initialize karein
    await initDb();

    // 2. Auto-create a default Owner account on first run if no users exist yet
    const userCountResult = await db.execute('SELECT COUNT(*) as count FROM users');
    const userCount = Number(userCountResult.rows[0].count);

    if (userCount === 0) {
      const hash = bcrypt.hashSync('owner123', 10);
      await db.execute({
        sql: 'INSERT INTO users (name, username, password_hash, role) VALUES (?, ?, ?, ?)',
        args: ['Shop Owner', 'owner', hash, 'owner']
      });
      console.log('Default Owner account created -> username: owner | password: owner123 (change this!)');
    }

    // 3. Server start karein
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`Udhaar backend running on http://127.0.0.1:${PORT}`);
    });
  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
}

// Server ko execute karein
startServer();