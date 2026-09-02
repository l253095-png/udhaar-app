// backend/utils/dateHelper.js
//
// WHY THIS FILE EXISTS:
// Turso (cloud SQLite) runs on its own server, whose timezone we don't control.
// SQL defaults like `datetime('now', 'localtime')` use THAT server's clock, not
// Render's, not the owner's. Setting TZ=Asia/Karachi on Render does NOT fix this,
// because the SQL function executes remotely on Turso, not on our Node process.
//
// So instead, we compute the Pakistan-time timestamp HERE in Node.js (using
// Node's own Date object, which we DO control regardless of server TZ, by
// manually adding the +5:00 offset), and pass it explicitly into every INSERT.
// We never rely on SQLite's `datetime('now','localtime')` default again for
// anything that matters (transaction times, sync times).

const PKT_OFFSET_MS = 5 * 60 * 60 * 1000; // UTC+5, Pakistan has no DST

/**
 * Returns the current Pakistan time as 'YYYY-MM-DD HH:MM:SS' (SQLite TEXT format).
 */
function nowPkt() {
  const utcNow = new Date(Date.now());
  const pkt = new Date(utcNow.getTime() + PKT_OFFSET_MS);
  return pkt.toISOString().slice(0, 19).replace('T', ' ');
}

/**
 * Returns just today's date in Pakistan time as 'YYYY-MM-DD'.
 */
function todayPkt() {
  return nowPkt().slice(0, 10);
}

/**
 * Combines a date string ('YYYY-MM-DD') and optional time string ('HH:MM' or
 * 'HH:MM:SS') into a full 'YYYY-MM-DD HH:MM:SS' timestamp.
 */
function buildPktTimestamp(dateStr, timeStr) {
  if (!dateStr) return nowPkt();

  let time = timeStr;
  if (!time) {
    time = nowPkt().slice(11); // current PKT time-of-day as fallback
  }
  if (time.length === 5) time += ':00'; // 'HH:MM' -> 'HH:MM:SS'

  return `${dateStr} ${time}`;
}

module.exports = { nowPkt, todayPkt, buildPktTimestamp, PKT_OFFSET_MS };