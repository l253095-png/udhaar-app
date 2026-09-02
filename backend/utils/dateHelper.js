const PKT_OFFSET_MS = 5 * 60 * 60 * 1000; // UTC+5, Pakistan has no DST

function nowPkt() {
  const utcNow = new Date(Date.now());
  const pkt = new Date(utcNow.getTime() + PKT_OFFSET_MS);
  return pkt.toISOString().slice(0, 19).replace('T', ' ');
}

function todayPkt() {
  return nowPkt().slice(0, 10);
}

function buildPktTimestamp(dateStr, timeStr) {
  if (!dateStr) return nowPkt();

  let time = timeStr;
  if (!time) {
    time = nowPkt().slice(11);
  }
  if (time.length === 5) time += ':00';

  return `${dateStr} ${time}`;
}

module.exports = { nowPkt, todayPkt, buildPktTimestamp, PKT_OFFSET_MS };