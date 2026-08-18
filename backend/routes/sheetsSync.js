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
// ============================================================
const BLOCKS = [
  // Udhaar (debit) - customer took goods, owes money
  { range: 'A2:B50', nameCol: 0, amountCol: 1, type: 'udhaar', key: 'udhaar1' },
  { range: 'A52:B71', nameCol: 0, amountCol: 1, type: 'udhaar', key: 'udhaar2' },
  // Wasooli (credit) - customer paid / cleared their khata
  { range: 'I2:J50', nameCol: 0, amountCol: 1, type: 'wasooli', key: 'wasooli1' },
  { range: 'M2:N16', nameCol: 0, amountCol: 1, type: 'wasooli', key: 'wasooli2' },
];

const SINGLE_CELLS = {
  monthly_expense: 'D51',
  daily_online: 'J72',
  daily_main_branch_purchase: 'N24',
};

function getAuthClient() {
  const keyPath =
    process.env.GOOGLE_SERVICE_ACCOUNT_KEY_PATH ||
    path.join(__dirname, '..', 'config', 'service-account-key.json');

  const auth = new google.auth.GoogleAuth({
    keyFile: keyPath,
    scopes: [
      'https://www.googleapis.com/auth/spreadsheets',
      'https://www.googleapis.com/auth/drive',
    ],
  });
  return auth;
}

function getSheetsClient(auth) {
  return google.sheets({ version: 'v4', auth });
}

function getDriveClient(auth) {
  return google.drive({ version: 'v3', auth });
}

async function getFirstSheetName(sheetId) {
  const auth = getAuthClient();
  const sheets = getSheetsClient(auth);

  try {
    const response = await sheets.spreadsheets.get({
      spreadsheetId: sheetId,
      fields: 'sheets(properties(title))',
    });

    const sheetList = response.data.sheets || [];
    if (sheetList.length === 0) {
      throw {
        error: 'The spreadsheet has no sheets.',
        errorCode: 'NO_SHEETS_IN_SPREADSHEET',
        details: 'The spreadsheet must contain at least one sheet/tab. Please add a sheet and try again.',
      };
    }

    const firstSheetName = sheetList[0].properties.title;
    console.log(`[Sheets Sync] Using first sheet: "${firstSheetName}"`);
    return firstSheetName;
  } catch (err) {
    if (err.errorCode) throw err;
    throw {
      error: 'Failed to retrieve sheet information from the spreadsheet.',
      errorCode: 'SHEET_METADATA_ERROR',
      details: `Unable to read sheet metadata. Error: ${err.message}. Ensure the service account has Sheets API access.`,
    };
  }
}

async function getLatestSheetIdFromFolder() {
  const folderId = process.env.GOOGLE_DRIVE_FOLDER_ID;
  if (!folderId) {
    throw {
      error: 'Google Drive folder ID is not configured.',
      errorCode: 'MISSING_FOLDER_ID',
      details: 'The GOOGLE_DRIVE_FOLDER_ID environment variable is not set in .env file.',
    };
  }

  const auth = getAuthClient();
  const drive = getDriveClient(auth);

  try {
    const response = await drive.files.list({
      q: `'${folderId}' in parents and mimeType='application/vnd.google-apps.spreadsheet' and trashed=false`,
      spaces: 'drive',
      fields: 'files(id, name, modifiedTime)',
      orderBy: 'modifiedTime desc',
      pageSize: 1,
    });

    const files = response.data.files || [];
    if (files.length === 0) {
      throw {
        error: 'No Google Sheets found in the configured folder.',
        errorCode: 'NO_SHEETS_FOUND',
        details: `Folder ID: ${folderId}. Please ensure at least one Google Sheet exists in this folder.`,
      };
    }

    const latestSheet = files[0];
    console.log(`[Sheets Sync] Using latest sheet: "${latestSheet.name}" (ID: ${latestSheet.id})`);
    return latestSheet.id;
  } catch (err) {
    if (err.errorCode) throw err;
    throw {
      error: 'Failed to fetch the latest Google Sheet from your Drive folder.',
      errorCode: 'DRIVE_API_ERROR',
      details: `${err.message || 'Unknown error'}`,
    };
  }
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

// UPDATED: Dynamic duplicate checking with default isoDate
function applyTransaction(customerId, type, amount, source, userId, isoDate = new Date().toISOString().slice(0, 10)) {
  const existing = db
    .prepare(
      "SELECT * FROM transactions WHERE customer_id = ? AND type = ? AND amount = ? AND source = ? AND (date(created_at) = date(?) OR DATE(created_at) = DATE('now', 'localtime'))"
    )
    .get(customerId, type, amount, source, isoDate);
  
  if (existing) {
    console.log(`[Sheets Sync] Skipping duplicate transaction for customer ${customerId}: ${type} Rs${amount}`);
    return db.prepare('SELECT * FROM customers WHERE id = ?').get(customerId);
  }

  const balanceChange = type === 'udhaar' ? amount : -amount;
  db.prepare(
    'INSERT INTO transactions (customer_id, type, amount, source, created_by) VALUES (?, ?, ?, ?, ?)'
  ).run(customerId, type, amount, source, userId);
  db.prepare('UPDATE customers SET balance = balance + ? WHERE id = ?').run(balanceChange, customerId);
  return db.prepare('SELECT * FROM customers WHERE id = ?').get(customerId);
}

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
router.post('/run', async (req, res) => {
  try {
    const auth = getAuthClient();
    const sheets = getSheetsClient(auth);
    const sheetId = await getLatestSheetIdFromFolder();
    const tabName = await getFirstSheetName(sheetId);
    
    const today = new Date();
    const isoDate = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
    
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
          const updated = applyTransaction(exactMatch.id, block.type, amount, 'google_sheet', req.user.id, isoDate);
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

    const cellRefs = Object.values(SINGLE_CELLS).map((cell) => `'${tabName}'!${cell}`);
    const batchResult = await sheets.spreadsheets.values.batchGet({
      spreadsheetId: sheetId,
      ranges: cellRefs,
    });

    const categories = Object.keys(SINGLE_CELLS);
    categories.forEach((category, idx) => {
      const valueRange = batchResult.data.valueRanges[idx];
      if (!valueRange) return;
      const raw = valueRange.values && valueRange.values[0] && valueRange.values[0][0];
      const amount = parseFloat(raw);
      if (!isNaN(amount)) {
        upsertDailyExpense(category, isoDate, amount, req.user.id);
      }
    });

    db.prepare(
      'INSERT INTO sync_log (rows_synced, new_customers_flagged, synced_by) VALUES (?, ?, ?)'
    ).run(processedCount, pendingCount, req.user.id);

    res.json({ success: true, processedCount, pendingCount, tabName });
  } catch (err) {
    console.error('[Sheets Sync Error]', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Pending Endpoints
router.get('/pending', (req, res) => {
  const pending = db.prepare('SELECT * FROM pending_sheet_syncs ORDER BY created_at DESC').all();
  res.json(pending);
});

router.get('/pending-count', (req, res) => {
  const { count } = db.prepare('SELECT COUNT(*) as count FROM pending_sheet_syncs').get();
  res.json({ count });
});

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

    const today = new Date();
    const isoDate = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
    const updated = applyTransaction(targetCustomerId, pending.type, pending.amount, 'google_sheet', req.user.id, isoDate);
    notify(updated, pending.type, pending.amount, updated.balance);

    db.prepare('DELETE FROM pending_sheet_syncs WHERE id = ?').run(pendingId);
    res.json({ message: 'Resolved', customerId: targetCustomerId });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to resolve entry', details: err.message });
  }
});

router.post('/bulk-reject', (req, res) => {
  const { pendingIds } = req.body;
  if (!Array.isArray(pendingIds) || pendingIds.length === 0) {
    return res.status(400).json({ error: 'pendingIds must be a non-empty array' });
  }

  try {
    let rejectedCount = 0;
    for (const pendingId of pendingIds) {
      const pending = db.prepare('SELECT * FROM pending_sheet_syncs WHERE id = ?').get(pendingId);
      if (pending) {
        db.prepare('DELETE FROM pending_sheet_syncs WHERE id = ?').run(pendingId);
        rejectedCount++;
      }
    }
    res.json({ message: 'Entries rejected', rejectedCount });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to bulk reject', details: err.message });
  }
});

router.post('/bulk-approve-as-create', (req, res) => {
  const { pendingIds } = req.body;
  if (!Array.isArray(pendingIds) || pendingIds.length === 0) {
    return res.status(400).json({ error: 'pendingIds must be a non-empty array' });
  }

  try {
    let approvedCount = 0;
    const createdCustomerIds = [];
    
    const today = new Date();
    const isoDate = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
    
    for (const pendingId of pendingIds) {
      const pending = db.prepare('SELECT * FROM pending_sheet_syncs WHERE id = ?').get(pendingId);
      if (!pending) continue;

      const info = db
        .prepare('INSERT INTO customers (name, phone) VALUES (?, ?)')
        .run(pending.sheet_name, pending.phone || null);
      const customerId = info.lastInsertRowid;
      createdCustomerIds.push(customerId);

      const updated = applyTransaction(customerId, pending.type, pending.amount, 'google_sheet', req.user.id, isoDate);
      notify(updated, pending.type, pending.amount, updated.balance);

      db.prepare('DELETE FROM pending_sheet_syncs WHERE id = ?').run(pendingId);
      approvedCount++;
    }

    res.json({ 
      message: 'Entries approved and customers created', 
      approvedCount, 
      createdCustomerIds 
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to bulk approve', details: err.message });
  }
});

module.exports = router;