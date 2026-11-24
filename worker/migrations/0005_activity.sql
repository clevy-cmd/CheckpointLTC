CREATE TABLE activity (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  list_id     TEXT    NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  revision    INTEGER NOT NULL,
  actor_id    INTEGER NOT NULL,
  kind        TEXT    NOT NULL,
  item_id     TEXT,
  data        TEXT,
  created_at  INTEGER NOT NULL
);
CREATE INDEX activity_list ON activity(list_id, id);
