<div align="center">

# 🛡️ RoadSoS — Neura

### Road Safety Emergency Response System
**Help in under 5 seconds · Works fully offline · Covers 190+ countries**

*Built for IIT Madras Centre of Excellence in Road Safety (CoERS) Hackathon 2026*
*Problem Statement 3 — Technology-Driven Emergency Response*

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.111-009688?logo=fastapi)](https://fastapi.tiangolo.com)
[![Next.js](https://img.shields.io/badge/Next.js-16-black?logo=nextdotjs)](https://nextjs.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-Neon-4169E1?logo=postgresql)](https://neon.tech)
[![License](https://img.shields.io/badge/License-Hackathon-orange)](./LICENSE)

</div>

---

## 📋 Table of Contents

- [The Problem](#-the-problem)
- [The Solution](#-the-solution)
- [App Screenshots](#-app-screenshots)
- [Architecture](#-architecture)
- [Tech Stack](#-tech-stack)
- [Project Structure](#-project-structure)
- [Data Sources & Trust Scoring](#-data-sources--trust-scoring)
- [Database Schema](#-database-schema)
- [API Reference](#-api-reference)
- [Quick Start](#-quick-start)
- [Environment Variables](#-environment-variables)
- [Feature Modules](#-feature-modules)
- [Offline Architecture](#-offline-architecture)
- [AI Safety System](#-ai-safety-system)
- [Data Pipeline](#-data-pipeline)

---

## 🚨 The Problem

> **India loses one life to road accidents every 3.5 minutes.**

| Metric | Figure | Source |
|--------|--------|--------|
| Road accident deaths (2022) | **1,68,491** | MoRTH Annual Report 2022 |
| Total road accidents (2022) | 4,61,312 | MoRTH Annual Report 2022 |
| Share of global road deaths | ~11% | WHO Global Status Report 2023 |
| Average urban EMS response time | 20–45 min | NITI Aayog Report 2023 |
| Average rural EMS response time | 60+ min | National Health Mission Data |
| Lives saveable in the "Golden Hour" | Up to 60% | AIIMS Trauma Research |

The system breaks down at three points:
1. **Discovery Delay** — bystanders don't know which number to call (100? 108? 112?)
2. **Communication Gap** — no structured GPS location or victim data reaches dispatchers
3. **No Accountability** — after calling, there's no way to know if help is actually coming

---

## 💡 The Solution

RoadSoS gives anyone at a road accident **verified, geo-ranked emergency contacts in under 5 seconds** — with one tap to call — even with **zero internet connectivity**, anywhere in the world.

```
Open app → Tap emergency type → Triage complete → Contacts alerted, GPS shared, services surfaced
                                Under 30 seconds from app open to first action
```

**Core capabilities:**
- 🆘 **One-Tap Emergency Dispatch** — 4 emergency categories, GPS auto-shared, SMS alerts fired
- 🏥 **Geo-Adaptive Service Discovery** — Verified hospitals, police, ambulance ranked by distance + trust score
- 🤖 **AI First Aid** — Gemini Flash online, Indian Red Cross decision trees offline
- 📴 **Fully Offline-First** — Emergency numbers for 190+ countries, services cached in SQLite
- 🗺️ **Journey Mode** — Real-time blackspot detection from MoRTH accident data
- 👩 **Women Safety Mode** — Silent SOS, trusted circle, fake call deterrent
- 📊 **CAD Web Dashboard** — Dispatcher command centre with live incident queue and PDF reporting

---

## 📱 App Screenshots

> **Add screenshots here** — place images in a `/docs/screenshots/` folder and update paths below.

| Home Screen | Triage Screen | Results Screen |
|:-----------:|:-------------:|:--------------:|
| `docs/screenshots/home.png` | `docs/screenshots/triage.png` | `docs/screenshots/results.png` |

| Journey Mode | AI Assist | Safety Screen |
|:------------:|:---------:|:-------------:|
| `docs/screenshots/journey.png` | `docs/screenshots/ai.png` | `docs/screenshots/safety.png` |

| Incident Status | Web Dashboard | CAD Report |
|:---------------:|:-------------:|:----------:|
| `docs/screenshots/incident_status.png` | `docs/screenshots/dashboard.png` | `docs/screenshots/cad_report.png` |

---

## 🏗️ Architecture

### System Overview

```mermaid
graph TB
    subgraph Mobile["📱 Flutter Mobile App"]
        UI[UI Screens<br/>GoRouter + Riverpod]
        LS[LocationService<br/>GPS + Geocoding]
        ES[EmergencyService<br/>Session lifecycle]
        AS[AIService<br/>Gemini + Decision Trees]
        OS[OfflineService<br/>Cache + Sync]
        SMS[SMSService<br/>url_launcher]
        DB_LOCAL[(Drift SQLite<br/>Offline-first)]
    end

    subgraph Backend["⚙️ FastAPI Backend"]
        API[FastAPI<br/>REST API]
        SF[ServiceFetcher<br/>Geo-adaptive]
        TS[TrustScorer<br/>1–5 tiers]
        DD[Deduplicator]
        RR[ResultRanker<br/>Distance + Trust]
        LR[LocationResolver<br/>Nominatim]
    end

    subgraph Adapters["🔌 Data Adapters"]
        OSM[OSMAdapter<br/>Overpass QL]
        MPLS[MapplsAdapter<br/>India]
        NHS[NHSCQCAdapter<br/>UK]
        HDX[HDXAdapter<br/>Africa / UN]
        HS[HealthsitesAdapter<br/>Global]
    end

    subgraph Cloud["☁️ Cloud"]
        NEON[(Neon PostgreSQL<br/>PostGIS)]
        GEO[Geoapify<br/>Places + Routing]
        GPLACES[Google Places API<br/>Vehicle services]
        GEMINI[Gemini Flash 1.5<br/>AI guidance]
    end

    subgraph Dashboard["🖥️ Web Dashboard<br/>Next.js CAD"]
        CAD[Incident Queue<br/>Priority P1/P2/P3]
        MAP[Leaflet Map]
        DISP[Dispatcher Panel<br/>Status + Notes]
        PDF[PDF Export<br/>jsPDF]
    end

    UI --> ES --> API
    UI --> OS --> DB_LOCAL
    UI --> AS --> GEMINI
    ES --> SMS
    ES --> LS
    API --> SF --> Adapters
    SF --> TS --> DD --> RR
    API --> NEON
    Dashboard --> NEON
    Adapters --> GEO
    Adapters --> GPLACES
    LR --> OSM
```

### Emergency Session Data Flow

```mermaid
sequenceDiagram
    participant U as 👤 User
    participant App as 📱 Flutter App
    participant SQLite as 🗄️ SQLite
    participant API as ⚙️ FastAPI
    participant DB as 🐘 Neon DB
    participant AI as 🤖 Gemini

    U->>App: Tap Emergency Category
    App->>SQLite: Create local session
    App->>U: SMS alert to contacts (url_launcher)
    App->>API: POST /api/emergency/start
    API-->>DB: INSERT emergency_sessions (async, non-blocking)
    API-->>App: { session_id, status: "active" }
    App->>U: Navigate → Triage Screen

    U->>App: Complete victim triage
    App->>API: GET /api/services/nearby?lat=&lng=
    API->>API: ServiceFetcher.fetch() — parallel adapters
    API-->>App: Ranked verified services

    App->>AI: POST first-aid request
    AI-->>App: Structured guidance (IMMEDIATE → STEPS → CALL)

    loop Every 10 seconds
        App->>SQLite: INSERT location_ping (local)
        App->>API: POST /api/emergency/ping (async)
        API-->>DB: INSERT location_pings (non-blocking)
    end

    U->>App: Tap "Emergency Resolved"
    App->>SQLite: Mark session resolved
    App->>API: POST /api/emergency/resolve
    API-->>DB: UPDATE emergency_sessions SET is_active=FALSE
```

### Offline Resilience Pattern

```mermaid
flowchart LR
    REQ[Incoming Request] --> CHK{Online?}
    CHK -->|Yes| API[FastAPI Backend]
    CHK -->|No| CACHE[SQLite Cache]
    API -->|Success| SAVE[Cache to SQLite]
    API -->|Fail| CACHE
    SAVE --> RESP[Return Data]
    CACHE --> RESP

    subgraph Sync["🔄 Background Sync (when online restored)"]
        QUEUE[SQLite Queue] --> UPLOAD[Upload to Neon DB]
    end
```

### Trust Scoring System

```mermaid
graph LR
    subgraph T5["⭐⭐⭐⭐⭐ Score 5 — Government Official"]
        A[data.gov.in]
        B[NHA / NHP.gov.in]
        C[NHS CQC API]
        D[MoRTH Data]
    end
    subgraph T4["⭐⭐⭐⭐ Score 4 — Government-Backed"]
        E[Mappls / MapMyIndia]
        F[Healthsites.io]
    end
    subgraph T3["⭐⭐⭐ Score 3 — Community Verified"]
        G[OpenStreetMap]
    end
    subgraph T2["⭐⭐ Score 2 — Developing-Nation Fallback"]
        H[HDX / UN Data]
    end
    subgraph T1["⭐ Score 1 — Never in Emergency Mode"]
        I[Crowdsourced / Unknown]
    end

    T5 & T4 & T3 -->|Emergency Mode ≥3| SHOW[Shown to User]
    T2 & T1 -->|Filtered Out| HIDE[Hidden in Emergency]
    T2 -->|Non-Emergency ≥2| SHOW2[Shown in Browse Mode]
```

---

## 🛠️ Tech Stack

### Mobile (Flutter)

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Framework | **Flutter 3.x + Dart** | Single codebase for Android & iOS |
| State Management | **Riverpod 2.x** | Compile-time safe, context-free providers |
| Local Database | **Drift (SQLite)** | Typed, offline-first data layer |
| Navigation | **GoRouter 13** | Declarative routing + deep links |
| Maps | **flutter_map + OpenStreetMap** | Free, offline-capable base maps |
| HTTP Client | **Dio 5 + http** | Interceptor chain + direct API calls |
| Background | **flutter_background_service** | Location pings when app backgrounded |
| Permissions | **permission_handler** | Location, phone, SMS |
| Voice | **speech_to_text** | Voice-to-text for AI and evidence input |

### Backend (Python)

| Layer | Technology | Purpose |
|-------|-----------|---------|
| API Framework | **FastAPI 0.111** | Async REST API with auto OpenAPI docs |
| Database Client | **asyncpg** | Native async PostgreSQL driver |
| HTTP Client | **aiohttp + httpx** | Async adapter calls with timeouts |
| Geospatial | **Shapely + GeoJSON** | Coordinate processing and geofencing |
| Server | **Uvicorn** | ASGI production server |
| Validation | **Pydantic v2** | Request/response schema validation |

### Web Dashboard (Next.js)

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Framework | **Next.js 16 + React 19** | Full-stack TypeScript app |
| Database | **@neondatabase/serverless** | Direct Neon DB connection from Edge |
| Maps | **Leaflet + react-leaflet** | Interactive incident map |
| PDF Export | **jsPDF** | Official CAD incident reports |
| Icons | **lucide-react** | Consistent icon system |
| Styling | **Tailwind CSS 4** | Utility-first design system |

### Cloud & External APIs

| Service | Provider | Usage |
|---------|----------|-------|
| Database | **Neon PostgreSQL + PostGIS** | Emergency sessions, services, blackspots |
| Maps (India) | **Mappls (MapMyIndia)** | India-specific POI search |
| Maps (Global) | **Geoapify** | Places, geocoding, routing |
| Vehicle Services | **Google Places API (New)** | Towing, breakdown, tyre repair |
| AI Guidance | **Gemini Flash 1.5** | Online first-aid instructions |
| UK Services | **NHS CQC API** | UK hospital data |
| Africa Data | **HDX (UN)** | Health facilities in developing nations |

---

## 📁 Project Structure

```
RoadSOS_Neura/
│
├── 📱 mobile/                      # Flutter mobile application
│   ├── lib/
│   │   ├── main.dart               # Entry point, error handling, permissions
│   │   ├── app.dart                # MaterialApp + Riverpod shell
│   │   ├── core/
│   │   │   ├── router.dart         # GoRouter route definitions
│   │   │   ├── theme.dart          # Design tokens, colors, typography
│   │   │   ├── constants.dart      # App-wide constants
│   │   │   ├── api_keys.dart       # Dev fallback keys (gitignored)
│   │   │   └── interceptors/       # Dio offline interceptor
│   │   ├── data/
│   │   │   ├── models/             # ServiceModel, IncidentRecord, etc.
│   │   │   ├── local/              # Drift DB schema + DAOs
│   │   │   ├── remote/             # API client
│   │   │   ├── providers/          # Riverpod data providers
│   │   │   └── services/           # Business logic services
│   │   ├── services/
│   │   │   ├── ai_service.dart     # Gemini + offline decision tree
│   │   │   ├── emergency_service.dart  # Session lifecycle
│   │   │   ├── location_service.dart   # GPS + reverse geocoding
│   │   │   ├── offline_service.dart    # Cache management + sync
│   │   │   ├── places_service.dart     # Geoapify + Google Places
│   │   │   ├── sms_service.dart        # SMS alerts via url_launcher
│   │   │   ├── connectivity_service.dart
│   │   │   └── osm_service.dart        # Direct OSM queries
│   │   ├── features/
│   │   │   ├── loading/            # Splash + initialization screen
│   │   │   ├── onboarding/         # 5-step onboarding flow
│   │   │   ├── home/               # Main screen + emergency grid
│   │   │   ├── triage/             # Emergency type + victim selection
│   │   │   ├── victims/            # Per-victim detail capture
│   │   │   ├── results/            # Service results + AI card + status
│   │   │   ├── journey/            # Journey mode + blackspot detection
│   │   │   ├── ai_assist/          # Chat interface with Gemini
│   │   │   ├── safety/             # Women safety mode + trusted circle
│   │   │   ├── non_emergency/      # Browse towing, breakdown, etc.
│   │   │   └── profile/            # User profile + contacts
│   │   └── widgets/                # Shared reusable widgets
│   ├── assets/
│   │   └── data/
│   │       ├── country_config.json         # Per-country adapter config
│   │       ├── emergency_numbers.json      # 190+ country numbers
│   │       ├── decision_trees.json         # Offline AI (Indian Red Cross)
│   │       ├── country_boundaries.geojson  # Boundary detection
│   │       └── seed_services.json          # Bootstrapped service data
│   ├── scripts/                    # Development utility scripts
│   │   ├── db_init.dart            # One-time Neon DB table creation
│   │   ├── db_migrate.dart         # Schema migration v1→v2
│   │   └── db_migrate2.dart        # Schema migration (incident_updates)
│   ├── pubspec.yaml
│   └── Makefile                    # make run / make build shortcuts
│
├── ⚙️ backend/                     # FastAPI Python backend
│   ├── main.py                     # App entry point, CORS, lifespan
│   ├── core/
│   │   ├── database.py             # asyncpg pool management
│   │   ├── service_fetcher.py      # 🔑 Core geo-adaptive algorithm
│   │   ├── location_resolver.py    # Country detection via Nominatim
│   │   ├── deduplicator.py         # Merge results across adapters
│   │   ├── result_ranker.py        # Distance + trust ranking
│   │   └── trust_scorer.py         # 5-tier trust scoring
│   ├── adapters/
│   │   ├── base_adapter.py         # Abstract adapter interface
│   │   ├── osm_adapter.py          # OpenStreetMap Overpass QL
│   │   ├── mappls_adapter.py       # MapMyIndia (India)
│   │   ├── nhs_cqc_adapter.py      # NHS CQC API (UK)
│   │   ├── hdx_adapter.py          # HDX/UN (Africa)
│   │   └── healthsites_adapter.py  # Healthsites.io (global)
│   ├── routers/
│   │   ├── emergency.py            # /api/emergency/* endpoints
│   │   ├── services.py             # /api/services/* endpoints
│   │   └── offline.py              # /api/offline/* endpoints
│   ├── schemas/
│   │   ├── emergency_schemas.py    # Pydantic request/response models
│   │   └── service_schemas.py      # Service data models
│   ├── data/
│   │   ├── country_config.json     # (same as mobile asset, server copy)
│   │   ├── emergency_numbers.json  # 190+ country numbers
│   │   └── decision_trees.json     # Offline AI decision trees
│   ├── tests/                      # pytest test suite
│   ├── requirements.txt
│   └── .env.example
│
├── 🖥️ web_dashboard/               # Next.js CAD dispatch dashboard
│   └── src/
│       ├── app/
│       │   ├── page.tsx            # 🔑 Full CAD dashboard UI
│       │   ├── layout.tsx          # Root layout
│       │   └── api/
│       │       └── incidents/      # REST API routes (Neon DB)
│       ├── components/
│       │   └── Map.tsx             # Leaflet map component
│       └── types/
│           └── index.ts            # TypeScript types
│
├── 🗄️ database/
│   └── schema.sql                  # PostgreSQL schema (7 tables + indexes)
│
└── 🔧 pipeline/
    ├── seed_emergency_numbers.py   # Seeds 190+ country emergency numbers
    └── ingest_osm.py               # Downloads city POI data from OSM
```

---

## 📊 Data Sources & Trust Scoring

| Source | Data | Trust Score | Coverage |
|--------|------|:-----------:|----------|
| data.gov.in / NHA | India hospital & health centre directory | ⭐⭐⭐⭐⭐ **5** | India |
| NHS CQC API | UK hospitals (daily updated) | ⭐⭐⭐⭐⭐ **5** | United Kingdom |
| MoRTH | Highway accident blackspot data | ⭐⭐⭐⭐⭐ **5** | India |
| Mappls (MapMyIndia) | India nearby services + POI | ⭐⭐⭐⭐ **4** | India |
| Healthsites.io | Verified health facilities | ⭐⭐⭐⭐ **4** | Global |
| OSM / Overpass QL | Community-verified POI | ⭐⭐⭐ **3** | Global (fallback) |
| HDX (UN) | Africa health facility data | ⭐⭐ **2** | Africa |
| emergencynumberapi.com | 190+ country emergency numbers | N/A | 190+ countries |

> **Emergency Mode Rule:** Only services with trust score ≥ 3 are shown when a life may depend on the number.

---

## 🗄️ Database Schema

```mermaid
erDiagram
    services {
        bigint id PK
        text name
        text category
        real lat
        real lng
        text phone_primary
        text country_code
        smallint trust_score
        text source
        boolean is_24hr
        boolean is_active
    }

    emergency_numbers {
        bigint id PK
        text country_code UK
        text country_name
        text police
        text ambulance
        text fire
        text unified
        text women
    }

    emergency_sessions {
        bigint id PK
        text session_id UK
        text emergency_type
        text victim_type
        real lat
        real lng
        text country_code
        integer victim_count
        jsonb victim_details
        boolean is_active
        timestamptz started_at
        timestamptz resolved_at
    }

    location_pings {
        bigint id PK
        text session_id FK
        real lat
        real lng
        real accuracy_m
        timestamptz pinged_at
    }

    user_reports {
        bigint id PK
        bigint service_id FK
        text report_type
        boolean resolved
    }

    offline_packs {
        bigint id PK
        text pack_id UK
        text country_code
        text region_name
        integer record_count
        text version
    }

    blackspots {
        bigint id PK
        text highway
        text km_marker
        real lat
        real lng
        integer accidents_3yr
        integer fatalities_3yr
        text severity
        text source
    }

    emergency_sessions ||--o{ location_pings : "has"
    services ||--o{ user_reports : "receives"
```

---

## 🔌 API Reference

### Base URL
```
http://localhost:8000
```

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Liveness probe |
| `POST` | `/api/emergency/start` | Open a new emergency session |
| `POST` | `/api/emergency/ping` | Send location update for active session |
| `POST` | `/api/emergency/resolve` | Close/resolve an emergency session |
| `GET` | `/api/services/nearby` | Get ranked nearby services by GPS |
| `GET` | `/api/services/emergency-numbers/{country_code}` | Country emergency numbers |
| `GET` | `/api/offline/decision-trees` | Bundled offline AI decision trees |
| `GET` | `/api/offline/country-config` | Per-country data source config |
| `GET` | `/docs` | Interactive Swagger UI |

**Example — Start Emergency:**
```bash
curl -X POST http://localhost:8000/api/emergency/start \
  -H "Content-Type: application/json" \
  -d '{
    "emergency_type": "accident",
    "victim_type": "people_injured",
    "lat": 19.076,
    "lng": 72.877,
    "victim_count": 2
  }'
```

**Example — Nearby Services:**
```bash
curl "http://localhost:8000/api/services/nearby?lat=19.076&lng=72.877&emergency_mode=true"
```

---

## 🚀 Quick Start

### Prerequisites

| Tool | Version |
|------|---------|
| Python | 3.11+ |
| Flutter SDK | 3.3+ |
| Node.js | 20+ |
| Dart SDK | 3.3+ |

### 1. Database Setup (Supabase or Neon)

```bash
# Option A: Supabase
# 1. Go to supabase.com → Create project → SQL Editor
# 2. Paste contents of database/schema.sql → Run

# Option B: Neon
# 1. Go to neon.tech → Create project
# 2. Run schema.sql in the SQL editor
```

Tables created: `services`, `emergency_numbers`, `emergency_sessions`,
`location_pings`, `user_reports`, `offline_packs`, `blackspots`

### 2. Backend

```bash
cd backend
python -m venv venv
source venv/bin/activate       # Windows: venv\Scripts\activate

pip install -r requirements.txt

cp .env.example .env           # Fill in your values (see Environment Variables)

uvicorn main:app --reload --port 8000
# → API running at http://localhost:8000
# → Swagger docs at http://localhost:8000/docs
```

### 3. Data Pipeline (Seed real data)

```bash
cd pipeline

# Seed emergency numbers for 190+ countries
python seed_emergency_numbers.py

# Ingest POI data from OpenStreetMap for a city
python ingest_osm.py --city Mumbai --lat 19.076 --lng 72.877 --radius 25
python ingest_osm.py --city Delhi  --lat 28.679 --lng 77.069 --radius 30
```

### 4. Flutter Mobile App

```bash
cd mobile

flutter pub get
dart run build_runner build --delete-conflicting-outputs

# Copy env example and fill in keys
cp .env.local.example .env

# Run on Android emulator (backend reachable at 10.0.2.2)
flutter run --dart-define-from-file=.env

# Run on physical device (replace with your machine's local IP)
flutter run --dart-define-from-file=.env \
            --dart-define=API_BASE_URL=http://192.168.1.x:8000

# Makefile shortcuts
make run        # physical device
make run-emu    # emulator
make build      # release APK
```

### 5. Web Dashboard

```bash
cd web_dashboard
npm install
npm run dev
# → Dashboard at http://localhost:3000
```

### Verify Everything Works

```bash
# Backend health
curl http://localhost:8000/health
# → {"status":"ok","version":"1.0.0","timestamp":"..."}

# India emergency numbers
curl http://localhost:8000/api/services/emergency-numbers/IN
# → {"country_code":"IN","police":"100","ambulance":"108","fire":"101","unified":"112"}

# Offline decision trees
curl http://localhost:8000/api/offline/decision-trees
# → {"breakdown":{...},"accident_injury":{...},...}
```

---

## 🔐 Environment Variables

### `backend/.env`

```env
# Neon DB connection string
NEON_DATABASE_URL=postgresql://user:pass@ep-xxx.region.aws.neon.tech/neondb?sslmode=require

# India map services (MapMyIndia)
MAPPLS_API_KEY=your-mappls-api-key

# AI guidance
GEMINI_API_KEY=your-gemini-api-key

# Optional: UK hospital data (free at developer.cqc.org.uk)
CQC_API_KEY=your-cqc-api-key

# Optional: global health facilities
HEALTHSITES_API_KEY=your-healthsites-api-key

ENVIRONMENT=development
SECRET_KEY=change-this-in-production
```

### `mobile/.env` (via `--dart-define-from-file`)

```env
# POI search, geocoding, routing
GEOAPIFY_API_KEY=your-geoapify-api-key

# Vehicle services (towing, breakdown, tyre repair)
GOOGLE_PLACES_API_KEY=your-google-places-api-key

# Backend URL (10.0.2.2 = emulator localhost)
API_BASE_URL=http://10.0.2.2:8000

# Optional cloud DB for real-time incident tracking
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-supabase-anon-key

# India maps
MAPPLS_API_KEY=your-mappls-api-key

# AI
GEMINI_API_KEY=your-gemini-api-key
```

### `web_dashboard/.env.local`

```env
DATABASE_URL=postgresql://user:pass@ep-xxx.region.aws.neon.tech/neondb?sslmode=require
```

---

## 📱 Feature Modules

### Module Map

```mermaid
flowchart TD
    M1[Module 1\nScaffold + DB + Config] --> M2
    M2[Module 2\nGeo-Adaptive Service Fetcher] --> M3
    M3[Module 3\nFlutter Shell + Home Screen] --> M4
    M4[Module 4\nEmergency Triage + Results + One-Tap Call] --> M5
    M5[Module 5\nOffline Architecture\nDrift + Cache] --> M6
    M6[Module 6\nData Pipeline + Seed Real Data] --> M7
    M7[Module 7\nJourney Mode + Blackspot Warnings] --> M8
    M8[Module 8\nAI Assist\nGemini + Offline Tree] --> M9
    M9[Module 9\nGroup Victims Flow] --> M10
    M10[Module 10\nWomen / Solo Traveller Safety] --> M11
    M11[Module 11\nNon-Emergency + Milestone] --> M12
    M12[Module 12\nUI Polish + APK Build] --> M13
    M13[Module 13\nCAD Dashboard + Submission]

    style M1 fill:#16A34A,color:#fff
    style M2 fill:#16A34A,color:#fff
    style M3 fill:#16A34A,color:#fff
    style M4 fill:#16A34A,color:#fff
    style M5 fill:#16A34A,color:#fff
    style M6 fill:#16A34A,color:#fff
    style M7 fill:#16A34A,color:#fff
    style M8 fill:#16A34A,color:#fff
    style M9 fill:#16A34A,color:#fff
    style M10 fill:#16A34A,color:#fff
    style M11 fill:#16A34A,color:#fff
    style M12 fill:#16A34A,color:#fff
    style M13 fill:#16A34A,color:#fff
```

### Screen Inventory

| Screen | Route | Description |
|--------|-------|-------------|
| Loading / Splash | `/` | DB init, permission warmup, safety tip display |
| Onboarding | `/onboarding` | 5-step: Welcome → Profile → Contacts → Location → Ready |
| Home | `/home` | Emergency grid, mode toggle, quick-dial strip |
| Triage | `/triage` | Emergency type → victim classification |
| Victims | `/victims` | Per-victim: age group, condition, resource needed |
| Results | `/results` | Services, AI first-aid card, emergency call buttons |
| Journey | `/journey` | Full-screen map, blackspot detection, ETA SMS |
| AI Assist | `/ai` | Chat interface with Gemini + offline fallback |
| Safety | `/safety` | Silent SOS, trusted circle, fake call deterrent |
| Non-Emergency | `/non-emergency` | Towing, breakdown, puncture repair |
| Incident Status | `/incident-status` | Live tracking, 5-step progress, dispatcher messages |
| History | `/history` | Past emergency sessions list |
| Incident Details | `/incident-details` | Read-only historical incident view |
| Service Details | `/service-details` | Map + call + photo evidence |
| Profile | `/profile` | User name, blood group, emergency contacts |

---

## 📴 Offline Architecture

The offline layer is **not a degraded mode** — it is the primary design. All critical functions work without any internet connection.

```mermaid
graph LR
    subgraph "Bundled Assets (always available)"
        A[emergency_numbers.json\n190+ countries]
        B[decision_trees.json\nIndian Red Cross protocols]
        C[country_config.json\nAdapter routing]
        D[seed_services.json\nBootstrap POI data]
    end

    subgraph "SQLite Cache (Drift)"
        E[cached_services\n7-day expiry, geo-keyed]
        F[emergency_sessions_local\nsync queue]
        G[location_pings_local\nsync queue]
    end

    subgraph "Sync on Reconnect"
        H[ConnectivityService\nstream listener]
        I[OfflineService.syncUnsyncedPings\nbatch upload]
    end

    A & B & C & D --> APP[App Works Offline]
    E --> APP
    H --> I --> F & G
```

**Offline interceptor** (`core/interceptors/`): The Dio interceptor chain transparently serves cached `GET /api/services/nearby` responses from SQLite when the backend is unreachable, with no code change needed in UI layers.

---

## 🤖 AI Safety System

The AI module uses a **7-layer safety architecture** to prevent dangerous guidance:

```mermaid
graph TD
    Q[User Query] --> L1

    L1["Layer 1: System Prompt\nRestricts to road safety topics only"]
    L2["Layer 2: Temperature = 0.1\nNear-deterministic, no hallucinations"]
    L3["Layer 3: Output Validator\nRejects: dosages · diagnostic language ·\nmovement advice · 'not serious' assessments"]
    L4["Layer 4: Gemini Safety Filters\nBLOCK_LOW_AND_ABOVE for dangerous content"]
    L5["Layer 5: Offline Fallback\nActivates on any validation failure"]
    L6["Layer 6: Source Badge\nClearly labels Gemini vs offline protocol"]
    L7["Layer 7: Mandatory Disclaimer\nDisplayed under every AI response"]

    L1 --> L2 --> L3 --> L4 --> L5 --> L6 --> L7 --> RESP[Safe Response to User]

    style L3 fill:#DC2626,color:#fff
    style L5 fill:#D97706,color:#fff
```

Every AI response follows a mandatory structure:
```
IMMEDIATE: [single critical action]
STEPS:
  1. ...
  2. ...
  3. ...
CALL: [emergency number]
NOTE: [safety caveat]
```

---

## 🔧 Data Pipeline

### OSM Ingest

```bash
# Download and seed POI data for any city globally
python pipeline/ingest_osm.py \
  --city "Bengaluru" \
  --lat 12.971 \
  --lng 77.594 \
  --radius 30        # km radius
```

Fetches hospitals, police stations, fire stations, and ambulance services from the OSM Overpass API and upserts them to the `services` table with trust score 3.

### Emergency Numbers Seed

```bash
python pipeline/seed_emergency_numbers.py
```

Seeds `emergency_numbers` table with police, ambulance, fire, and unified numbers for 190+ countries from a verified dataset.

---

## 🗺️ Journey Mode & Blackspot Detection

Journey mode provides real-time warnings when approaching MoRTH-verified accident blackspots:

| Blackspot | Highway | 3-yr Accidents | Severity |
|-----------|---------|:--------------:|:--------:|
| Khopoli Ghat | NH-48 | 47 | 🔴 High |
| Karimnagar Bypass | NH-44 | 38 | 🔴 High |
| Jaipur–Delhi Corridor | NH-48 | 31 | 🔴 High |
| Tumkur Road | NH-75 | 29 | 🟡 Medium |
| Vadodara Expressway | NH-48 | 26 | 🟡 Medium |

> **Note:** The `blackspots` table is ready to receive all **13,795 MoRTH 2022 blackspots** from the full national highway dataset.

---

## 🌐 Web Dashboard (CAD)

The Next.js dispatch dashboard is a full **Computer Aided Dispatch** system:

- **Live Incident Queue** — auto-refreshes every 3 seconds, audio alert on new incidents
- **Priority Classification** — P1 Critical / P2 Urgent / P3 Routine with SLA timers
- **Status Workflow** — Received → Acknowledged → Dispatched → En Route → Resolved → Closed
- **Dispatcher Panel** — Notes with auto-save, responder coordinates, live message to victim
- **PDF CAD Report** — Exportable official incident report (jsPDF)
- **Leaflet Map** — Incident location pinned on OpenStreetMap

---

## 📜 Licence

Built for **IIT Madras Centre of Excellence in Road Safety (CoERS) Hackathon 2026**.

> *"In a country where someone dies on the road every 3.5 minutes, the right technology in the right hands at the right moment is not a feature — it is a responsibility."*
