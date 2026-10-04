import { ApiError, type Entitlement, type StoredEntitlement } from './types';

interface Row {
  token_hash: string; product_id: string; kind: Entitlement['kind']; status: Entitlement['status'];
  expires_at_ms: number | null; verified_at_ms: number; test_purchase: number; revision: number;
  replaced_by_hash: string | null;
}

export async function readPurchase(db: D1Database, hash: string): Promise<StoredEntitlement | null> {
  const row = await db.prepare('SELECT * FROM purchases WHERE token_hash = ?').bind(hash).first<Row>();
  if (!row) return null;
  return { tokenHash: row.token_hash, productId: row.product_id, kind: row.kind,
    status: row.replaced_by_hash ? 'inactive' : row.status, expiresAtMs: row.expires_at_ms,
    verifiedAtMs: row.verified_at_ms, testPurchase: !!row.test_purchase, revision: row.revision,
    replacedByHash: row.replaced_by_hash };
}

export async function acquireLease(db: D1Database, hash: string, now: number): Promise<string> {
  const owner = crypto.randomUUID();
  const result = await db.prepare(`INSERT INTO verification_leases(token_hash, owner, expires_at_ms) VALUES (?, ?, ?)
    ON CONFLICT(token_hash) DO UPDATE SET owner = excluded.owner, expires_at_ms = excluded.expires_at_ms
    WHERE verification_leases.expires_at_ms <= ? RETURNING owner`)
    .bind(hash, owner, now + 45_000, now).first<{ owner: string }>();
  if (result?.owner !== owner) throw new ApiError(503, 'verification_in_progress');
  return owner;
}

export async function releaseLease(db: D1Database, hash: string, owner: string): Promise<void> {
  await db.prepare('DELETE FROM verification_leases WHERE token_hash = ? AND owner = ?').bind(hash, owner).run();
}

export async function savePurchase(db: D1Database, hash: string, owner: string, grant: Entitlement,
  linkedHash: string | undefined, now: number): Promise<StoredEntitlement> {
  // The lease owner is checked inside the transaction: a timed-out request cannot overwrite a newer query.
  const guard = `EXISTS (SELECT 1 FROM verification_leases WHERE token_hash = ? AND owner = ? AND expires_at_ms > ?)`;
  const statements = [db.prepare(`INSERT INTO purchases(token_hash, product_id, kind, status, expires_at_ms, verified_at_ms, test_purchase)
    SELECT ?, ?, ?, ?, ?, ?, ? WHERE ${guard}
    ON CONFLICT(token_hash) DO UPDATE SET product_id = excluded.product_id, kind = excluded.kind,
      status = CASE WHEN purchases.replaced_by_hash IS NULL THEN excluded.status ELSE 'inactive' END,
      expires_at_ms = excluded.expires_at_ms, verified_at_ms = excluded.verified_at_ms,
      test_purchase = excluded.test_purchase, revision = purchases.revision + 1
    RETURNING token_hash`).bind(hash, grant.productId, grant.kind, grant.status, grant.expiresAtMs,
      grant.verifiedAtMs, grant.testPurchase ? 1 : 0, hash, owner, now)];
  // Pending replacements do not invalidate the still-paid old purchase.
  if (linkedHash && linkedHash !== hash && grant.status === 'active') {
    statements.push(db.prepare(`INSERT INTO purchases(token_hash, product_id, kind, status, verified_at_ms, replaced_by_hash)
      SELECT ?, ?, 'subscription', 'inactive', ?, ? WHERE ${guard}
      ON CONFLICT(token_hash) DO UPDATE SET status = 'inactive', replaced_by_hash = excluded.replaced_by_hash,
        verified_at_ms = MAX(purchases.verified_at_ms, excluded.verified_at_ms), revision = purchases.revision + 1`)
      .bind(linkedHash, grant.productId, grant.verifiedAtMs, hash, hash, owner, now));
  }
  const results = await db.batch(statements);
  if (!results[0].results.length) throw new ApiError(503, 'verification_in_progress');
  const saved = await readPurchase(db, hash);
  if (!saved) throw new ApiError(503, 'verification_unavailable');
  return saved;
}

export async function notificationHandled(db: D1Database, id: string): Promise<boolean> {
  return !!await db.prepare('SELECT message_id FROM notifications WHERE message_id = ?').bind(id).first();
}

export async function finishNotification(db: D1Database, id: string, now: number): Promise<void> {
  await db.batch([
    db.prepare('INSERT OR IGNORE INTO notifications(message_id, handled_at_ms) VALUES (?, ?)').bind(id, now),
    // Keep thirty days of deduplication; an older replay simply queries Google again.
    db.prepare('DELETE FROM notifications WHERE handled_at_ms < ?').bind(now - 30 * 86_400_000),
    db.prepare('DELETE FROM verification_leases WHERE expires_at_ms < ?').bind(now - 60_000),
  ]);
}
