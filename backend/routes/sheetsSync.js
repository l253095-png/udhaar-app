const express = require('express');
const { google } = require('googleapis');
const path = require('path');
const { db } = require('../config/db');
const { nowLocal, todayLocal } = require('../config/timeHelper');
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
async function colorCell(sheetId, cell, color) {
  if (!sheetId || !cell || !color) return;
  try {
    const auth = getAuthClient();
    const sheets = getSheetsClient(auth);
    const meta = await sheets.spreadsheets.get({ spreadsheetId: sheetId, fields: 'sheets(properties(sheetId,title))' });
    const sheetList = meta.data.sheets || [];
    if (sheetList.length === 0) return;
    const gridSheetId = sheetList[0].properties.sheetId; // each day's file has exactly one tab

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

async function getLatestSheetFile() {
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
    // fileName (e.g. "20.8.26") is the real day-identifier - every day's file
    // has its own internal tab still called "Sheet1", so the tab name alone
    // can't tell two different days apart.
    return { fileId: files[0].id, fileName: files[0].name };
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

async function applyTransaction(customerId, type, amount, source, userId, isoDate, syncTab) {
  // Safety net: if an identical transaction for this customer/type/amount/source
  // already exists today, skip re-inserting it (defense in depth alongside the
  // synced_rows tracking, in case sync is ever re-run in an unusual way).
  const dupe = await db.execute({
    sql: "SELECT * FROM transactions WHERE customer_id = ? AND type = ? AND amount = ? AND source = ? AND date(created_at) = date(?)",
    args: [customerId, type, amount, source, isoDate || todayLocal()],
  });
  if (dupe.rows[0]) {
    console.log(`[Sheets Sync] Skipping duplicate transaction for customer ${customerId}: ${type} Rs${amount}`);
    const cur = await db.execute({ sql: 'SELECT * FROM customers WHERE id = ?', args: [customerId] });
    return cur.rows[0];
  }

  const balanceChange = type === 'udhaar' ? amount : -amount;
  await db.execute({
    sql: 'INSERT INTO transactions (customer_id, type, amount, source, sync_tab, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    args: [customerId, type, amount, source, syncTab || null, userId, nowLocal()],
  });
  await db.execute({
    sql: 'UPDATE customers SET balance = balance + ? WHERE id = ?',
    args: [balanceChange, customerId],
  });
  const updated = await db.execute({ sql: 'SELECT * FROM customers WHERE id = ?', args: [customerId] });
  return updated.rows[0];
}

async function upsertDailyExpense(category, isoDate, amount, userId, syncTab) {
  const found = await db.execute({
    sql: "SELECT * FROM expenses WHERE category = ? AND entry_date = ? AND source = 'google_sheet'",
    args: [category, isoDate],
  });
  const existing = found.rows[0];
  if (existing) {
    await db.execute({
      sql: 'UPDATE expenses SET amount = ?, sync_tab = ? WHERE id = ?',
      args: [amount, syncTab || null, existing.id],
    });
  } else {
    await db.execute({
      sql: 'INSERT INTO expenses (category, amount, entry_date, source, sync_tab, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      args: [category, amount, isoDate, 'google_sheet', syncTab || null, userId, nowLocal()],
    });
  }
}

// POST /api/sheets-sync/run
router.post('/run', async (req, res) => {
  try {
    const auth = getAuthClient();
    const sheets = getSheetsClient(auth);
    const { fileId: sheetId, fileName: tabName } = await getLatestSheetFile();
    // The Sheet inside every day's file is always called "Sheet1" internally -
    // it does NOT identify which day this is. `tabName` (the day's FILE name,
    // e.g. "20.8.26") is what we use everywhere for tracking; `sheetTabTitle`
    // is only used to build the A1 range references below.
    const sheetTabTitle = await getFirstSheetName(sheetId);
    const isoDate = todayLocal();

    const allCustomers = (await db.execute('SELECT * FROM customers')).rows;

    // Pre-load this tab's already-synced row keys once, so the per-row check
    // stays a fast in-memory lookup instead of a network round-trip each time.
    const syncedKeys = new Set(
      (await db.execute({
        sql: 'SELECT row_key FROM synced_rows WHERE tab_name = ?',
        args: [tabName],
      })).rows.map((r) => r.row_key)
    );

    const ignoredNames = new Set(
      (await db.execute('SELECT normalized_name FROM ignored_sheet_names')).rows.map((r) => r.normalized_name)
    );

    let processedCount = 0;
    let pendingCount = 0;
    let ignoredCount = 0;
    const colorJobs = [];

    for (const block of BLOCKS) {
      const result = await sheets.spreadsheets.values.get({
        spreadsheetId: sheetId,
        range: `'${sheetTabTitle}'!${block.range}`,
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
        if (syncedKeys.has(rowKey)) continue;

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
          await db.execute({
            sql: 'INSERT INTO staged_entries (customer_id, type, amount, tab_name, sheet_id, marker_cell, row_key, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            args: [exactMatch.id, block.type, amount, tabName, sheetId, nameCell, rowKey, req.user.id, nowLocal()],
          });
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
          await db.execute({
            sql: `INSERT INTO pending_sheet_syncs
                  (sheet_name, amount, type, tab_name, sheet_id, marker_cell, row_key, suggested_customer_id, suggested_customer_name, created_at)
                  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            args: [
              name,
              amount,
              block.type,
              tabName,
              sheetId,
              nameCell,
              rowKey,
              match ? match.customer.id : null,
              match ? match.customer.name : null,
              nowLocal(),
            ],
          });
          pendingCount++;
          colorJobs.push({ cell: nameCell, color: COLOR_PENDING });
        }

        await db.execute({
          sql: 'INSERT OR IGNORE INTO synced_rows (tab_name, row_key) VALUES (?, ?)',
          args: [tabName, rowKey],
        });
        syncedKeys.add(rowKey);
      }
    }

    // Color all processed row name-cells (blue=imported, yellow=pending review, grey=ignored)
    for (const job of colorJobs) {
      await colorCell(sheetId, job.cell, job.color);
    }

    const cellRefs = Object.values(SINGLE_CELLS).map((cell) => `'${sheetTabTitle}'!${cell}`);
    const batchResult = await sheets.spreadsheets.values.batchGet({ spreadsheetId: sheetId, ranges: cellRefs });
    const categories = Object.keys(SINGLE_CELLS);
    for (let idx = 0; idx < categories.length; idx++) {
      const valueRange = batchResult.data.valueRanges[idx];
      if (!valueRange) continue;
      const raw = valueRange.values && valueRange.values[0] && valueRange.values[0][0];
      const amount = parseFloat(raw);
      if (!isNaN(amount)) {
        await upsertDailyExpense(categories[idx], isoDate, amount, req.user.id, tabName);
      }
    }

    await db.execute({
      sql: 'INSERT INTO sync_log (tab_name, rows_synced, new_customers_flagged, synced_by, synced_at) VALUES (?, ?, ?, ?, ?)',
      args: [tabName, processedCount, pendingCount, req.user.id, nowLocal()],
    });

    res.json({ success: true, processedCount, pendingCount, ignoredCount, tabName });
  } catch (err) {
    console.error('[Sheets Sync Error]', err);
    res.status(500).json({
      success: false,
      error: err.error || err.message || 'Sync failed',
      errorCode: err.errorCode,
      details: err.details,
    });
  }
});

// GET /api/sheets-sync/pending
router.get('/pending', async (req, res) => {
  try {
    const result = await db.execute('SELECT * FROM pending_sheet_syncs ORDER BY created_at DESC');
    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to list pending entries', details: err.message });
  }
});

// GET /api/sheets-sync/pending-count
router.get('/pending-count', async (req, res) => {
  try {
    const result = await db.execute('SELECT COUNT(*) as count FROM pending_sheet_syncs');
    res.json({ count: Number(result.rows[0]?.count || 0) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to count pending entries', details: err.message });
  }
});

// POST /api/sheets-sync/approve
// Body: { pendingId, action: 'link' | 'create' | 'reject' | 'ignore', customerId?, newCustomerName? }
router.post('/approve', async (req, res) => {
  const { pendingId, action, customerId, newCustomerName } = req.body;
  try {
    const found = await db.execute({
      sql: 'SELECT * FROM pending_sheet_syncs WHERE id = ?',
      args: [pendingId],
    });
    const pending = found.rows[0];
    if (!pending) return res.status(404).json({ error: 'Pending entry not found' });

    if (action === 'reject') {
      await db.execute({ sql: 'DELETE FROM pending_sheet_syncs WHERE id = ?', args: [pendingId] });
      // Un-mark this row as synced, so the NEXT sync run reconsiders it
      // (e.g. if the owner fixes the name in the Sheet afterward).
      if (pending.row_key) {
        await db.execute({
          sql: 'DELETE FROM synced_rows WHERE tab_name = ? AND row_key = ?',
          args: [pending.tab_name, pending.row_key],
        });
      }
      await colorCell(pending.sheet_id, pending.marker_cell, COLOR_CLEAR);
      return res.json({ message: 'Rejected — will be reconsidered on the next sync' });
    }

    if (action === 'ignore') {
      // Permanently ignore this exact name (e.g. "43BRENT" turns out to be a
      // rent/location code, not a real customer) so it's never flagged again.
      await db.execute({
        sql: 'INSERT OR IGNORE INTO ignored_sheet_names (normalized_name, original_name, created_by) VALUES (?, ?, ?)',
        args: [normalizeIgnoredName(pending.sheet_name), pending.sheet_name, req.user.id],
      });
      await db.execute({ sql: 'DELETE FROM pending_sheet_syncs WHERE id = ?', args: [pendingId] });
      await colorCell(pending.sheet_id, pending.marker_cell, COLOR_IGNORED);
      return res.json({ message: `"${pending.sheet_name}" will be auto-skipped in every future sync` });
    }

    let targetCustomerId = customerId;
    if (action === 'create') {
      const info = await db.execute({
        sql: 'INSERT INTO customers (name, phone, created_at) VALUES (?, ?, ?)',
        args: [newCustomerName || pending.sheet_name, pending.phone || null, nowLocal()],
      });
      targetCustomerId = Number(info.lastInsertRowid);
    } else if (action !== 'link' || !targetCustomerId) {
      return res.status(400).json({ error: 'action must be link (with customerId), create, reject, or ignore' });
    }

    // Now matched to a customer, but STILL doesn't touch their balance -
    // it moves into the "Imported" list for the Owner's final approval.
    await db.execute({
      sql: 'INSERT INTO staged_entries (customer_id, type, amount, tab_name, sheet_id, marker_cell, row_key, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      args: [targetCustomerId, pending.type, pending.amount, pending.tab_name, pending.sheet_id, pending.marker_cell, pending.row_key, req.user.id, nowLocal()],
    });

    await db.execute({ sql: 'DELETE FROM pending_sheet_syncs WHERE id = ?', args: [pendingId] });
    await colorCell(pending.sheet_id, pending.marker_cell, COLOR_STAGED);
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
      const found = await db.execute({
        sql: 'SELECT * FROM pending_sheet_syncs WHERE id = ?',
        args: [pendingId],
      });
      const pending = found.rows[0];
      if (!pending) continue;

      await db.execute({ sql: 'DELETE FROM pending_sheet_syncs WHERE id = ?', args: [pendingId] });
      if (pending.row_key) {
        await db.execute({
          sql: 'DELETE FROM synced_rows WHERE tab_name = ? AND row_key = ?',
          args: [pending.tab_name, pending.row_key],
        });
      }
      await colorCell(pending.sheet_id, pending.marker_cell, COLOR_CLEAR);
      rejectedCount++;
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
      const found = await db.execute({
        sql: 'SELECT * FROM pending_sheet_syncs WHERE id = ?',
        args: [pendingId],
      });
      const pending = found.rows[0];
      if (!pending) continue;

      const info = await db.execute({
        sql: 'INSERT INTO customers (name, phone, created_at) VALUES (?, ?, ?)',
        args: [pending.sheet_name, pending.phone || null, nowLocal()],
      });
      const customerId = Number(info.lastInsertRowid);
      createdCustomerIds.push(customerId);

      // Stage it - doesn't touch the balance until approved from Imported Entries.
      await db.execute({
        sql: 'INSERT INTO staged_entries (customer_id, type, amount, tab_name, sheet_id, marker_cell, row_key, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        args: [customerId, pending.type, pending.amount, pending.tab_name, pending.sheet_id, pending.marker_cell, pending.row_key, req.user.id, nowLocal()],
      });

      await db.execute({ sql: 'DELETE FROM pending_sheet_syncs WHERE id = ?', args: [pendingId] });
      await colorCell(pending.sheet_id, pending.marker_cell, COLOR_STAGED);
      approvedCount++;
    }

    res.json({ message: 'Moved to Imported Entries — approve them there to apply to balances', approvedCount, createdCustomerIds });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to bulk approve', details: err.message });
  }
});

// GET /api/sheets-sync/history - list past sync runs (for the Undo picker)
router.get('/history', async (req, res) => {
  try {
    const result = await db.execute('SELECT * FROM sync_log ORDER BY synced_at DESC LIMIT 30');
    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to load sync history', details: err.message });
  }
});

// GET /api/sheets-sync/legacy-count - counts pre-fix sync entries that have
// no day-tag (sync_tab IS NULL), so the normal per-day Undo can't reach them.
router.get('/legacy-count', async (req, res) => {
  try {
    const result = await db.execute(
      "SELECT COUNT(*) as count FROM transactions WHERE source = 'google_sheet' AND sync_tab IS NULL"
    );
    res.json({ count: Number(result.rows[0]?.count || 0) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to count legacy entries', details: err.message });
  }
});

// POST /api/sheets-sync/undo-legacy
// Body: { password }
// One-time cleanup: reverses ALL Sheet-sync transactions/expenses that predate
// the day-tracking fix (they have no tab_name, so the normal Undo can't find them).
router.post('/undo-legacy', async (req, res) => {
  const { password } = req.body;
  const requiredPassword = process.env.UNDO_PASSWORD || 'undosheet';
  if (password !== requiredPassword) {
    return res.status(403).json({ error: 'Incorrect undo password' });
  }

  try {
    const found = await db.execute(
      "SELECT * FROM transactions WHERE source = 'google_sheet' AND sync_tab IS NULL"
    );
    const transactions = found.rows;

    // All-or-nothing: balances and their transactions must move together.
    const tx = await db.transaction('write');
    try {
      for (const txn of transactions) {
        const balanceChange = txn.type === 'udhaar' ? -txn.amount : txn.amount;
        await tx.execute({
          sql: 'UPDATE customers SET balance = balance + ? WHERE id = ?',
          args: [balanceChange, txn.customer_id],
        });
        await tx.execute({ sql: 'DELETE FROM transactions WHERE id = ?', args: [txn.id] });
      }
      await tx.execute("DELETE FROM expenses WHERE source = 'google_sheet' AND sync_tab IS NULL");
      await tx.execute('DELETE FROM staged_entries WHERE tab_name IS NULL');
      await tx.execute('DELETE FROM pending_sheet_syncs WHERE tab_name IS NULL');
      // Old (pre-fix) rows were tracked under the literal tab name "Sheet1"
      // (the internal tab, not a real day) - clear only those, not any
      // correctly-tagged rows from a real day that may already exist.
      await tx.execute("DELETE FROM synced_rows WHERE tab_name = 'Sheet1' OR tab_name IS NULL");
      await tx.execute('DELETE FROM sync_log WHERE tab_name IS NULL');
      await tx.commit();
    } catch (e) {
      await tx.rollback();
      throw e;
    }

    res.json({
      message: `Legacy cleanup complete. ${transactions.length} old (pre-fix) transactions reversed. All Sheet rows will be reconsidered on your next sync.`,
      reversedCount: transactions.length,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to undo legacy entries', details: err.message });
  }
});

// POST /api/sheets-sync/undo
// Body: { tabName, password }
// Reverses every transaction/expense that came from that day's sync, and
// frees up that tab's rows so a fresh sync run will reprocess them from scratch.
router.post('/undo', async (req, res) => {
  const { tabName, password } = req.body;
  if (!tabName) return res.status(400).json({ error: 'tabName is required' });

  const requiredPassword = process.env.UNDO_PASSWORD || 'undosheet';
  if (password !== requiredPassword) {
    return res.status(403).json({ error: 'Incorrect undo password' });
  }

  try {
    const found = await db.execute({
      sql: "SELECT * FROM transactions WHERE sync_tab = ? AND source = 'google_sheet'",
      args: [tabName],
    });
    const transactions = found.rows;

    const tx = await db.transaction('write');
    try {
      for (const txn of transactions) {
        const balanceChange = txn.type === 'udhaar' ? -txn.amount : txn.amount; // reverse it
        await tx.execute({
          sql: 'UPDATE customers SET balance = balance + ? WHERE id = ?',
          args: [balanceChange, txn.customer_id],
        });
        await tx.execute({ sql: 'DELETE FROM transactions WHERE id = ?', args: [txn.id] });
      }
      await tx.execute({
        sql: "DELETE FROM expenses WHERE sync_tab = ? AND source = 'google_sheet'",
        args: [tabName],
      });
      await tx.execute({ sql: 'DELETE FROM pending_sheet_syncs WHERE tab_name = ?', args: [tabName] });
      await tx.execute({ sql: 'DELETE FROM staged_entries WHERE tab_name = ?', args: [tabName] });
      await tx.execute({ sql: 'DELETE FROM synced_rows WHERE tab_name = ?', args: [tabName] });
      await tx.execute({ sql: 'DELETE FROM sync_log WHERE tab_name = ?', args: [tabName] });
      await tx.commit();
    } catch (e) {
      await tx.rollback();
      throw e;
    }

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
router.get('/staged', async (req, res) => {
  try {
    const result = await db.execute(
      `SELECT se.*, c.name as customer_name, c.phone as customer_phone
       FROM staged_entries se
       JOIN customers c ON c.id = se.customer_id
       ORDER BY se.created_at DESC`
    );
    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to list imported entries', details: err.message });
  }
});

// GET /api/sheets-sync/staged-count
router.get('/staged-count', async (req, res) => {
  try {
    const result = await db.execute('SELECT COUNT(*) as count FROM staged_entries');
    res.json({ count: Number(result.rows[0]?.count || 0) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to count imported entries', details: err.message });
  }
});

// POST /api/sheets-sync/staged/:id/approve - THE final step: applies to balance
router.post('/staged/:id/approve', async (req, res) => {
  try {
    const found = await db.execute({
      sql: 'SELECT * FROM staged_entries WHERE id = ?',
      args: [req.params.id],
    });
    const staged = found.rows[0];
    if (!staged) return res.status(404).json({ error: 'Entry not found' });

    const isoDate = todayLocal();
    const updated = await applyTransaction(
      staged.customer_id, staged.type, staged.amount, 'google_sheet', req.user.id, isoDate, staged.tab_name
    );
    notify(updated, staged.type, staged.amount, updated.balance);

    await db.execute({ sql: 'DELETE FROM staged_entries WHERE id = ?', args: [staged.id] });
    await colorCell(staged.sheet_id, staged.marker_cell, COLOR_SYNCED);
    res.json({ message: 'Approved and applied to balance', customerId: staged.customer_id, newBalance: updated.balance });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to approve entry', details: err.message });
  }
});

// POST /api/sheets-sync/staged/:id/reject - discard it, row gets reconsidered next sync
router.post('/staged/:id/reject', async (req, res) => {
  try {
    const found = await db.execute({
      sql: 'SELECT * FROM staged_entries WHERE id = ?',
      args: [req.params.id],
    });
    const staged = found.rows[0];
    if (!staged) return res.status(404).json({ error: 'Entry not found' });

    await db.execute({ sql: 'DELETE FROM staged_entries WHERE id = ?', args: [staged.id] });
    if (staged.row_key) {
      await db.execute({
        sql: 'DELETE FROM synced_rows WHERE tab_name = ? AND row_key = ?',
        args: [staged.tab_name, staged.row_key],
      });
    }
    await colorCell(staged.sheet_id, staged.marker_cell, COLOR_CLEAR);
    res.json({ message: 'Rejected — will be reconsidered on the next sync' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to reject entry', details: err.message });
  }
});

// POST /api/sheets-sync/staged/bulk-approve - approve everything at once
router.post('/staged/bulk-approve', async (req, res) => {
  try {
    const allStaged = (await db.execute('SELECT * FROM staged_entries')).rows;
    const isoDate = todayLocal();
    let approvedCount = 0;

    for (const staged of allStaged) {
      const updated = await applyTransaction(
        staged.customer_id, staged.type, staged.amount, 'google_sheet', req.user.id, isoDate, staged.tab_name
      );
      notify(updated, staged.type, staged.amount, updated.balance);
      await db.execute({ sql: 'DELETE FROM staged_entries WHERE id = ?', args: [staged.id] });
      await colorCell(staged.sheet_id, staged.marker_cell, COLOR_SYNCED);
      approvedCount++;
    }

    res.json({ message: `${approvedCount} entries approved and applied`, approvedCount });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to bulk approve', details: err.message });
  }
});

module.exports = router;
