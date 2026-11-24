CREATE TABLE sessions (
  id            TEXT    PRIMARY KEY,
  user_id       INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  key_hash      TEXT    NOT NULL UNIQUE,
  label         TEXT    NOT NULL,
  created_at    INTEGER NOT NULL,
  last_seen_at  INTEGER NOT NULL
);
CREATE INDEX sessions_user ON sessions(user_id, created_at);

INSERT INTO sessions (id, user_id, key_hash, label, created_at, last_seen_at)
SELECT lower(hex(randomblob(7))), user_id, key_hash, 'Roblox Studio', last_seen_at, last_seen_at
  FROM users
 WHERE key_hash NOT LIKE 'revoked:%';

CREATE TABLE bans (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     INTEGER NOT NULL,
  level       TEXT    NOT NULL CHECK (level IN ('upload', 'full', 'illegal')),
  reason      TEXT    NOT NULL,
  created_at  INTEGER NOT NULL,
  lifted_at   INTEGER
);
CREATE UNIQUE INDEX bans_active ON bans(user_id) WHERE lifted_at IS NULL;
