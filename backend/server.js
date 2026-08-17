require('dotenv').config();
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');

const db = require('./config/db');
const authRoutes = require('./routes/auth');
const customerRoutes = require('./routes/customers');
const transactionRoutes = require('./routes/transactions');
const sheetsSyncRoutes = require('./routes/sheetsSync');
const expensesRoutes = require('./routes/expenses');

const app = express();
app.use(cors());
app.use(express.json());

app.get('/', (req, res) => {
  res.json({ status: 'ok', message: 'Udhaar Management API is running' });
});

app.use('/api/auth', authRoutes);
app.use('/api/customers', customerRoutes);
app.use('/api/transactions', transactionRoutes);
app.use('/api/sheets-sync', sheetsSyncRoutes);
app.use('/api/expenses', expensesRoutes);

// Auto-create a default Owner account on first run if no users exist yet
const userCount = db.prepare('SELECT COUNT(*) as count FROM users').get().count;
if (userCount === 0) {
  const hash = bcrypt.hashSync('owner123', 10);
  db.prepare(
    'INSERT INTO users (name, username, password_hash, role) VALUES (?, ?, ?, ?)'
  ).run('Shop Owner', 'owner', hash, 'owner');
  console.log('Default Owner account created -> username: owner | password: owner123 (change this!)');
}

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Udhaar backend running on http://localhost:${PORT}`);
});
