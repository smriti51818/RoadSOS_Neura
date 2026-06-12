# RoadSoS

> Road Safety Emergency Response System
> Built for IIT Madras Road Safety Hackathon 2026

## The Problem

Over 1.5 lakh people die in road accidents in India every year.
The "golden hour" — the first hour after an accident — is when
timely help saves lives. Victims and bystanders cannot find
verified emergency contacts fast enough.

## The Solution

RoadSoS gives anyone at a road accident verified, location-aware
emergency contacts in under 5 seconds — with one tap to call —
even with zero internet connectivity, anywhere in the world.

## Quick Start

### Backend
```bash
cd backend
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env      # fill in your values
uvicorn main:app --reload --port 8000
```

### Flutter
```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

### Database Setup (Supabase)
1. Go to supabase.com → Create project → SQL Editor
2. Paste contents of `database/schema.sql` → Run
3. Verify 7 tables created: services, emergency_numbers, emergency_sessions,
   location_pings, user_reports, offline_packs, blackspots

### Seed Data
```bash
cd pipeline
python seed_emergency_numbers.py
python ingest_osm.py --city Mumbai --lat 19.076 --lng 72.877 --radius 25
```

## Environment Variables

### backend/.env
```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-supabase-service-role-key
MAPPLS_API_KEY=your-mappls-api-key
GEMINI_API_KEY=your-gemini-api-key
ENVIRONMENT=development
SECRET_KEY=change-this-in-production
```

### Flutter (--dart-define flags)
```
API_BASE_URL=http://10.0.2.2:8000
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-supabase-anon-key
MAPPLS_API_KEY=your-mappls-api-key
GEMINI_API_KEY=your-gemini-api-key
```

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile | Flutter + Riverpod 2.x + Drift (SQLite) |
| Backend | FastAPI + Python |
| Cloud DB | Supabase PostgreSQL + PostGIS |
| India maps | Mappls (MapMyIndia) |
| Global maps | flutter_map + OpenStreetMap |
| AI online | Google Gemini Flash API |
| AI offline | JSON decision trees |
| Background | flutter_background_service |

## Data Sources

| Source | Data | Trust Score |
|---|---|---|
| data.gov.in | India hospital + health centres directory | 5 |
| NHA / nhp.gov.in | National hospital directory with GPS | 5 |
| MoRTH | Highway accident blackspot data | 5 |
| NHS CQC API | UK hospital data (daily updated) | 5 |
| Mappls | India nearby services | 4 |
| OSM Overpass | Global service data | 3 |
| HDX (UN) | Africa health facility data | 2 |
| emergencynumberapi.com | 190+ country emergency numbers | N/A |

## Module Build Order

| Day | Module | Description |
|---|---|---|
| 1 AM | Module 1 | Scaffold + DB + Config + Backend base ✅ |
| 1 PM | Module 2 | Geo-adaptive service fetcher |
| 2 AM | Module 3 | Flutter shell + loading + home screen |
| 2 PM | Module 4 | Emergency triage + results + one-tap call |
| 3 AM | Module 5 | Offline architecture (Drift + cache) |
| 3 PM | Module 6 | Data pipeline + seed real data |
| 4 AM | Module 7 | Journey mode + blackspot warnings |
| 4 PM | Module 8 | AI Assist (Gemini + offline tree) |
| 5 AM | Module 9 | Group victims flow |
| 5 PM | Module 10 | Women/solo traveller safety mode |
| 5 Eve | Module 11 | Non-emergency + milestone + checklist |
| 6 AM | Module 12 | UI polish + APK build + testing |
| 6 PM | Module 13 | PPT + submission package |

## Verification Commands

```bash
# Backend health
curl http://localhost:8000/health
# → {"status":"ok","version":"1.0.0","timestamp":"..."}

# Emergency numbers loaded
curl http://localhost:8000/api/services/emergency-numbers/IN
# → {"country_code":"IN","police":"100","ambulance":"108",...}

# Decision trees loaded
curl http://localhost:8000/api/offline/decision-trees
# → {"breakdown":{...},"accident_injury":{...},...}
```

## Licence

Built for IIT Madras Road Safety Hackathon 2026.
For competition purposes only.
