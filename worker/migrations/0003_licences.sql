ALTER TABLE users ADD COLUMN roblox_refresh TEXT;
ALTER TABLE users ADD COLUMN licence_checked_at INTEGER;

ALTER TABLE login_sessions ADD COLUMN roblox_refresh TEXT;
ALTER TABLE login_sessions ADD COLUMN error_code TEXT;
