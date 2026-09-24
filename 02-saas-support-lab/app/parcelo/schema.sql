-- Parcelo: shipment tracking API for small online shops.

CREATE TABLE IF NOT EXISTS customers (
    id    text PRIMARY KEY,
    name  text NOT NULL,
    plan  text NOT NULL
);

CREATE TABLE IF NOT EXISTS api_keys (
    id          serial PRIMARY KEY,
    customer_id text NOT NULL REFERENCES customers(id),
    key_prefix  text NOT NULL,              -- first 12 chars, safe to show in logs and support tools
    key_hash    text NOT NULL UNIQUE,       -- sha256 of the full key; the key itself is never stored
    scope       text NOT NULL CHECK (scope IN ('read', 'write')),
    revoked     boolean NOT NULL DEFAULT false,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS shipments (
    id             bigserial PRIMARY KEY,
    customer_id    text NOT NULL REFERENCES customers(id),
    tracking_code  text,
    recipient_city text NOT NULL,
    weight_kg      numeric(8, 2) NOT NULL,
    status         text NOT NULL DEFAULT 'created',
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);

-- Serves the paginated list endpoint (WHERE customer_id = ? AND id > ? ORDER BY id).
CREATE INDEX IF NOT EXISTS shipments_customer_id_id ON shipments (customer_id, id);
-- Deliberate lab defect (ticket PS-1007 / ENG-2042): there is no index on
-- (customer_id, created_at), which the daily report filters on.

CREATE TABLE IF NOT EXISTS webhook_endpoints (
    customer_id text PRIMARY KEY REFERENCES customers(id),
    url         text NOT NULL,
    secret      text NOT NULL
);

CREATE TABLE IF NOT EXISTS events (
    id          text PRIMARY KEY,
    customer_id text NOT NULL REFERENCES customers(id),
    type        text NOT NULL,
    payload     jsonb NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS webhook_deliveries (
    id          bigserial PRIMARY KEY,
    event_id    text NOT NULL REFERENCES events(id),
    attempt     int NOT NULL,
    status_code int,
    duration_ms int NOT NULL,
    error       text,
    created_at  timestamptz NOT NULL DEFAULT now()
);
