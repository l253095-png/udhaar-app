const express = require('express');
const { db } = require('../config/db');
const { authenticate, ownerOnly } = require('../middleware/auth');
const PDFDocument = require('pdfkit');
const { logAudit } = require('../utils/auditLog');
const router = express.Router();
router.use(authenticate);

// WhatsApp is optional — if the package isn't installed yet or WhatsApp isn't linked, this quietly does nothing.
let sendWhatsAppMessage = async () => {};
try {
  sendWhatsAppMessage = require('../services/whatsapp').sendWhatsAppMessage;
} catch (e) {
  console.log('WhatsApp module not active yet.');
}

function notifyCustomer(customer, type, amount, newBalance) {
  const typeLabel = type === 'udhaar' ? 'Udhaar (Debit)' : 'Wasooli (Credit)';
  const message =
    `Assalam-o-Alaikum ${customer.name},\n` +
    `Aaj aap ne Rs ${amount} ka ${typeLabel} kiya.\n` +
    `Aapka remaining balance: Rs ${newBalance}\n` +
    `- Shukriya`;
  sendWhatsAppMessage(customer.phone, message).catch(() => {});
}

// GET /api/transactions - Owner and Worker can view all transactions
router.get('/', async (req, res) => {
  try {
    const { type, period } = req.query;

    let query = `SELECT t.*, c.name as customer_name, c.phone as customer_phone
                 FROM transactions t
                 JOIN customers c ON c.id = t.customer_id
                 WHERE 1=1`;
    const params = [];

    if (type === 'udhaar' || type === 'wasooli') {
      query += ' AND t.type = ?';
      params.push(type);
    }

    if (period === 'today') {
      query += " AND date(t.created_at) = date('now', 'localtime')";
    } else if (period === 'month') {
      query += " AND strftime('%Y-%m', t.created_at) = strftime('%Y-%m', 'now', 'localtime')";
    }

    query += ' ORDER BY t.created_at DESC LIMIT 500';

    const result = await db.execute({ sql: query, args: params });
    const transactions = result.rows;

    const total = transactions.reduce((sum, t) => sum + t.amount, 0);
    res.json({ transactions, total, count: transactions.length });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error fetching transactions' });
  }
});

// POST /api/transactions - Owner only
router.post('/', ownerOnly, async (req, res) => {
  try {
    const { customer_id, type, amount, note } = req.body;
    if (!customer_id || !type || !amount) {
      return res.status(400).json({ error: 'customer_id, type, and amount are required' });
    }
    if (!['udhaar', 'wasooli'].includes(type)) {
      return res.status(400).json({ error: 'type must be udhaar or wasooli' });
    }

    const custResult = await db.execute({
      sql: 'SELECT * FROM customers WHERE id = ?',
      args: [customer_id]
    });
    const customer = custResult.rows[0];
    if (!customer) return res.status(404).json({ error: 'Customer not found' });

    const balanceChange = type === 'udhaar' ? amount : -amount;

    // Execute using Turso transaction batch
    const batchResult = await db.batch([
      {
        sql: 'INSERT INTO transactions (customer_id, type, amount, note, source, created_by) VALUES (?, ?, ?, ?, ?, ?)',
        args: [customer_id, type, amount, note || null, 'app', req.user.id]
      },
      {
        sql: 'UPDATE customers SET balance = balance + ? WHERE id = ?',
        args: [balanceChange, customer_id]
      }
    ]);

    const insertResult = batchResult[0];
    const id = Number(insertResult.lastInsertRowid);

    const updatedCustResult = await db.execute({
      sql: 'SELECT * FROM customers WHERE id = ?',
      args: [customer_id]
    });
    const updatedCustomer = updatedCustResult.rows[0];
    
        notifyCustomer(customer, type, amount, updatedCustomer.balance);

    await logAudit(
      'transaction',
      id,
      'create',
      `${type === 'udhaar' ? 'Debit' : 'Credit'} of Rs ${amount} added for "${customer.name}"`,
      req.user.id
    );

    res.status(201).json({ id, message: 'Transaction recorded' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error creating transaction' });
  }
});

// PUT /api/transactions/:id - Owner only
router.put('/:id', ownerOnly, async (req, res) => {
  try {
    const { type, amount, note } = req.body;
    const txnResult = await db.execute({
      sql: 'SELECT * FROM transactions WHERE id = ?',
      args: [req.params.id]
    });
    const txn = txnResult.rows[0];
    if (!txn) return res.status(404).json({ error: 'Transaction not found' });

    const newType = type || txn.type;
    const newAmount = amount !== undefined ? amount : txn.amount;
    if (!['udhaar', 'wasooli'].includes(newType)) {
      return res.status(400).json({ error: 'type must be udhaar or wasooli' });
    }

    const oldEffect = txn.type === 'udhaar' ? -txn.amount : txn.amount; // undo old
    const newEffect = newType === 'udhaar' ? newAmount : -newAmount; // apply new

        await db.batch([
      {
        sql: 'UPDATE customers SET balance = balance + ? WHERE id = ?',
        args: [oldEffect, txn.customer_id]
      },
      {
        sql: 'UPDATE transactions SET type = ?, amount = ?, note = ? WHERE id = ?',
        args: [newType, newAmount, note ?? txn.note, req.params.id]
      },
      {
        sql: 'UPDATE customers SET balance = balance + ? WHERE id = ?',
        args: [newEffect, txn.customer_id]
      }
    ]);

    await logAudit(
      'transaction',
      req.params.id,
      'update',
      `Transaction edited: ${txn.type} Rs ${txn.amount} -> ${newType} Rs ${newAmount}`,
      req.user.id
    );

    res.json({ message: 'Transaction updated' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error updating transaction' });
  }
});

// DELETE /api/transactions/:id - Owner only
router.delete('/:id', ownerOnly, async (req, res) => {
  try {
    const txnResult = await db.execute({
      sql: 'SELECT * FROM transactions WHERE id = ?',
      args: [req.params.id]
    });
    const txn = txnResult.rows[0];
    if (!txn) return res.status(404).json({ error: 'Transaction not found' });

    const balanceChange = txn.type === 'udhaar' ? -txn.amount : txn.amount;

        await db.batch([
      {
        sql: 'DELETE FROM transactions WHERE id = ?',
        args: [req.params.id]
      },
      {
        sql: 'UPDATE customers SET balance = balance + ? WHERE id = ?',
        args: [balanceChange, txn.customer_id]
      }
    ]);

    await logAudit(
      'transaction',
      req.params.id,
      'delete',
      `Transaction deleted: ${txn.type} Rs ${txn.amount}`,
      req.user.id
    );

    res.json({ message: 'Transaction deleted and balance adjusted' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error deleting transaction' });
  }
});
// GET /api/transactions/range-report/pdf?start=YYYY-MM-DD&end=YYYY-MM-DD
// System-wide PDF: every transaction in the date range, with the customer's
// balance right after that specific transaction (walked back from their
// CURRENT balance across their full history, then filtered to the range).
router.get('/range-report/pdf', ownerOnly, async (req, res) => {
  try {
    const { start, end } = req.query;
    if (!start || !end) {
      return res.status(400).json({ error: 'start and end dates are required' });
    }

    const rangeResult = await db.execute({
      sql: `SELECT t.*, c.name as customer_name
            FROM transactions t
            JOIN customers c ON c.id = t.customer_id
            WHERE date(t.created_at) BETWEEN date(?) AND date(?)
            ORDER BY t.created_at ASC`,
      args: [start, end]
    });
    const rangeTxns = rangeResult.rows;

    // Work out "balance after" for each transaction, per customer.
    const customerIds = [...new Set(rangeTxns.map(t => t.customer_id))];
    const balanceAfterMap = {};

    for (const custId of customerIds) {
      const custResult = await db.execute({
        sql: 'SELECT * FROM customers WHERE id = ?',
        args: [custId]
      });
      const customer = custResult.rows[0];
      if (!customer) continue;

      const allTxResult = await db.execute({
        sql: 'SELECT * FROM transactions WHERE customer_id = ? ORDER BY created_at DESC',
        args: [custId]
      });

      let runningBalance = customer.balance || 0;
      for (const t of allTxResult.rows) {
        balanceAfterMap[t.id] = runningBalance;
        const amt = t.amount || 0;
        const effect = t.type === 'udhaar' ? amt : -amt;
        runningBalance -= effect;
      }
    }

    const doc = new PDFDocument({ margin: 40, size: 'A4' });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="report_${start}_to_${end}.pdf"`);
    doc.pipe(res);

    doc.fontSize(18).text('Udhaar Report', { align: 'center' });
    doc.moveDown(0.3);
    doc.fontSize(11).fillColor('#555').text(`${start} to ${end}`, { align: 'center' });
    doc.moveDown(1);

    const totalDebit = rangeTxns.filter(t => t.type === 'udhaar').reduce((s, t) => s + t.amount, 0);
    const totalCredit = rangeTxns.filter(t => t.type === 'wasooli').reduce((s, t) => s + t.amount, 0);
    doc.fontSize(12).fillColor('#000')
      .text(`Total Debit (Udhaar): Rs ${totalDebit.toFixed(0)}`)
      .text(`Total Credit (Wasooli): Rs ${totalCredit.toFixed(0)}`)
      .text(`Total Entries: ${rangeTxns.length}`);
    doc.moveDown(1);

    let y = doc.y;
    doc.fontSize(10).fillColor('#000');
    doc.text('Date', 40, y, { width: 90 });
    doc.text('Customer', 140, y, { width: 150 });
    doc.text('Type', 300, y, { width: 70 });
    doc.text('Amount', 380, y, { width: 70 });
    doc.text('Balance After', 460, y, { width: 95 });
    y += 16;
    doc.moveTo(40, y).lineTo(555, y).stroke();
    y += 6;

    for (const t of rangeTxns) {
      if (y > 770) {
        doc.addPage();
        y = 40;
      }
      const dateStr = (t.created_at || '').split(' ')[0];
      const balAfter = balanceAfterMap[t.id];

      doc.fontSize(9).fillColor('#000').text(dateStr, 40, y, { width: 90 });
      doc.text(t.customer_name || '', 140, y, { width: 150 });
      doc.fillColor(t.type === 'udhaar' ? '#c0392b' : '#27ae60')
        .text(t.type === 'udhaar' ? 'Debit' : 'Credit', 300, y, { width: 70 });
      doc.fillColor('#000').text(`Rs ${t.amount.toFixed(0)}`, 380, y, { width: 70 });
      doc.text(balAfter != null ? `Rs ${balAfter.toFixed(0)}` : '-', 460, y, { width: 95 });

      y += 16;
    }

    doc.end();
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Server error generating report' });
  }
});
module.exports = router;