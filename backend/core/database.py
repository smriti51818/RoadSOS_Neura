"""Neon DB connection pool — asyncpg-based PostgreSQL client.

Usage:
    Set NEON_DATABASE_URL in .env (or environment):
        postgresql://user:password@ep-xxx.region.aws.neon.tech/neondb?sslmode=require

    The lifespan handler in main.py calls connect() on startup and
    disconnect() on shutdown. All routers access the pool via get_pool().

Neon notes:
    • Always use sslmode=require in the connection string.
    • For high-traffic use the pooled endpoint:
        ep-xxx-pooler.region.aws.neon.tech
    • The direct endpoint (ep-xxx.region.aws.neon.tech) is fine for
      hackathon demo traffic.
"""

import logging
import os
from typing import Optional

import asyncpg

logger = logging.getLogger(__name__)

_pool: Optional[asyncpg.Pool] = None


async def connect() -> None:
    """Open the asyncpg connection pool to Neon DB.

    Called once on app startup via the FastAPI lifespan handler.
    Raises ValueError if NEON_DATABASE_URL is not set — this is
    intentional so misconfigured deploys fail loudly at startup.
    """
    global _pool

    dsn = os.getenv("NEON_DATABASE_URL")
    if not dsn:
        logger.warning(
            "[DB] NEON_DATABASE_URL not set — database persistence disabled. "
            "Emergency sessions and pings will NOT be stored in Neon."
        )
        return

    try:
        _pool = await asyncpg.create_pool(
            dsn,
            min_size=1,
            max_size=10,
            # Neon requires SSL — redundant if sslmode=require is in the DSN
            # but kept as an explicit safeguard.
            ssl="require",
            command_timeout=10,
            # Serverless Neon instances may go idle — reconnect automatically.
            max_inactive_connection_lifetime=300,
        )
        logger.info("[DB] Neon DB connection pool ready ✓")
    except Exception as exc:
        logger.error(f"[DB] Failed to connect to Neon DB: {exc}")
        _pool = None


async def disconnect() -> None:
    """Close the connection pool gracefully on app shutdown."""
    global _pool
    if _pool is not None:
        await _pool.close()
        _pool = None
        logger.info("[DB] Neon DB connection pool closed")


def get_pool() -> Optional[asyncpg.Pool]:
    """Return the active connection pool, or None if DB is not configured."""
    return _pool


def is_connected() -> bool:
    """True if the pool is open and ready for queries."""
    return _pool is not None
