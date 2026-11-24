PRAGMA foreign_keys = ON;

CREATE TABLE users (
  user_id        INTEGER PRIMARY KEY,
  key_hash       TEXT    NOT NULL UNIQUE,
  verified       INTEGER NOT NULL DEFAULT 0,
  claim_phrase   TEXT,
  claim_expires  INTEGER,
  created_at     INTEGER NOT NULL,
  last_seen_at   INTEGER NOT NULL
);

CREATE TABLE lists (
  id          TEXT    PRIMARY KEY,
  owner_id    INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  title       TEXT    NOT NULL,
  share_code  TEXT    NOT NULL UNIQUE,
  revision    INTEGER NOT NULL DEFAULT 1,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);
CREATE INDEX lists_owner ON lists(owner_id);

CREATE TABLE items (
  id          TEXT    PRIMARY KEY,
  list_id     TEXT    NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  text        TEXT    NOT NULL,
  done        INTEGER NOT NULL DEFAULT 0,
  position    REAL    NOT NULL,
  version     INTEGER NOT NULL DEFAULT 1,
  created_by  INTEGER NOT NULL,
  updated_by  INTEGER NOT NULL,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);
CREATE INDEX items_list ON items(list_id, position);

CREATE TABLE members (
  list_id   TEXT    NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  user_id   INTEGER NOT NULL,
  role      TEXT    NOT NULL CHECK (role IN ('editor', 'viewer')),
  added_at  INTEGER NOT NULL,
  PRIMARY KEY (list_id, user_id)
);
CREATE INDEX members_user ON members(user_id);

CREATE TABLE assignments (
  list_id      TEXT    NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  user_id      INTEGER NOT NULL,
  assigned_at  INTEGER NOT NULL,
  PRIMARY KEY (list_id, user_id)
);
CREATE INDEX assignments_user ON assignments(user_id);

CREATE TABLE visits (
  list_id    TEXT    NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  user_id    INTEGER NOT NULL,
  opened_at  INTEGER NOT NULL,
  PRIMARY KEY (list_id, user_id)
);
CREATE INDEX visits_user ON visits(user_id);
