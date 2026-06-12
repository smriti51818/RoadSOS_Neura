<div align="center">

# RoadSoS — Neura

### Road Safety Emergency Response System
**Emergency help in under 5 seconds · Fully offline · Covers 190+ countries**

*Built for IIT Madras Centre of Excellence in Road Safety (CoERS) Hackathon 2026 — Problem Statement 3*

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.111-009688?logo=fastapi)](https://fastapi.tiangolo.com)
[![Next.js](https://img.shields.io/badge/Next.js-16-black?logo=nextdotjs)](https://nextjs.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-Neon-4169E1?logo=postgresql)](https://neon.tech)

</div>

---

## The Problem

> **India loses one life to road accidents every 3.5 minutes.**

| Metric | Figure | Source |
|--------|--------|--------|
| Road accident deaths (2022) | 1,68,491 | MoRTH Annual Report 2022 |
| Average urban EMS response time | 20–45 min | NITI Aayog Report 2023 |
| Average rural EMS response time | 60+ min | National Health Mission Data |
| Lives saveable in the "Golden Hour" | Up to 60% | AIIMS Trauma Research |

Three points of failure: bystanders don't know which number to call, no structured GPS data reaches dispatchers, and there's no accountability after dialling.

---

## The Solution

RoadSoS gives anyone at a road accident **verified, geo-ranked emergency contacts in under 5 seconds** — with one tap to call — even with **zero internet connectivity**, anywhere in the world.

```
Open app → Select emergency type → Triage done → Contacts alerted, GPS shared, services surfaced
                        Under 30 seconds from launch to first action
```

**Core capabilities:**
- **One-Tap Emergency Dispatch** — 4 crisis categories, GPS auto-shared, SMS alerts fired
- **Geo-Adaptive Service Discovery** — Hospitals, police, ambulance ranked by distance and trust score
- **AI First Aid** — Gemini Flash online; Indian Red Cross decision trees offline
- **Fully Offline-First** — Emergency numbers for 190+ countries cached in SQLite
- **Journey Mode** — Real-time blackspot detection from MoRTH accident data
- **Women Safety Mode** — Silent SOS, trusted circle, fake-call deterrent
- **CAD Web Dashboard** — Dispatcher command centre with live incident queue and PDF reporting

---

## Architecture

```mermaid
graph TB
    subgraph Mobile["Flutter Mobile App"]
        UI[UI / GoRouter + Riverpod]
        ES[EmergencyService]
        AS[AIService · Gemini + Decision Trees]
        OS[OfflineService · Drift SQLite]
        SMS[SMS · url_launcher]
    end

    subgraph Backend["FastAPI Backend"]
        API[REST API]
        SF[ServiceFetcher · geo-adaptive]
        TS[TrustScorer · 5 tiers]
        RR[ResultRanker · distance + trust]
    end

    subgraph Adapters["Data Adapters"]
        OSM[OpenStreetMap · Overpass QL]
        MPLS[Mappls · India]
        NHS[NHS CQC · UK]
        HDX[HDX · Africa / UN]
        HS[Healthsites · Global]
    end

    subgraph Cloud["Cloud"]
        NEON[(Neon PostgreSQL + PostGIS)]
        GEMINI[Gemini Flash 1.5]
        GEO[Geoapify · Places + Routing]
    end

    subgraph Dashboard["Next.js CAD Dashboard"]
        CAD[Incident Queue · P1/P2/P3]
        PDF[PDF Export · jsPDF]
    end

    UI --> ES --> API
    UI --> OS
    UI --> AS --> GEMINI
    ES --> SMS
    API --> SF --> Adapters
    SF --> TS --> RR
    API --> NEON
    Dashboard --> NEON
    Adapters --> GEO
```

---

## Tech Stack

### Mobile (Flutter)

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Framework | Flutter 3.x + Dart | Single codebase for Android & iOS |
| State Management | Riverpod 2.x | Compile-time safe providers |
| Local Database | Drift (SQLite) | Offline-first typed data layer |
| Navigation | GoRouter 13 | Declarative routing + deep links |
| Maps | flutter_map + OpenStreetMap | Free, offline-capable maps |
| Background | flutter_background_service | Location pings when backgrounded |

### Backend (Python)

| Layer | Technology | Purpose |
|-------|-----------|---------|
| API Framework | FastAPI 0.111 | Async REST API with OpenAPI docs |
| Database | asyncpg | Native async PostgreSQL driver |
| HTTP Client | aiohttp + httpx | Async adapter calls with timeouts |
| Validation | Pydantic v2 | Request/response schema validation |

### Web Dashboard (Next.js)

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Framework | Next.js 16 + React 19 | Full-stack TypeScript app |
| Database | @neondatabase/serverless | Direct Neon DB connection |
| Maps | Leaflet + react-leaflet | Interactive incident map |
| PDF Export | jsPDF | Official CAD incident reports |
| Styling | Tailwind CSS 4 | Utility-first design system |

### External APIs

| Service | Provider | Usage |
|---------|----------|-------|
| Database | Neon PostgreSQL + PostGIS | Emergency sessions, services, blackspots |
| Maps (India) | Mappls (MapMyIndia) | India-specific POI search |
| Maps (Global) | Geoapify | Places, geocoding, routing |
| Vehicle Services | Google Places API | Towing, breakdown, tyre repair |
| AI Guidance | Gemini Flash 1.5 | Online first-aid instructions |
| UK Services | NHS CQC API | UK hospital data |
| Africa Data | HDX (UN) | Health facilities in developing nations |

---

## Data Sources & Trust Scoring

Services are filtered by trust score before being shown in emergency mode. Only score ≥ 3 is surfaced when a life depends on the result.

| Source | Trust Score | Coverage |
|--------|:-----------:|----------|
| data.gov.in / NHA / NHS CQC / MoRTH | **5** | India + UK |
| Mappls (MapMyIndia) / Healthsites.io | **4** | India + Global |
| OpenStreetMap / Overpass QL | **3** | Global |
| HDX (UN) | **2** | Africa (non-emergency only) |

---

## Project Structure

```
RoadSOS_Neura/
├── mobile/                         # Flutter mobile application
│   └── lib/
│       ├── core/                   # Router, theme, constants, API keys
│       ├── data/                   # Models, Drift DB, providers, services
│       ├── services/               # AI, emergency, location, SMS, offline
│       ├── features/               # Screen modules (home, triage, results…)
│       └── widgets/                # Shared reusable widgets
│
├── backend/                        # FastAPI Python backend
│   ├── core/                       # DB pool, service fetcher, trust scorer
│   ├── adapters/                   # OSM, Mappls, NHS CQC, HDX, Healthsites
│   ├── routers/                    # /api/emergency, /api/services, /api/offline
│   └── schemas/                    # Pydantic request/response models
│
├── web_dashboard/                  # Next.js CAD dispatch dashboard
│   └── src/app/                    # Dashboard UI, Leaflet map, API routes
│
├── database/
│   └── schema.sql                  # PostgreSQL schema (7 tables + indexes)
│
└── pipeline/
    ├── seed_emergency_numbers.py   # Seeds 190+ country emergency numbers
    └── ingest_osm.py               # Downloads city POI data from OSM
```

---

## Quick Start

### Prerequisites

| Tool | Version |
|------|---------|
| Python | 3.11+ |
| Flutter SDK | 3.3+ |
| Node.js | 20+ |

### 1. Database (Neon or Supabase)

Create a project on [neon.tech](https://neon.tech) or [supabase.com](https://supabase.com), then run `database/schema.sql` in the SQL editor.

### 2. Backend

```bash
cd backend
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env          # fill in your values
uvicorn main:app --reload --port 8000
# API at http://localhost:8000 · Swagger at http://localhost:8000/docs
```

### 3. Seed Data

```bash
cd pipeline
python seed_emergency_numbers.py           # 190+ country emergency numbers
python ingest_osm.py --city Mumbai --lat 19.076 --lng 72.877 --radius 25
```

### 4. Flutter Mobile App

```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
cp .env.local.example .env

# Android emulator (backend at 10.0.2.2)
flutter run --dart-define-from-file=.env

# Physical device (replace with your machine's IP)
flutter run --dart-define-from-file=.env --dart-define=API_BASE_URL=http://192.168.1.x:8000
```

### 5. Web Dashboard

```bash
cd web_dashboard
npm install && npm run dev
# Dashboard at http://localhost:3000
```

---

## Environment Variables

### `backend/.env`

```env
NEON_DATABASE_URL=postgresql://user:pass@ep-xxx.region.aws.neon.tech/neondb?sslmode=require
MAPPLS_API_KEY=your-mappls-api-key
GEMINI_API_KEY=your-gemini-api-key
CQC_API_KEY=your-cqc-api-key          # optional — UK hospital data
HEALTHSITES_API_KEY=your-key           # optional — global health facilities
ENVIRONMENT=development
SECRET_KEY=change-this-in-production
```

### `mobile/.env`

```env
GEOAPIFY_API_KEY=your-geoapify-api-key
GOOGLE_PLACES_API_KEY=your-google-places-api-key
API_BASE_URL=http://10.0.2.2:8000      # use machine IP for physical device
MAPPLS_API_KEY=your-mappls-api-key
GEMINI_API_KEY=your-gemini-api-key
```

### `web_dashboard/.env.local`

```env
DATABASE_URL=postgresql://user:pass@ep-xxx.region.aws.neon.tech/neondb?sslmode=require
```

---

## API Reference

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Liveness probe |
| `POST` | `/api/emergency/start` | Open a new emergency session |
| `POST` | `/api/emergency/ping` | Send location update for active session |
| `POST` | `/api/emergency/resolve` | Close/resolve an emergency session |
| `GET` | `/api/services/nearby` | Get ranked nearby services by GPS |
| `GET` | `/api/services/emergency-numbers/{cc}` | Country emergency numbers |
| `GET` | `/api/offline/decision-trees` | Bundled offline AI decision trees |
| `GET` | `/docs` | Interactive Swagger UI |

```bash
# Start emergency session
curl -X POST http://localhost:8000/api/emergency/start \
  -H "Content-Type: application/json" \
  -d '{"emergency_type":"accident","lat":19.076,"lng":72.877,"victim_count":2}'

# Nearby services
curl "http://localhost:8000/api/services/nearby?lat=19.076&lng=72.877&emergency_mode=true"

# India emergency numbers
curl http://localhost:8000/api/services/emergency-numbers/IN
```

---

## Licence

Built for **IIT Madras Centre of Excellence in Road Safety (CoERS) Hackathon 2026**.

> *"In a country where someone dies on the road every 3.5 minutes, the right technology in the right hands at the right moment is not a feature — it is a responsibility."*
