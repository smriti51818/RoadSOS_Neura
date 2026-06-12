-- RoadSoS PostgreSQL Schema — Supabase compatible
-- Run in Supabase SQL Editor: paste this file and execute.
-- Required: PostGIS extension for spatial queries.

-- ── Extensions ─────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS postgis;

-- ── Helper: updated_at auto-update trigger ────────────────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ── 1. services — master service registry ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS services (
  id             BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  name           TEXT NOT NULL,
  category       TEXT NOT NULL CHECK (
                   category IN (
                     'hospital', 'police', 'ambulance', 'fire',
                     'towing', 'breakdown', 'puncture', 'helpline'
                   )
                 ),
  subcategory    TEXT,
  lat            REAL NOT NULL,
  lng            REAL NOT NULL,
  phone_primary  TEXT,
  phone_secondary TEXT,
  address        TEXT,
  country_code   TEXT NOT NULL DEFAULT 'IN',
  state_code     TEXT,
  is_24hr        BOOLEAN NOT NULL DEFAULT FALSE,
  trust_score    SMALLINT NOT NULL DEFAULT 1 CHECK (trust_score BETWEEN 1 AND 5),
  source         TEXT NOT NULL,
  verified_date  TEXT,
  is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_services_country_category
  ON services (country_code, category);
CREATE INDEX IF NOT EXISTS idx_services_lat_lng
  ON services (lat, lng);
CREATE INDEX IF NOT EXISTS idx_services_trust_score
  ON services (trust_score);

CREATE TRIGGER trg_services_updated_at
  BEFORE UPDATE ON services
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ── 2. emergency_numbers — per-country contact directory ──────────────────────
CREATE TABLE IF NOT EXISTS emergency_numbers (
  id           BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  country_code TEXT NOT NULL UNIQUE,
  country_name TEXT NOT NULL,
  police       TEXT,
  ambulance    TEXT,
  fire         TEXT,
  unified      TEXT NOT NULL DEFAULT '112',
  coast_guard  TEXT,
  disaster     TEXT,
  women        TEXT,
  last_verified TEXT
);

CREATE INDEX IF NOT EXISTS idx_emergency_numbers_country
  ON emergency_numbers (country_code);

-- ── 3. emergency_sessions — active and historical emergency events ─────────────
CREATE TABLE IF NOT EXISTS emergency_sessions (
  id               BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  session_id       TEXT NOT NULL UNIQUE,
  user_phone       TEXT,
  started_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  emergency_type   TEXT NOT NULL CHECK (
                     emergency_type IN ('accident', 'fire', 'medical', 'unsafe')
                   ),
  victim_type      TEXT NOT NULL CHECK (
                     victim_type IN (
                       'people_injured', 'vehicle_only', 'self', 'bystander'
                     )
                   ),
  lat              REAL NOT NULL,
  lng              REAL NOT NULL,
  country_code     TEXT NOT NULL DEFAULT 'IN',
  victim_count     INTEGER,
  victim_details   JSONB,          -- List<VictimDetail> serialised
  is_active        BOOLEAN NOT NULL DEFAULT TRUE,
  resolved_at      TIMESTAMPTZ,
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_emergency_sessions_active
  ON emergency_sessions (is_active, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_emergency_sessions_session_id
  ON emergency_sessions (session_id);

CREATE TRIGGER trg_emergency_sessions_updated_at
  BEFORE UPDATE ON emergency_sessions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ── 4. location_pings — emergency location history ────────────────────────────
CREATE TABLE IF NOT EXISTS location_pings (
  id           BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  session_id   TEXT NOT NULL REFERENCES emergency_sessions(session_id)
                 ON DELETE CASCADE,
  lat          REAL NOT NULL,
  lng          REAL NOT NULL,
  accuracy_m   REAL,
  pinged_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_to_police BOOLEAN NOT NULL DEFAULT FALSE,
  sms_sent     BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_location_pings_session
  ON location_pings (session_id, pinged_at DESC);

-- ── 5. user_reports — data quality feedback ───────────────────────────────────
CREATE TABLE IF NOT EXISTS user_reports (
  id           BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  service_id   BIGINT NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  report_type  TEXT NOT NULL CHECK (
                 report_type IN ('wrong_number', 'closed', 'moved', 'duplicate')
               ),
  reported_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved     BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_user_reports_service
  ON user_reports (service_id, resolved);

-- ── 6. offline_packs — offline data pack manifest ────────────────────────────
CREATE TABLE IF NOT EXISTS offline_packs (
  id             BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  pack_id        TEXT NOT NULL UNIQUE,
  country_code   TEXT NOT NULL,
  region_name    TEXT NOT NULL,
  record_count   INTEGER NOT NULL DEFAULT 0,
  file_size_kb   INTEGER NOT NULL DEFAULT 0,
  downloaded_at  TIMESTAMPTZ,
  last_refreshed TIMESTAMPTZ,
  version        TEXT NOT NULL DEFAULT '1.0'
);

-- ── 7. blackspots — MoRTH highway accident blackspot data ─────────────────────
-- Source: MoRTH 2016–2022 data (13,795 blackspots on National Highways)
-- Definition: 500m stretch with ≥ 5 serious accidents OR ≥ 10 deaths in 3 years
CREATE TABLE IF NOT EXISTS blackspots (
  id              BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  highway         TEXT NOT NULL,    -- e.g. NH-48, SH-1
  km_marker       TEXT,             -- e.g. "km 142"
  lat             REAL,
  lng             REAL,
  state_code      TEXT,
  district        TEXT,
  accidents_3yr   INTEGER,
  fatalities_3yr  INTEGER,
  severity        TEXT CHECK (severity IN ('high', 'medium', 'low')),
  source          TEXT NOT NULL DEFAULT 'morth_2022',
  last_updated    TEXT
);

CREATE INDEX IF NOT EXISTS idx_blackspots_highway
  ON blackspots (highway, km_marker);
CREATE INDEX IF NOT EXISTS idx_blackspots_state
  ON blackspots (state_code);
CREATE INDEX IF NOT EXISTS idx_blackspots_lat_lng
  ON blackspots (lat, lng);

-- ── Seed: India emergency numbers ─────────────────────────────────────────────
INSERT INTO emergency_numbers
  (country_code, country_name, police, ambulance, fire, unified, women)
VALUES
  ('IN', 'India', '100', '108', '101', '112', '1091')
ON CONFLICT (country_code) DO NOTHING;
