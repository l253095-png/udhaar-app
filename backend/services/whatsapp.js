// WhatsApp integration using whatsapp-web.js.
// First time this runs, a QR code will print in the terminal —
// scan it with WhatsApp on your phone (Settings > Linked Devices > Link a Device).
// After that, the session stays logged in automatically.

const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');

let isReady = false;
const client = new Client({ authStrategy: new LocalAuth() });

client.on('qr', (qr) => {
  console.log('\n=== Scan this QR code with WhatsApp (Linked Devices) ===\n');
  qrcode.generate(qr, { small: true });
});

client.on('ready', () => {
  isReady = true;
  console.log('WhatsApp connected — automatic messages are now active.');
});

client.on('auth_failure', (msg) => {
  console.error('WhatsApp authentication failed:', msg);
});

client.initialize();

/**
 * Sends a WhatsApp message to a customer's phone number.
 * Fails silently (logs only) if WhatsApp isn't connected yet,
 * so it never breaks the main app flow.
 */
async function sendWhatsAppMessage(phone, message) {
  if (!isReady) {
    console.log('WhatsApp not connected yet — message queued/skipped for', phone);
    return;
  }
  if (!phone) return;

  try {
    let formatted = phone.replace(/\D/g, ''); // digits only
    if (formatted.startsWith('0')) {
      formatted = '92' + formatted.slice(1); // Pakistan country code
    }
    const chatId = `${formatted}@c.us`;
    await client.sendMessage(chatId, message);
  } catch (err) {
    console.error('WhatsApp send failed for', phone, '-', err.message);
  }
}

module.exports = { sendWhatsAppMessage };
