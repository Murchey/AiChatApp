CREATE TABLE user_account (
    id TEXT PRIMARY KEY,
    username TEXT NOT NULL UNIQUE COLLATE NOCASE,
    password_hash TEXT NOT NULL,
    created_at TEXT NOT NULL
);
ALTER TABLE device ADD COLUMN account_id TEXT REFERENCES user_account(id);
CREATE INDEX idx_device_account ON device(account_id);
