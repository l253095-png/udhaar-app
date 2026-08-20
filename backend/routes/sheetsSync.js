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
  { range: 'A2:B50', nameCol: 0, amountCol: 1, type: 'udhaar', key: 'udhaar1', markerCol: 'C' },
  { range: 'A52:B71', nameCol: 0, amountCol: 1, type: 'udhaar', key: 'udhaar2', markerCol: 'C' },
  // Wasooli (credit) - customer paid / cleared their khata
  { range: 'I2:J50', nameCol: 0, amountCol: 1, type: 'wasooli', key: 'wasooli1', markerCol: 'K' },
  { range: 'M2:N16', nameCol: 0, amountCol: 1, type: 'wasooli', key: 'wasooli2', markerCol: 'O' },
];

const SINGLE_CELLS = {
  monthly_expense: 'D51',
  daily_online: 'J72',
  daily_main_branch_purchase: 'N24',
};

// Colors used to mark row status directly on the NAME cell background
const COLOR_SYNCED = { red: 0.72, green: 0.9, blue: 0.72 };   // light green - fully approved, in balance
const COLOR_STAGED = { red: 0.7, green: 0.85, blue: 0.98 };   // light blue - imported, awaiting Owner's final approval
const COLOR_PENDING = { red: 1, green: 0.93, blue: 0.65 };    // light yellow/orange - name needs matching
const COLOR_REJECTED = { red: 1, green: 0.8, blue: 0.8 };     // light red
const COLOR_IGNORED = { red: 0.85, green: 0.85, blue: 0.85 }; // grey - permanently ignored
const COLOR_CLEAR = { red: 1, green: 1, blue: 1 };            // white (reset)

function normalizeIgnoredName(name) {
  return (name || '').trim().toLowerCase();
}

function getAuthClient() {
  const keyPath =
    process.env.GOOGLE_SERVICE_ACCOUNT_KEY_PATH ||
    path.join(__dirname, '..', 'config', 'service-account-key.json');

  return new google.auth.GoogleAuth({
    keyFile: keyPath,
    scopes: [
      'https://www.googleapis.com/auth/spreadsheets',
      'https://www.googleapis.com/auth/drive',
    ],
  });
}

function getSheetsClient(auth) {
  return google.sheets({ version: 'v4', auth });
}

function getDriveClient(auth) {
  return google.drive({ version: 'v3', auth });
}

/** Converts an A1 cell reference like "C5" into {row, col} zero-indexed grid coordinates. */
function cellToGridCoords(cell) {
  const match = cell.match(/^([A-Z]+)(\d+)$/);
  if (!match) return null;
  const colLetters = match[1];
  const row = parseInt(match[2], 10) - 1;
  let col = 0;
  for (let i = 0; i < colLetters.length; i++) {
    col = col * 26 + (colLetters.charCodeAt(i) - 64);
  }
  return { row, col: col - 1 };
}

/**
 * Colors the background of a specific cell (used on the customer NAME cell)
 * to visually show sync status directly in the Sheet, instead of text.
 * Fails silently (logs only) so it never breaks the main sync/approval flow.
 */
async function colorCell(sheetId, tabName, cell, color) {
  if (!sheetId || !tabName || !cell || !color) return;
  try {
    const auth = getAuthClient();
    const sheets = getSheetsClient(auth);
    const meta = await sheets.spreadsheets.get({ spreadsheetId: sheetId, fields: 'sheets(properties(sheetId,title))' });
    const sheetMeta = (meta.data.sheets || []).find((s) => s.properties.title === tabName);
    if (!sheetMeta) return;
    const gridSheetId = sheetMeta.properties.sheetId;

    const coords = cellToGridCoords(cell);
    if (!coords) return;

    await sheets.spreadsheets.batchUpdate({
      spreadsheetId: sheetId,
      requestBody: {
        requests: [
          {
            repeatCell: {
              range: {
                sheetId: gridSheetId,
                startRowIndex: coords.row,
                endRowIndex: coords.row + 1,
                startColumnIndex: coords.col,
                endColumnIndex: coords.col + 1,
              },
              cell: { userEnteredFormat: { backgroundColor: color } },
              fields: 'userEnteredFormat.backgroundColor',
            },
          },
        ],
      },
    });
  } catch (err) {
    console.error('Failed to color Sheet cell (non-fatal):', err.message);
  }
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
      throw { error: 'The spreadsheet has no sheets.', errorCode: 'NO_SHEETS_IN_SPREADSHEET', details: 'Add a sheet/tab and try again.' };
    }
    return sheetList[0].properties.title;
  } catch (err) {
    if (err.errorCode) throw err;
    throw { error: 'Failed to retrieve sheet information.', errorCode: 'SHEET_METADATA_ERROR', details: err.message };
  }
}

async function getLatestSheetIdFromFolder() {
  const folderId = process.env.GOOGLE_DRIVE_FOLDER_ID;
  if (!folderId) {
    throw { error: 'Google Drive folder ID is not configured.', errorCode: 'MISSING_FOLDER_ID', details: 'GOOGLE_DRIVE_FOLDER_ID is not set in .env' };
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
      throw { error: 'No Google Sheets found in the configured folder.', errorCode: 'NO_SHEETS_FOUND', details: `Folder ID: ${folderId}` };
    }
    console.log(`[Sheets Sync] Using latest sheet: "${files[0].name}" (ID: ${files[0].id})`);
    return files[0].id;
  } catch (err) {
    if (err.errorCode) throw err;
    throw { error: 'Failed to fetch the latest Google Sheet from your Drive folder.', errorCode: 'DRIVE_API_ERROR', details: err.message || 'Unknown error' };
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

/** Lowercase + word-split, for loose word-overlap matching. */
function tokenize(name) {
  return (name || '').toLowerCase().split(/\s+/).filter((w) => w.length > 1);
}

/** Strips ALL non-alphanumeric characters + lowercases, so "43b rent", "43B Rent", "43BRENT" all normalize the same. */
function normalizeName(name) {
  return (name || '').toLowerCase().replace(/[^a-z0-9]/g, '');
}

/**
 * Finds the best match for a sheet name among existing customers.
 * Returns { customer, confidence } where confidence is 'high' (spacing/case-only
 * difference, e.g. "43BRENT" vs "43b rent") or 'low' (partial word overlap only).
 */
function findBestFuzzyMatch(sheetName, allCustomers) {
  const normalizedSheetName = normalizeName(sheetName);

  // Tier 1: normalized-exact (same letters/numbers, different spacing/case/punctuation)
  const normalizedMatch = allCustomers.find((c) => normalizeName(c.name) === normalizedSheetName);
  if (normalizedMatch) {
    return { customer: normalizedMatch, confidence: 'high' };
  }

  // Tier 2: shared-word overlap (e.g. "Irtaza Shahid" vs "Irtaza Uncle")
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
  return bestScore > 0 ? { customer: best, confidence: 'low' } : null;
}

function applyTransaction(customerId, type, amount, source, userId, isoDate, syncTab) {
  // Safety net: if an identical transaction for this customer/type/amount/source
  // already exists today, skip re-inserting it (defense in depth alongside the
  // synced_rows tracking, in case sync is ever re-run in an unusual way).
  const existing = db
    .prepare(
      "SELECT * FROM transactions WHERE customer_id = ? AND type = ? AND amount = ? AND source = ? AND date(created_at) = date(?)"
    )
    .get(customerId, type, amount, source, isoDate || new Date().toISOString().slice(0, 10));
  if (existing) {
    console.log(`[Sheets Sync] Skipping duplicate transaction for customer ${customerId}: ${type} Rs${amount}`);
    return db.prepare('SELECT * FROM customers WHERE id = ?').get(customerId);
  }

  const balanceChange = type === 'udhaar' ? amount : -amount;
  db.prepare(
    'INSERT INTO transactions (customer_id, type, amount, source, sync_tab, created_by) VALUES (?, ?, ?, ?, ?, ?)'
  ).run(customerId, type, amount, source, syncTab || null, userId);
  db.prepare('UPDATE customers SET balance = balance + ? WHERE id = ?').run(balanceChange, customerId);
  return db.prepare('SELECT * FROM customers WHERE id = ?').get(customerId);
}

function upsertDailyExpense(category, isoDate, amount, userId, syncTab) {
  const existing = db
    .prepare("SELECT * FROM expenses WHERE category = ? AND entry_date = ? AND source = 'google_sheet'")
    .get(category, isoDate);
  if (existing) {
    db.prepare('UPDATE expenses SET amount = ?, sync_tab = ? WHERE id = ?').run(amount, syncTab || null, existing.id);
  } else {
    db.prepare(
      'INSERT INTO expenses (category, amount, entry_date, source, sync_tab, created_by) VALUES (?, ?, ?, ?, ?, ?)'
    ).run(category, amount, isoDate, 'google_sheet', syncTab || null, userId);
  }
}

function todayIsoDate() {
  const today = new Date();
  return `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
}

// POST /api/sheets-sync/run
router.post('/run', async (req, res) => {
  try {
    const auth = getAuthClient();
    const sheets = getSheetsClient(auth);
    const sheetId = await getLatestSheetIdFromFolder();
    const tabName = await getFirstSheetName(sheetId);
    const isoDate = todayIsoDate();

    const allCustomers = db.prepare('SELECT * FROM customers').all();

    const alreadySynced = (rowKey) =>
      !!db.prepare('SELECT 1 FROM synced_rows WHERE tab_name = ? AND row_key = ?').get(tabName, rowKey);
    const markSynced = db.prepare('INSERT OR IGNORE INTO synced_rows (tab_name, row_key) VALUES (?, ?)');
    const insertPending = db.prepare(
      `INSERT INTO pending_sheet_syncs
       (sheet_name, amount, type, tab_name, sheet_id, marker_cell, row_key, suggested_customer_id, suggested_customer_name)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
    );

    let processedCount = 0;
    let pendingCount = 0;
    let ignoredCount = 0;
    const colorJobs = [];
    const ignoredNames = new Set(
      db.prepare('SELECT normalized_name FROM ignored_sheet_names').all().map((r) => r.normalized_name)
    );

    for (const block of BLOCKS) {
      const result = await sheets.spreadsheets.values.get({
        spreadsheetId: sheetId,
        range: `'${tabName}'!${block.range}`,
      });
      const rows = result.data.values || [];
      const startRow = parseInt(block.range.match(/^[A-Z]+(\d+):/)[1], 10);
      const startCol = block.range.match(/^([A-Z]+)/)[1]; // name is always the first column in each block's range

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

        const sheetRowNum = startRow + i;
        const nameCell = `${startCol}${sheetRowNum}`;

        if (exactMatch) {
          // Matched a customer, but does NOT touch their balance yet -
          // it waits in the "Imported" list for the Owner's final approval.
          db.prepare(
            'INSERT INTO staged_entries (customer_id, type, amount, tab_name, sheet_id, marker_cell, row_key, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
          ).run(exactMatch.id, block.type, amount, tabName, sheetId, nameCell, rowKey, req.user.id);
          processedCount++;
          colorJobs.push({ cell: nameCell, color: COLOR_STAGED });
        } else if (ignoredNames.has(normalizeIgnoredName(name))) {
          // Owner previously marked this exact name (e.g. "43BRENT") as
          // permanently ignored - skip it silently, don't ask again.
          ignoredCount++;
          colorJobs.push({ cell: nameCell, color: COLOR_IGNORED });
        } else {
          // Fuzzy match (handles spacing/case differences like "43b rent" vs "43BRENT",
          // and partial-name matches like "Irtaza Shahid" vs "Irtaza Uncle")
          const match = findBestFuzzyMatch(name, allCustomers);
          insertPending.run(
            name,
            amount,
            block.type,
            tabName,
            sheetId,
            nameCell,
            rowKey,
            match ? match.customer.id : null,
            match ? match.customer.name : null
          );
          pendingCount++;
          colorJobs.push({ cell: nameCell, color: COLOR_PENDING });
        }
        markSynced.run(tabName, rowKey);
      }
    }

    // Color all processed row name-cells (green=synced, yellow=pending review)
    for (const job of colorJobs) {
      await colorCell(sheetId, tabName, job.cell, job.color);
    }

    const cellRefs = Object.values(SINGLE_CELLS).map((cell) => `'${tabName}'!${cell}`);
    const batchResult = await sheets.spreadsheets.values.batchGet({ spreadsheetId: sheetId, ranges: cellRefs });
    const categories = Object.keys(SINGLE_CELLS);
    categories.forEach((category, idx) => {
      const valueRange = batchResult.data.valueRanges[idx];
      if (!valueRange) return;
      const raw = valueRange.values && valueRange.values[0] && valueRange.values[0][0];
      const amount = parseFloat(raw);
      if (!isNaN(amount)) {
        upsertDailyExpense(category, isoDate, amount, req.user.id, tabName);
      }
    });

    db.prepare('INSERT INTO sync_log (tab_name, rows_synced, new_customers_flagged, synced_by) VALUES (?, ?, ?, ?)')
      .run(tabName, processedCount, pendingCount, req.user.id);

    res.json({ success: true, processedCount, pendingCount, ignoredCount, tabName });
  } catch (err) {
    console.error('[Sheets Sync Error]', err);
    res.status(500).json({ success: false, error: err.message });
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
router.post('/approve', async (req, res) => {
  const { pendingId, action, customerId, newCustomerName } = req.body;
  const pending = db.prepare('SELECT * FROM pending_sheet_syncs WHERE id = ?').get(pendingId);
  if (!pending) return res.status(404).json({ error: 'Pending entry not found' });

  try {
    if (action === 'reject') {
      db.prepare('DELETE FROM pending_sheet_syncs WHERE id = ?').run(pendingId);
      // Un-mark this row as synced, so the NEXT sync run reconsiders it
      // (e.g. if the owner fixes the name in the Sheet afterward).
      if (pending.row_key) {
        db.prepare('DELETE FROM synced_rows WHERE tab_name = ? AND row_key = ?').run(pending.tab_name, pending.row_key);
      }
      await colorCell(pending.sheet_id, pending.tab_name, pending.marker_cell, COLOR_CLEAR);
      return res.json({ message: 'Rejected — will be reconsidered on the next sync' });
    }

    if (action === 'ignore') {
      // Permanently ignore this exact name (e.g. "43BRENT" turns out to be a
      // rent/location code, not a real customer) so it's never flagged again,
      // in any future day's sheet.
      const normalized = normalizeIgnoredName(pending.sheet_name);
      db.prepare(
        'INSERT OR IGNORE INTO ignored_sheet_names (normalized_name, original_name, created_by) VALUES (?, ?, ?)'
      ).run(normalized, pending.sheet_name, req.user.id);
      db.prepare('DELETE FROM pending_sheet_syncs WHERE id = ?').run(pendingId);
      await colorCell(pending.sheet_id, pending.tab_name, pending.marker_cell, COLOR_IGNORED);
      return res.json({ message: `"${pending.sheet_name}" will be auto-skipped in every future sync` });
    }

    let targetCustomerId = customerId;
    if (action === 'create') {
      const info = db
        .prepare('INSERT INTO customers (name, phone) VALUES (?, ?)')
        .run(newCustomerName || pending.sheet_name, pending.phone || null);
      targetCustomerId = info.lastInsertRowid;
    } else if (action !== 'link' || !targetCustomerId) {
      return res.status(400).json({ error: 'action must be link (with customerId), create, reject, or ignore' });
    }

    // Now matched to a customer, but STILL doesn't touch their balance -
    // it moves into the "Imported" list for the Owner's final approval.
    db.prepare(
      'INSERT INTO staged_entries (customer_id, type, amount, tab_name, sheet_id, marker_cell, row_key, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
    ).run(targetCustomerId, pending.type, pending.amount, pending.tab_name, pending.sheet_id, pending.marker_cell, pending.row_key, req.user.id);

    db.prepare('DELETE FROM pending_sheet_syncs WHERE id = ?').run(pendingId);
    await colorCell(pending.sheet_id, pending.tab_name, pending.marker_cell, COLOR_STAGED);
    res.json({ message: 'Moved to Imported Entries — approve it there to apply it', customerId: targetCustomerId });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to resolve entry', details: err.message });
  }
});

// POST /api/sheets-sync/bulk-reject
router.post('/bulk-reject', async (req, res) => {
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
        if (pending.row_key) {
          db.prepare('DELETE FROM synced_rows WHERE tab_name = ? AND row_key = ?').run(pending.tab_name, pending.row_key);
        }
        await colorCell(pending.sheet_id, pending.tab_name, pending.marker_cell, COLOR_CLEAR);
        rejectedCount++;
      }
    }
    res.json({ message: 'Entries rejected', rejectedCount });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to bulk reject', details: err.message });
  }
});

// POST /api/sheets-sync/bulk-approve-as-create
router.post('/bulk-approve-as-create', async (req, res) => {
  const { pendingIds } = req.body;
  if (!Array.isArray(pendingIds) || pendingIds.length === 0) {
    return res.status(400).json({ error: 'pendingIds must be a non-empty array' });
  }
  try {
    let approvedCount = 0;
    const createdCustomerIds = [];

    for (const pendingId of pendingIds) {
      const pending = db.prepare('SELECT * FROM pending_sheet_syncs WHERE id = ?').get(pendingId);
      if (!pending) continue;

      const info = db.prepare('INSERT INTO customers (name, phone) VALUES (?, ?)').run(pending.sheet_name, pending.phone || null);
      const customerId = info.lastInsertRowid;
      createdCustomerIds.push(customerId);

      // Stage it - doesn't touch the balance until approved from Imported Entries.
      db.prepare(
        'INSERT INTO staged_entries (customer_id, type, amount, tab_name, sheet_id, marker_cell, row_key, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
      ).run(customerId, pending.type, pending.amount, pending.tab_name, pending.sheet_id, pending.marker_cell, pending.row_key, req.user.id);

      db.prepare('DELETE FROM pending_sheet_syncs WHERE id = ?').run(pendingId);
      await colorCell(pending.sheet_id, pending.tab_name, pending.marker_cell, COLOR_STAGED);
      approvedCount++;
    }

    res.json({ message: 'Moved to Imported Entries — approve them there to apply to balances', approvedCount, createdCustomerIds });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to bulk approve', details: err.message });
  }
});

// GET /api/sheets-sync/history - list past sync runs (for the Undo picker)
router.get('/history', (req, res) => {
  const rows = db.prepare('SELECT * FROM sync_log ORDER BY synced_at DESC LIMIT 30').all();
  res.json(rows);
});

// POST /api/sheets-sync/undo
// Body: { tabName }
// Reverses every transaction/expense that came from that day's sync, and
// frees up that tab's rows so a fresh sync run will reprocess them from scratch.
router.post('/undo', async (req, res) => {
  const { tabName } = req.body;
  if (!tabName) return res.status(400).json({ error: 'tabName is required' });

  try {
    const transactions = db.prepare("SELECT * FROM transactions WHERE sync_tab = ? AND source = 'google_sheet'").all(tabName);

    const undoAll = db.transaction(() => {
      for (const txn of transactions) {
        const balanceChange = txn.type === 'udhaar' ? -txn.amount : txn.amount; // reverse it
        db.prepare('UPDATE customers SET balance = balance + ? WHERE id = ?').run(balanceChange, txn.customer_id);
        db.prepare('DELETE FROM transactions WHERE id = ?').run(txn.id);
      }
      db.prepare("DELETE FROM expenses WHERE sync_tab = ? AND source = 'google_sheet'").run(tabName);
      db.prepare('DELETE FROM pending_sheet_syncs WHERE tab_name = ?').run(tabName);
      db.prepare('DELETE FROM staged_entries WHERE tab_name = ?').run(tabName);
      db.prepare('DELETE FROM synced_rows WHERE tab_name = ?').run(tabName);
      db.prepare('DELETE FROM sync_log WHERE tab_name = ?').run(tabName);
    });
    undoAll();

    res.json({
      message: `Undo complete for "${tabName}". ${transactions.length} transactions reversed. This day can now be synced fresh.`,
      reversedCount: transactions.length,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to undo sync', details: err.message });
  }
});

// ============================================================
// IMPORTED ENTRIES (staged_entries) — final approval step.
// Nothing here has touched a customer's balance yet.
// ============================================================

// GET /api/sheets-sync/staged - list everything awaiting final approval
router.get('/staged', (req, res) => {
  const rows = db
    .prepare(
      `SELECT se.*, c.name as customer_name, c.phone as customer_phone
       FROM staged_entries se
       JOIN customers c ON c.id = se.customer_id
       ORDER BY se.created_at DESC`
    )
    .all();
  res.json(rows);
});

// GET /api/sheets-sync/staged-count
router.get('/staged-count', (req, res) => {
  const { count } = db.prepare('SELECT COUNT(*) as count FROM staged_entries').get();
  res.json({ count });
});

// POST /api/sheets-sync/staged/:id/approve - THE final step: applies to balance + sends WhatsApp
router.post('/staged/:id/approve', async (req, res) => {
  const staged = db.prepare('SELECT * FROM staged_entries WHERE id = ?').get(req.params.id);
  if (!staged) return res.status(404).json({ error: 'Entry not found' });

  try {
    const isoDate = todayIsoDate();
    const updated = applyTransaction(staged.customer_id, staged.type, staged.amount, 'google_sheet', req.user.id, isoDate, staged.tab_name);
    notify(updated, staged.type, staged.amount, updated.balance);

    db.prepare('DELETE FROM staged_entries WHERE id = ?').run(staged.id);
    await colorCell(staged.sheet_id, staged.tab_name, staged.marker_cell, COLOR_SYNCED);
    res.json({ message: 'Approved and applied to balance', customerId: staged.customer_id, newBalance: updated.balance });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to approve entry', details: err.message });
  }
});

// POST /api/sheets-sync/staged/:id/reject - discard it, don't apply, row gets reconsidered next sync
router.post('/staged/:id/reject', async (req, res) => {
  const staged = db.prepare('SELECT * FROM staged_entries WHERE id = ?').get(req.params.id);
  if (!staged) return res.status(404).json({ error: 'Entry not found' });

  try {
    db.prepare('DELETE FROM staged_entries WHERE id = ?').run(staged.id);
    if (staged.row_key) {
      db.prepare('DELETE FROM synced_rows WHERE tab_name = ? AND row_key = ?').run(staged.tab_name, staged.row_key);
    }
    await colorCell(staged.sheet_id, staged.tab_name, staged.marker_cell, COLOR_CLEAR);
    res.json({ message: 'Rejected — will be reconsidered on the next sync' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to reject entry', details: err.message });
  }
});

// POST /api/sheets-sync/staged/bulk-approve - approve everything in the Imported list at once
router.post('/staged/bulk-approve', async (req, res) => {
  try {
    const allStaged = db.prepare('SELECT * FROM staged_entries').all();
    const isoDate = todayIsoDate();
    let approvedCount = 0;

    for (const staged of allStaged) {
      const updated = applyTransaction(staged.customer_id, staged.type, staged.amount, 'google_sheet', req.user.id, isoDate, staged.tab_name);
      notify(updated, staged.type, staged.amount, updated.balance);
      db.prepare('DELETE FROM staged_entries WHERE id = ?').run(staged.id);
      await colorCell(staged.sheet_id, staged.tab_name, staged.marker_cell, COLOR_SYNCED);
      approvedCount++;
    }

    res.json({ message: `${approvedCount} entries approved and applied`, approvedCount });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to bulk approve', details: err.message });
  }
});

module.exports = router;
