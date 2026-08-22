const { db } = require('../config/db');

async function logAudit(entityType, entityId, action, description, userId) {
  try {
    await db.execute({
      sql: 'INSERT INTO audit_log (entity_type, entity_id, action, description, performed_by) VALUES (?, ?, ?, ?, ?)',
      args: [entityType, entityId, action, description, userId || null]
    });
  } catch (e) {
    console.error('Audit log failed:', e);
  }
}

module.exports = { logAudit };