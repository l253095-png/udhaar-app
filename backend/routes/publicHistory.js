const express = require('express');
const { db } = require('../config/db');

const router = express.Router();

function escapeHtml(str) {
  return String(str ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

// GET /public/history/:token - Public, read-only. No login required.
router.get('/:token', async (req, res) => {
  try {
    const custResult = await db.execute({
      sql: 'SELECT * FROM customers WHERE public_token = ?',
      args: [req.params.token]
    });
    const customer = custResult.rows[0];
    if (!customer) {
      return res.status(404).send('<h2>Link not found or expired.</h2>');
    }

    const txResult = await db.execute({
      sql: 'SELECT * FROM transactions WHERE customer_id = ? ORDER BY created_at DESC',
      args: [customer.id]
    });

    const balance = customer.balance || 0;
    const rows = txResult.rows.map(t => `
      <tr>
        <td>${escapeHtml(t.created_at)}</td>
        <td style="color:${t.type === 'udhaar' ? '#c0392b' : '#27ae60'}">
          ${t.type === 'udhaar' ? 'Udhaar (Debit)' : 'Wasooli (Credit)'}
        </td>
        <td>Rs ${Number(t.amount).toFixed(0)}</td>
        <td>${escapeHtml(t.note || '')}</td>
      </tr>
    `).join('');

    const html = `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>${escapeHtml(customer.name)} - Udhaar History</title>
        <style>
          body { font-family: sans-serif; padding: 16px; max-width: 600px; margin: auto; }
          h2 { margin-bottom: 4px; }
          .balance { font-size: 24px; font-weight: bold; color: ${balance > 0 ? '#c0392b' : '#27ae60'}; }
          table { width: 100%; border-collapse: collapse; margin-top: 16px; }
          th, td { padding: 8px; border-bottom: 1px solid #eee; text-align: left; font-size: 13px; }
          th { background: #f5f5f5; }
        </style>
      </head>
      <body>
        <h2>${escapeHtml(customer.name)}</h2>
        <div>${escapeHtml(customer.phone || '')}</div>
        <div class="balance">Rs ${Math.abs(balance).toFixed(0)} ${balance > 0 ? '(Baqaya)' : '(Clear)'}</div>
        <table>
          <thead><tr><th>Date</th><th>Type</th><th>Amount</th><th>Note</th></tr></thead>
          <tbody>${rows || '<tr><td colspan="4">No transactions yet.</td></tr>'}</tbody>
        </table>
      </body>
      </html>
    `;

    res.send(html);
  } catch (error) {
    console.error(error);
    res.status(500).send('<h2>Something went wrong.</h2>');
  }
});

module.exports = router;