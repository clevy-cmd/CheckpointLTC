ALTER TABLE items ADD COLUMN assignees TEXT;
UPDATE items SET assignees = json_array(assignee_id) WHERE assignee_id IS NOT NULL;

CREATE TABLE item_assignees (
  item_id  TEXT    NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  list_id  TEXT    NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  user_id  INTEGER NOT NULL,
  PRIMARY KEY (item_id, user_id)
);
CREATE INDEX item_assignees_user ON item_assignees(user_id);
CREATE INDEX item_assignees_list ON item_assignees(list_id, user_id);

INSERT OR IGNORE INTO item_assignees (item_id, list_id, user_id)
SELECT id, list_id, assignee_id FROM items WHERE assignee_id IS NOT NULL;

CREATE TRIGGER item_assignees_insert AFTER INSERT ON items WHEN NEW.assignees IS NOT NULL
BEGIN
  INSERT OR IGNORE INTO item_assignees (item_id, list_id, user_id)
  SELECT NEW.id, NEW.list_id, value FROM json_each(NEW.assignees);
END;

CREATE TRIGGER item_assignees_update AFTER UPDATE OF assignees ON items
BEGIN
  DELETE FROM item_assignees WHERE item_id = NEW.id;
  INSERT OR IGNORE INTO item_assignees (item_id, list_id, user_id)
  SELECT NEW.id, NEW.list_id, value FROM json_each(COALESCE(NEW.assignees, '[]'));
END;

ALTER TABLE lists ADD COLUMN auto_assignees TEXT;
