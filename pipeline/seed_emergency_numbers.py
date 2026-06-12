#!/usr/bin/env python3
"""Seed emergency numbers from JSON into Supabase.

Usage:
  python seed_emergency_numbers.py

Requires environment variables:
  SUPABASE_URL  — e.g. https://your-project.supabase.co
  SUPABASE_KEY  — service role key (not anon key — needs write access)

Install:
  pip install supabase python-dotenv
"""

import json
import os
import sys
from pathlib import Path

from dotenv import load_dotenv
from supabase import create_client, Client

# Load .env from backend directory
env_path = Path(__file__).parent.parent / "backend" / ".env"
load_dotenv(dotenv_path=env_path)

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

DATA_PATH = (
    Path(__file__).parent.parent / "backend" / "data" / "emergency_numbers.json"
)


def main() -> None:
    if not SUPABASE_URL or not SUPABASE_KEY:
        print(
            "ERROR: SUPABASE_URL and SUPABASE_KEY must be set in backend/.env",
            file=sys.stderr,
        )
        sys.exit(1)

    if not DATA_PATH.exists():
        print(f"ERROR: {DATA_PATH} not found", file=sys.stderr)
        sys.exit(1)

    with open(DATA_PATH, encoding="utf-8") as f:
        records = json.load(f)

    if not isinstance(records, list):
        print("ERROR: emergency_numbers.json must be a JSON array", file=sys.stderr)
        sys.exit(1)

    print(f"[Seed] Connecting to Supabase at {SUPABASE_URL}...")
    client: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

    inserted = 0
    for record in records:
        country_code = record.get("country_code", "")
        if not country_code:
            print(f"  SKIP: record missing country_code: {record}")
            continue

        # Upsert on country_code — update if exists, insert if not
        result = (
            client.table("emergency_numbers")
            .upsert(record, on_conflict="country_code")
            .execute()
        )
        inserted += 1
        print(f"  OK: {country_code} — {record.get('country_name', '')}")

    print(f"\n[Seed] Seeded {inserted} emergency number records into Supabase.")


if __name__ == "__main__":
    main()
