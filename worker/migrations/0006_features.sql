ALTER TABLE lists ADD COLUMN item_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE lists ADD COLUMN done_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE lists ADD COLUMN archived_at INTEGER;
ALTER TABLE lists ADD COLUMN deleted_at INTEGER;
ALTER TABLE lists ADD COLUMN place_id INTEGER;

ALTER TABLE items ADD COLUMN priority INTEGER NOT NULL DEFAULT 0;
ALTER TABLE items ADD COLUMN due_at INTEGER;
ALTER TABLE items ADD COLUMN label TEXT;
ALTER TABLE items ADD COLUMN section TEXT;
ALTER TABLE items ADD COLUMN notes TEXT;
ALTER TABLE items ADD COLUMN assignee_id INTEGER;
ALTER TABLE items ADD COLUMN link TEXT;
ALTER TABLE items ADD COLUMN deleted_at INTEGER;
CREATE INDEX items_assignee ON items(assignee_id);

ALTER TABLE activity ADD COLUMN undone INTEGER NOT NULL DEFAULT 0;

UPDATE lists SET
  item_count = (SELECT COUNT(*) FROM items i WHERE i.list_id = lists.id),
  done_count = (SELECT COUNT(*) FROM items i WHERE i.list_id = lists.id AND i.done = 1);

CREATE TRIGGER items_count_insert AFTER INSERT ON items WHEN NEW.deleted_at IS NULL
BEGIN
  UPDATE lists SET item_count = item_count + 1, done_count = done_count + NEW.done WHERE id = NEW.list_id;
END;

CREATE TRIGGER items_count_delete AFTER DELETE ON items WHEN OLD.deleted_at IS NULL
BEGIN
  UPDATE lists SET item_count = item_count - 1, done_count = done_count - OLD.done WHERE id = OLD.list_id;
END;

CREATE TRIGGER items_count_update AFTER UPDATE OF done, deleted_at ON items
BEGIN
  UPDATE lists SET
    item_count = item_count + (NEW.deleted_at IS NULL) - (OLD.deleted_at IS NULL),
    done_count = done_count + (NEW.deleted_at IS NULL AND NEW.done = 1) - (OLD.deleted_at IS NULL AND OLD.done = 1)
  WHERE id = NEW.list_id;
END;

CREATE TABLE members_new (
  list_id   TEXT    NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  user_id   INTEGER NOT NULL,
  role      TEXT    NOT NULL CHECK (role IN ('admin', 'editor', 'viewer')),
  added_at  INTEGER NOT NULL,
  PRIMARY KEY (list_id, user_id)
);
INSERT INTO members_new (list_id, user_id, role, added_at) SELECT list_id, user_id, role, added_at FROM members;
DROP TABLE members;
ALTER TABLE members_new RENAME TO members;
CREATE INDEX members_user ON members(user_id);

CREATE TABLE comments (
  id          TEXT    PRIMARY KEY,
  item_id     TEXT    NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  list_id     TEXT    NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  author_id   INTEGER NOT NULL,
  body        TEXT    NOT NULL,
  mentions    TEXT,
  created_at  INTEGER NOT NULL
);
CREATE INDEX comments_item ON comments(item_id, created_at);

CREATE TABLE notifications (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     INTEGER NOT NULL,
  list_id     TEXT    NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  item_id     TEXT,
  actor_id    INTEGER NOT NULL,
  kind        TEXT    NOT NULL,
  data        TEXT,
  created_at  INTEGER NOT NULL,
  read_at     INTEGER
);
CREATE INDEX notifications_user ON notifications(user_id, id);

CREATE TABLE preferences (
  user_id     INTEGER PRIMARY KEY,
  data        TEXT    NOT NULL,
  updated_at  INTEGER NOT NULL
);

CREATE TABLE seen (
  list_id   TEXT    NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  user_id   INTEGER NOT NULL,
  revision  INTEGER NOT NULL,
  seen_at   INTEGER NOT NULL,
  PRIMARY KEY (list_id, user_id)
);

CREATE TABLE presence (
  list_id     TEXT    NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  user_id     INTEGER NOT NULL,
  item_id     TEXT,
  place_id    INTEGER,
  updated_at  INTEGER NOT NULL,
  PRIMARY KEY (list_id, user_id)
);

CREATE TABLE roblox_users (
  user_id       INTEGER PRIMARY KEY,
  name          TEXT    NOT NULL,
  display_name  TEXT    NOT NULL,
  fetched_at    INTEGER NOT NULL
);
CREATE INDEX roblox_users_name ON roblox_users(name COLLATE NOCASE);

CREATE TABLE submissions (
  id            TEXT    PRIMARY KEY,
  user_id       INTEGER NOT NULL,
  kind          TEXT    NOT NULL CHECK (kind IN ('bug', 'feedback')),
  title         TEXT    NOT NULL,
  body          TEXT    NOT NULL,
  extra         TEXT,
  attachment_id TEXT,
  thread_id     TEXT,
  status        TEXT    NOT NULL,
  created_at    INTEGER NOT NULL
);
CREATE INDEX submissions_user ON submissions(user_id, kind, created_at);

CREATE TABLE uploads (
  id          TEXT    PRIMARY KEY,
  user_id     INTEGER NOT NULL,
  name        TEXT    NOT NULL,
  extension   TEXT    NOT NULL,
  size        INTEGER NOT NULL,
  parts       INTEGER NOT NULL,
  received    INTEGER NOT NULL DEFAULT 0,
  status      TEXT    NOT NULL,
  verdict     TEXT,
  scores      TEXT,
  review_hash TEXT,
  keep        INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER
);
CREATE INDEX uploads_user ON uploads(user_id, created_at);
CREATE INDEX uploads_expiry ON uploads(expires_at);

CREATE TABLE strikes (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     INTEGER NOT NULL,
  upload_id   TEXT,
  level       TEXT    NOT NULL,
  reason      TEXT    NOT NULL,
  created_at  INTEGER NOT NULL
);
CREATE INDEX strikes_user ON strikes(user_id);

CREATE TABLE game_keys (
  id          TEXT    PRIMARY KEY,
  list_id     TEXT    NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  owner_id    INTEGER NOT NULL,
  key_hash    TEXT    NOT NULL UNIQUE,
  label       TEXT    NOT NULL,
  created_at  INTEGER NOT NULL
);
CREATE INDEX game_keys_list ON game_keys(list_id);

CREATE TABLE game_reports (
  id          TEXT    PRIMARY KEY,
  list_id     TEXT    NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  game_key_id TEXT    NOT NULL,
  place_id    INTEGER,
  player_id   INTEGER NOT NULL,
  player_name TEXT    NOT NULL,
  kind        TEXT    NOT NULL CHECK (kind IN ('bug', 'feedback')),
  text        TEXT    NOT NULL,
  status      TEXT    NOT NULL DEFAULT 'new',
  created_at  INTEGER NOT NULL
);
CREATE INDEX game_reports_list ON game_reports(list_id, status, created_at);
CREATE INDEX game_reports_player ON game_reports(game_key_id, player_id, created_at);

CREATE TABLE export_tokens (
  token_hash  TEXT    PRIMARY KEY,
  list_id     TEXT    NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  user_id     INTEGER NOT NULL,
  format      TEXT    NOT NULL,
  expires_at  INTEGER NOT NULL
);
