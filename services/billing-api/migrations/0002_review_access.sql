-- Review access is isolated from purchase/notification data. No raw credentials or JWTs.
CREATE TABLE review_credentials (
  credential_hash TEXT PRIMARY KEY,
  revision INTEGER NOT NULL DEFAULT 1,
  revoked INTEGER NOT NULL DEFAULT 0 CHECK(revoked IN (0, 1)),
  created_at_ms INTEGER NOT NULL
);
CREATE TABLE review_installations (
  installation_id TEXT PRIMARY KEY,
  credential_hash TEXT NOT NULL REFERENCES review_credentials(credential_hash) ON DELETE CASCADE,
  credential_revision INTEGER NOT NULL,
  public_key_spki TEXT NOT NULL,
  key_hash TEXT NOT NULL,
  renewal_hash TEXT NOT NULL,
  revoked INTEGER NOT NULL DEFAULT 0 CHECK(revoked IN (0, 1)),
  last_renewed_at_ms INTEGER NOT NULL
);
CREATE INDEX review_installations_retention ON review_installations(last_renewed_at_ms);
CREATE TABLE review_challenges (
  challenge_id TEXT PRIMARY KEY,
  nonce_hash TEXT NOT NULL,
  operation TEXT NOT NULL CHECK(operation IN ('activate', 'renew', 'exit')),
  key_hash TEXT NOT NULL,
  request_nonce TEXT NOT NULL,
  credential_hash TEXT NOT NULL REFERENCES review_credentials(credential_hash) ON DELETE CASCADE,
  credential_revision INTEGER NOT NULL,
  installation_id TEXT,
  expires_at_ms INTEGER NOT NULL
);
CREATE INDEX review_challenges_retention ON review_challenges(expires_at_ms);
