const express = require('express');
const { google } = require('googleapis');
const path = require('path');
const db = require('../config/db');
const { authenticate, ownerOnly } = require('../middleware/auth');

const router = express.Router();
router.use(authenticate, ownerOnly); // sync is Owner-only, always

// Expected Google Sheet columns (row 1 = headers):
// A: Name | B: HouseNumber | C: Type (Udhaar/Wasooli) | D: Amount | E: Note | F: Synced
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

// GET /api/sheets-sync/preview - reads unsynced rows WITHOUT writing anything
router.get('/preview', async (req, res) => {
  try {
    const sheets = getSheetsClient();
    const sheetId = process.env.GOOGLE_SHEET_ID;

    const result = await sheets.spreadsheets.values.get({
      spreadsheetId: sheetId,
      range: SHEET_RANGE,
    });

    const rows = result.data.values || [];
    const preview = [];

    rows.forEach((row, index) => {
      const [name, houseNumber, type, amount, note, synced] = row;
      if (synced === 'Synced' || !name || !amount) return; // skip already-synced or empty rows

      const customer = db
        .prepare('SELECT * FROM customers WHERE name = ? AND house_number = ?')
        .get(name, houseNumber);

      preview.push({
        rowNumber: index + 2, // +2 because range starts at row 2
        name,
        houseNumber,
        type: (type || '').toLowerCase(),
        amount: parseFloat(amount),
        note: note || null,
        matchedCustomerId: customer ? customer.id : null,
        isNewCustomer: !customer,
      });
    });

    res.json({ totalRows: preview.length, preview });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to read Google Sheet', details: err.message });
  }
});

// POST /api/sheets-sync/confirm - actually imports the rows and marks them Synced
// Body: { rows: [ { rowNumber, name, houseNumber, type, amount, note, matchedCustomerId } ] }
router.post('/confirm', async (req, res) => {
  const { rows } = req.body;
  if (!Array.isArray(rows) || rows.length === 0) {
    return res.status(400).json({ error: 'No rows provided to sync' });
  }

  try {
    const sheets = getSheetsClient();
    const sheetId = process.env.GOOGLE_SHEET_ID;

    const insertTxn = db.prepare(
      'INSERT INTO transactions (customer_id, type, amount, note, source, created_by) VALUES (?, ?, ?, ?, ?, ?)'
    );
    const updateBalance = db.prepare('UPDATE customers SET balance = balance + ? WHERE id = ?');
    const insertCustomer = db.prepare(
      'INSERT INTO customers (name, house_number) VALUES (?, ?)'
    );

    let syncedCount = 0;
    let newCustomerCount = 0;
    const markSyncedRequests = [];

    const runAll = db.transaction(() => {
      for (const row of rows) {
        let customerId = row.matchedCustomerId;

        // Auto-create customer if it doesn't exist yet (Owner already confirmed this in preview step)
        if (!customerId) {
          const info = insertCustomer.run(row.name, row.houseNumber || null);
          customerId = info.lastInsertRowid;
          newCustomerCount++;
        }

        const balanceChange = row.type === 'udhaar' ? row.amount : -row.amount;
        insertTxn.run(customerId, row.type, row.amount, row.note, 'google_sheet', req.user.id);
        updateBalance.run(balanceChange, customerId);

        // Mark column F ("Synced") for this row
        markSyncedRequests.push({
          range: `Sheet1!F${row.rowNumber}`,
          values: [['Synced']],
        });
        syncedCount++;
      }
    });

    runAll();

    // Batch update the Sheet to mark rows as Synced
    if (markSyncedRequests.length > 0) {
      await sheets.spreadsheets.values.batchUpdate({
        spreadsheetId: sheetId,
        requestBody: { valueInputOption: 'RAW', data: markSyncedRequests },
      });
    }

    db.prepare(
      'INSERT INTO sync_log (rows_synced, new_customers_flagged, synced_by) VALUES (?, ?, ?)'
    ).run(syncedCount, newCustomerCount, req.user.id);

    res.json({ message: 'Sync complete', syncedCount, newCustomerCount });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Sync failed', details: err.message });
  }
});

module.exports = router;
