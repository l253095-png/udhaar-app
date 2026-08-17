const express = require('express');
const { google } = require('googleapis');
const path = require('path');
const db = require('../config/db');
const { authenticate, ownerOnly } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate, ownerOnly); // sync is Owner-only, always

let sendWhatsAppMessage = async () => {};
try {
  sendWhatsAppMessage = require('../services/whatsapp').sendWhatsAppMessage;
} catch (e) {
  // WhatsApp module not installed yet - sync still works, just no messages sent
}

// ============================================================
// SHEET LAYOUT (matches the owner's real daily ledger sheet)
// Each day has its own tab, named like "3.4.2026" (d.M.yyyy)
// ============================================================
const BLOCKS = [
  // Udhaar (debit) - customer took goods, owes money
  { range: 'A2:B50', nameCol: 0, amountCol: 1, type: 'udhaar', key: 'udhaar1' },
  { range: 'A52:B71', nameCol: 0, amountCol: 1, type: 'udhaar', key: 'udhaar2' },
  // Wasooli (credit) - customer paid / cleared their khata
  { range: 'I2:J50', nameCol: 0, amountCol: 1, type: 'wasooli', key: 'wasooli1' },
  { range: 'M2:N16', nameCol: 0, amountCol: 1, type: 'wasooli', key: 'wasooli2' },
];

// Single running-total cells that feed the 3 dashboard expense modules
const SINGLE_CELLS = {
  monthly_expense: 'D51', // "Daily Expense" cell - daily figure, rolled up into Monthly Expense screen
  daily_online: 'J72',
  daily_main_branch_purchase: 'N24',
};

function getSheetsClient() {
  const keyPath =
    process.env.GOOGLE_SERVICE_ACCOUNT_KEY_PATH ||
    path.join(__dirname, '..', 'config', 'service-account-key.json');

  const auth = new google.auth.GoogleAuth({
    keyFile: keyPath,
    scopes: ['https://www.googleapis.com/auth/spreadsheets'],
  });
  return google.sheets({ version: 'v4', auth });
}

/** Today's tab name in the sheet's own format, e.g. "3.4.2026" (no leading zeros). */
function todayTabName() {
  const now = new Date();
  return `${now.getDate()}.${now.getMonth() + 1}.${now.getFullYear()}`;
}

/** Converts a tab name like "3.4.2026" into an ISO date "2026-04-03" for storage. */
function tabNameToIsoDate(tabName) {
  const [d, m, y] = tabName.split('.').map((n) => parseInt(n, 10));
  if (!d || !m || !y) return new Date().toISOString().slice(0, 10);
  return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

function notify(customer, type, amount, newBalance) {
  const typeLabel = type === 'udhaar' ? 'Udhaar (Debit)' : 'Wasooli (Credit)';
  const message =
    `Assalam-o-Alaikum ${customer.name},\n` +
    `Aaj aap ne Rs ${amount} ka ${typeLabel} kiya.\n` +
    `Aapka remaining balance: Rs ${newBalance}\n` +
    `- Shukriya`;
  sendWhatsAppMessage(customer.phone, message).catch(() => {});
}

function tokenize(name) {
  return (name || '').toLowerCase().split(/\s+/).filter((w) => w.length > 1);
}

function findBestFuzzyMatch(sheetName, allCustomers) {
  const sheetWords = tokenize(sheetName);
  if (sheetWords.length === 0) return null;
  let best = null;
  let bestScore = 0;
  for (const customer of allCustomers) {
    const overlap = sheetWords.filter((w) => tokenize(customer.name).includes(w)).length;
    if (overlap > bestScore) {
      bestScore = overlap;
      best = customer;
    }
  }
  return bestScore > 0 ? best : null;
}

function applyTransaction(customerId, type, amount, source, userId) {
  const balanceChange = type === 'udhaar' ? amount : -amount;
  db.prepare(
    'INSERT INTO transactions (customer_id, type, amount, source, created_by) VALUES (?, ?, ?, ?, ?)'
  ).run(customerId, type, amount, source, userId);
  db.prepare('UPDATE customers SET balance = balance + ? WHERE id = ?').run(balanceChange, customerId);
  return db.prepare('SELECT * FROM customers WHERE id = ?').get(customerId);
}

/** Inserts or updates a single running-total expense figure for one day, without duplicating. */
function upsertDailyExpense(category, isoDate, amount, userId) {
  const existing = db
    .prepare("SELECT * FROM expenses WHERE category = ? AND entry_date = ? AND source = 'google_sheet'")
    .get(category, isoDate);
  if (existing) {
    db.prepare('UPDATE expenses SET amount = ? WHERE id = ?').run(amount, existing.id);
  } else {
    db.prepare(
      'INSERT INTO expenses (category, amount, entry_date, source, created_by) VALUES (?, ?, ?, ?, ?)'
    ).run(category, amount, isoDate, 'google_sheet', userId);
  }
}

// POST /api/sheets-sync/run
// Body (optional): { tabName: "3.4.2026" } - defaults to today.
router.post('/run', async (req, res) => {
  const tabName = (req.body && req.body.tabName) || todayTabName();
  const isoDate = tabNameToIsoDate(tabName);

  try {
    const sheets = getSheetsClient();
    const sheetId = process.env.GOOGLE_SHEET_ID;
    const allCustomers = db.prepare('SELECT * FROM customers').all();

    const alreadySynced = (rowKey) =>
      !!db.prepare('SELECT 1 FROM synced_rows WHERE tab_name = ? AND row_key = ?').get(tabName, rowKey);
    const markSynced = db.prepare('INSERT OR IGNORE INTO synced_rows (tab_name, row_key) VALUES (?, ?)');
    const insertPending = db.prepare(
      `INSERT INTO pending_sheet_syncs
       (sheet_name, amount, type, tab_name, suggested_customer_id, suggested_customer_name)
       VALUES (?, ?, ?, ?, ?, ?)`
    );

    let processedCount = 0;
    let pendingCount = 0;

    // ---- 1. Udhaar / Wasooli name+amount blocks ----
    for (const block of BLOCKS) {
      const result = await sheets.spreadsheets.values.get({
        spreadsheetId: sheetId,
        range: `'${tabName}'!${block.range}`,
      });
      const rows = result.data.values || [];

      for (let i = 0; i < rows.length; i++) {
        const row = rows[i];
        const name = row[block.nameCol];
        const amountRaw = row[block.amountCol];
        if (!name || !amountRaw) continue;

        const rowKey = `${block.key}_${i}`;
        if (alreadySynced(rowKey)) continue;

        const amount = parseFloat(amountRaw);
        if (isNaN(amount) || amount <= 0) continue;

        const exactMatch = allCustomers.find(
          (c) => c.name.trim().toLowerCase() === name.toString().trim().toLowerCase()
        );

        if (exactMatch) {
          const updated = applyTransaction(exactMatch.id, block.type, amount, 'google_sheet', req.user.id);
          notify(exactMatch, block.type, amount, updated.balance);
          processedCount++;
        } else {
          const suggestion = findBestFuzzyMatch(name, allCustomers);
          insertPending.run(
            name,
            amount,
            block.type,
            tabName,
            suggestion ? suggestion.id : null,
            suggestion ? suggestion.name : null
          );
          pendingCount++;
        }
        markSynced.run(tabName, rowKey);
      }
    }

    // ---- 2. Single-cell daily totals -> Monthly Expense / Daily Online / Main Branch Purchase ----
    const cellRefs = Object.values(SINGLE_CELLS).map((cell) => `'${tabName}'!${cell}`);
    const batchResult = await sheets.spreadsheets.values.batchGet({
      spreadsheetId: sheetId,
      ranges: cellRefs,
    });

    const categories = Object.keys(SINGLE_CELLS);
    categories.forEach((category, idx) => {
      const valueRange = batchResult.data.valueRanges[idx];
      const raw = valueRange.values && valueRange.values[0] && valueRange.values[0][0];
      const amount = parseFloat(raw);
      if (!isNaN(amount)) {
        upsertDailyExpense(category, isoDate, amount, req.user.id);
      }
    });

    db.prepare(
      'INSERT INTO sync_log (rows_synced, new_customers_flagged, synced_by) VALUES (?, ?, ?)'
    ).run(processedCount, pendingCount, req.user.id);

    res.json({ processedCount, pendingCount, tabName });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Sync failed', details: err.message, tabName });
  }
});

// GET /api/sheets-sync/pending
router.get('/pending', (req, res) => {
  const pending = db.prepare('SELECT * FROM pending_sheet_syncs ORDER BY created_at DESC').all();
  res.json(pending);
});

// GET /api/sheets-sync/pending-count
router.get('/pending-count', (req, res) => {
  const { count } = db.prepare('SELECT COUNT(*) as count FROM pending_sheet_syncs').get();
  res.json({ count });
});

// POST /api/sheets-sync/approve
// Body: { pendingId, action: 'link' | 'create' | 'reject', customerId?, newCustomerName? }
router.post('/approve', (req, res) => {
  const { pendingId, action, customerId, newCustomerName } = req.body;
  const pending = db.prepare('SELECT * FROM pending_sheet_syncs WHERE id = ?').get(pendingId);
  if (!pending) return res.status(404).json({ error: 'Pending entry not found' });

  try {
    if (action === 'reject') {
      db.prepare('DELETE FROM pending_sheet_syncs WHERE id = ?').run(pendingId);
      return res.json({ message: 'Rejected and removed' });
    }

    let targetCustomerId = customerId;

    if (action === 'create') {
      const info = db
        .prepare('INSERT INTO customers (name, phone) VALUES (?, ?)')
        .run(newCustomerName || pending.sheet_name, pending.phone || null);
      targetCustomerId = info.lastInsertRowid;
    } else if (action !== 'link' || !targetCustomerId) {
      return res.status(400).json({ error: 'action must be link (with customerId), create, or reject' });
    }

    const updated = applyTransaction(targetCustomerId, pending.type, pending.amount, 'google_sheet', req.user.id);
    notify(updated, pending.type, pending.amount, updated.balance);

    db.prepare('DELETE FROM pending_sheet_syncs WHERE id = ?').run(pendingId);
    res.json({ message: 'Resolved', customerId: targetCustomerId });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to resolve entry', details: err.message });
  }
});

module.exports = router;
