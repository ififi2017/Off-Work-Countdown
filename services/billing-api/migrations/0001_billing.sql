-- Purchase tokens, Google payloads, email, IP, salary and work records are never stored.
CREATE TABLE purchases (
  token_hash TEXT PRIMARY KEY,
  product_id TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('subscription', 'lifetime')),
  status TEXT NOT NULL CHECK (status IN ('active', 'inactive', 'pending')),
  expires_at_ms INTEGER,
  verified_at_ms INTEGER NOT NULL,
  test_purchase INTEGER NOT NULL DEFAULT 0,
  revision INTEGER NOT NULL DEFAULT 1,
  replaced_by_hash TEXT
);

-- Short leases serialize Google queries for a token across Worker instances.
CREATE TABLE verification_leases (
  token_hash TEXT PRIMARY KEY,
  owner TEXT NOT NULL,
  expires_at_ms INTEGER NOT NULL
);

CREATE TABLE notifications (
  message_id TEXT PRIMARY KEY,
  handled_at_ms INTEGER NOT NULL
);
CREATE INDEX notifications_handled_at ON notifications(handled_at_ms);
CREATE INDEX verification_leases_expiry ON verification_leases(expires_at_ms);
