"""All tunables in one place. Only the values tests or compose override read the environment."""
import os

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://parcelo:parcelo@db:5432/parcelo")
SHARED_DIR = "/shared"

# Per API key: at most RATE_LIMIT_REQUESTS in any RATE_LIMIT_WINDOW_S seconds.
RATE_LIMIT_REQUESTS = 10
RATE_LIMIT_WINDOW_S = 10

# Webhooks are delivered at least once: a slow or failing endpoint is retried.
WEBHOOK_TIMEOUT_S = 3
WEBHOOK_MAX_ATTEMPTS = 3
WEBHOOK_BACKOFF_S = float(os.environ.get("WEBHOOK_BACKOFF_S", "1"))

PAGE_SIZE_DEFAULT = 50
PAGE_SIZE_MAX = 100

# The daily report is cancelled after this long rather than holding a connection.
REPORT_TIMEOUT_MS = 150

# Rows generated for the large customer at first boot (0 disables, used by tests).
BULK_SHIPMENTS = int(os.environ.get("BULK_SHIPMENTS", "8000000"))
