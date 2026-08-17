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

// Expected Google Sheet columns (row 1 = headers):
// A: Name | B: Phone | C: Type (Udhaar/Wasooli) | D: Amount | E: Note | F: Status (Synced/Pending)
const SHEET_RANGE = 'Sheet1!A2:F1000';

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

function notify(customer, type, amount, newBalance) {
  const typeLabel = type === 'udhaar' ? 'Udhaar (Debit)' : 'Wasooli (Credit)';
  const message =
    `Assalam-o-Alaikum ${customer.name},\n` +
    `Aaj aap ne Rs ${amount} ka ${typeLabel} kiya.\n` +
    `Aapka remaining balance: Rs ${newBalance}\n` +
    `- Shukriya`;
  sendWhatsAppMessage(customer.phone, message).catch(() => {});
}

/** Normalize a name into lowercase word tokens for fuzzy comparison. */
function tokenize(name) {
  return (name || '')
    .toLowerCase()
    .split(/\s+/)
    .filter((w) => w.length > 1);
}

/**
 * Finds the best fuzzy match for a sheet name among existing customers,
 * based on shared name keywords (e.g. "Irtaza Shahid" vs "Irtaza Uncle" -> shares "irtaza").
 * Returns the best-matching customer or null if nothing overlaps.
 */
function findBestFuzzyMatch(sheetName, allCustomers) {
  const sheetWords = tokenize(sheetName);
  if (sheetWords.length === 0) return null;

  let best = null;
  let bestScore = 0;

  for (const customer of allCustomers) {
    const customerWords = tokenize(customer.name);
    const overlap = sheetWords.filter((w) => customerWords.includes(w)).length;
    if (overlap > bestScore) {
      bestScore = overlap;
      best = customer;
    }
  }

  return bestScore > 0 ? best : null;
}

function applyTransaction(customerId, type, amount, note, source, userId) {
  const balanceChange = type === 'udhaar' ? amount : -amount;
  db.prepare(
    'INSERT INTO transactions (customer_id, type, amount, note, source, created_by) VALUES (?, ?, ?, ?, ?, ?)'
  ).run(customerId, type, amount, note || null, source, userId);
  db.prepare('UPDATE customers SET balance = balance + ? WHERE id = ?').run(balanceChange, customerId);
  return db.prepare('SELECT * FROM customers WHERE id = ?').get(customerId);
}

// POST /api/sheets-sync/run
// Reads new rows from the Sheet. Exact name matches import immediately.
// Everything else (no match or ambiguous/partial match) goes to the Pending Approval queue.
router.post('/run', async (req, res) => {
  try {
    const sheets = getSheetsClient();
    const sheetId = process.env.GOOGLE_SHEET_ID;

    const result = await sheets.spreadsheets.values.get({
      spreadsheetId: sheetId,
      range: SHEET_RANGE,
    });

    const rows = result.data.values || [];
    const allCustomers = db.prepare('SELECT * FROM customers').all();

    let processedCount = 0;
    let pendingCount = 0;
    const statusUpdates = [];

    const insertPending = db.prepare(
      `INSERT INTO pending_sheet_syncs
       (sheet_name, phone, amount, type, note, suggested_customer_id, suggested_customer_name)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    );

    for (let i = 0; i < rows.length; i++) {
      const [name, phone, typeRaw, amountRaw, note, status] = rows[i];
      const rowNumber = i + 2;
      if (status === 'Synced' || status === 'Pending' || !name || !amountRaw) continue;

      const type = (typeRaw || '').toLowerCase();
      const amount = parseFloat(amountRaw);
      if (!['udhaar', 'wasooli'].includes(type) || isNaN(amount)) continue;

      // Exact match (case-insensitive)
      const exactMatch = allCustomers.find((c) => c.name.trim().toLowerCase() === name.trim().toLowerCase());

      if (exactMatch) {
        const updated = applyTransaction(exactMatch.id, type, amount, note, 'google_sheet', req.user.id);
        notify(exactMatch, type, amount, updated.balance);
        processedCount++;
        statusUpdates.push({ range: `Sheet1!F${rowNumber}`, values: [['Synced']] });
      } else {
        const suggestion = findBestFuzzyMatch(name, allCustomers);
        insertPending.run(
          name,
          phone || null,
          amount,
          type,
          note || null,
          suggestion ? suggestion.id : null,
          suggestion ? suggestion.name : null
        );
        pendingCount++;
        statusUpdates.push({ range: `Sheet1!F${rowNumber}`, values: [['Pending']] });
      }
    }

    if (statusUpdates.length > 0) {
      await sheets.spreadsheets.values.batchUpdate({
        spreadsheetId: sheetId,
        requestBody: { valueInputOption: 'RAW', data: statusUpdates },
      });
    }

    db.prepare(
      'INSERT INTO sync_log (rows_synced, new_customers_flagged, synced_by) VALUES (?, ?, ?)'
    ).run(processedCount, pendingCount, req.user.id);

    res.json({ processedCount, pendingCount });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Sync failed', details: err.message });
  }
});

// GET /api/sheets-sync/pending - list all rows awaiting owner review
router.get('/pending', (req, res) => {
  const pending = db.prepare('SELECT * FROM pending_sheet_syncs ORDER BY created_at DESC').all();
  res.json(pending);
});

// GET /api/sheets-sync/pending-count - for the dashboard badge
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
        .run(newCustomerName || pending.sheet_name, pending.phone || '');
      targetCustomerId = info.lastInsertRowid;
    } else if (action !== 'link' || !targetCustomerId) {
      return res.status(400).json({ error: 'action must be link (with customerId), create, or reject' });
    }

    const updated = applyTransaction(
      targetCustomerId,
      pending.type,
      pending.amount,
      pending.note,
      'google_sheet',
      req.user.id
    );
    notify(updated, pending.type, pending.amount, updated.balance);

    db.prepare('DELETE FROM pending_sheet_syncs WHERE id = ?').run(pendingId);
    res.json({ message: 'Resolved', customerId: targetCustomerId });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to resolve entry', details: err.message });
  }
});

module.exports = router;
