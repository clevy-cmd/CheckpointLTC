CREATE TABLE login_sessions (
  code            TEXT    PRIMARY KEY,
  poll_hash       TEXT    NOT NULL,
  oauth_state     TEXT    NOT NULL UNIQUE,
  pkce_verifier   TEXT    NOT NULL,
  studio_user_id  INTEGER NOT NULL,
  user_id         INTEGER,
  error           TEXT,
  expires_at      INTEGER NOT NULL,
  created_at      INTEGER NOT NULL
);
CREATE INDEX login_sessions_expiry ON login_sessions(expires_at);

DELETE FROM users WHERE key_hash LIKE 'pending:%';
ALTER TABLE users DROP COLUMN claim_phrase;
ALTER TABLE users DROP COLUMN claim_expires;
