"""Database access: one short-lived connection per unit of work."""
from contextlib import contextmanager
from pathlib import Path

import psycopg
from psycopg.rows import dict_row

from . import config

SCHEMA = Path(__file__).with_name("schema.sql").read_text(encoding="utf-8")


@contextmanager
def connect():
    with psycopg.connect(config.DATABASE_URL, row_factory=dict_row) as conn:
        yield conn


def apply_schema() -> None:
    with connect() as conn:
        conn.execute(SCHEMA)
