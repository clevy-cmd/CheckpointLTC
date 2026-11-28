ALTER TABLE game_keys ADD COLUMN revoked_at INTEGER;
ALTER TABLE game_keys ADD COLUMN revoked_reason TEXT;

CREATE TABLE game_report_attempts (
  game_key_id TEXT    NOT NULL,
  player_id   INTEGER NOT NULL,
  kind        TEXT    NOT NULL,
  created_at  INTEGER NOT NULL
);
CREATE INDEX game_report_attempts_player ON game_report_attempts(game_key_id, player_id, kind, created_at);
CREATE INDEX game_report_attempts_age ON game_report_attempts(created_at);
