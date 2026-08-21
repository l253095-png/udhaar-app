// SQLite's `DEFAULT (datetime('now','localtime'))` on a column only ever
// applies at the moment the TABLE was first created - if a table already
// existed (e.g. from an older version of this app, before timestamps were
// fixed to use local time), that old default is permanently baked in and
// will NOT pick up later schema changes, even after migrations.
//
// To make timestamps reliably correct regardless of table history, every
// INSERT in this app should pass created_at/entry_date explicitly using
// these helpers instead of depending on the column's default.

function nowLocal() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

function todayLocal() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

module.exports = { nowLocal, todayLocal };
