CREATE TABLE sync_scope (
    device_id TEXT NOT NULL,
    domain TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL,
    PRIMARY KEY(device_id,domain),
    FOREIGN KEY(device_id) REFERENCES device(id)
);
CREATE TABLE sync_object (
    device_id TEXT NOT NULL,
    domain TEXT NOT NULL,
    revision INTEGER NOT NULL,
    content_sha256 TEXT NOT NULL,
    ciphertext TEXT NOT NULL,
    nonce TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    PRIMARY KEY(device_id,domain),
    FOREIGN KEY(device_id) REFERENCES device(id)
);
CREATE TABLE sync_write_result (
    device_id TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    request_hash TEXT NOT NULL,
    response_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY(device_id,idempotency_key)
);
