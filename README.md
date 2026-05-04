# CodeKada 2026
<img src="./assets/logo.png" alt="TrashMap PH Logo" width="500"/>

## TrashMap PH — Community Waste Management & Smart Collection Intelligence Platform
A full-stack application for the CodeKada 2025 hackathon.

By empowering citizens to report illegal dumpsites in real time and giving LGU officers a live operations dashboard with AI-optimized collection routing, TrashMap PH bridges the information gap between communities and local government — building cleaner, more responsive barangays from the ground up.

## Core Features
- Real-time citizen dumpsite reporting via mobile browser
- Live LGU operations dashboard with interactive map and heatmap
- AI-optimized garbage collection routing with fuel savings estimates
- Resident-facing estimated collection arrival schedules

## Limitation
- Data and implementation coverage is limited to **a selected pilot barangay, Quezon City**

## Tech Stack
- **LGU Dashboard:** ![Next.js](https://img.shields.io/badge/Next.js-000000?style=flat&logo=next.js&logoColor=white) ![TypeScript](https://img.shields.io/badge/TypeScript-3178C6?style=flat&logo=typescript&logoColor=white) ![Leaflet.js](https://img.shields.io/badge/Leaflet.js-199900?style=flat&logo=leaflet&logoColor=white) ![Tailwind CSS](https://img.shields.io/badge/Tailwind_CSS-38B2AC?style=flat&logo=tailwind-css&logoColor=white)
- **Client App:** ![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat&logo=flutter&logoColor=white) ![Dart](https://img.shields.io/badge/Dart-0175C2?style=flat&logo=dart&logoColor=white)
- **Backend & Realtime:** ![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?style=flat&logo=supabase&logoColor=white) ![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=flat&logo=postgresql&logoColor=white)
- **Route Optimization:** ![OpenRouteService](https://img.shields.io/badge/OpenRouteService-VRP_API-brightgreen?style=flat)

### Created by **UVCC**
* Vince Allen Tabelisma
* Generoso Estrabon
* Renz Eli Rey
* Peter Daniel Estuesta

## Project Structure

```
trashmap-ph/
├── assets/                        ← README images (logo, screenshots)
│
├── client_app/                    ← Flutter app — CLIENT SIDE (Citizen & Driver)
│   ├── android/                   ← Android build config & permissions
│   ├── lib/
│   │   ├── main.dart              ← App entry point, Supabase init
│   │   ├── screens/               ← UI screens (report form, map view, schedule)
│   │   ├── models/                ← Data models (Report, Zone, Schedule)
│   │   └── services/              ← Supabase queries & API calls
│   └── pubspec.yaml               ← Flutter dependencies
│
├── supabase/
│   └── schema.sql                 ← Database tables, PostGIS setup, Realtime config
│
├── src/                           ← Next.js source — LGU SIDE (Officer Dashboard)
│   ├── app/
│   │   ├── page.tsx               ← Main dashboard entry
│   │   ├── dashboard/             ← LGU live map & report management
│   │   ├── routes/                ← Route optimization & schedule publishing
│   │   └── api/                   ← Server-side API routes (ORS integration)
│   └── components/                ← Reusable UI components (Map, PinCard, Heatmap)
│
├── public/                        ← Static assets for Next.js
├── .env.local                     ← Environment variables (never commit this)
├── package.json                   ← Next.js dependencies
└── README.md
```

## Screenshots
![LGU Dashboard](./assets/dashboard.png)
![Client App](./assets/client.png)

## Setup Instructions

### Prerequisites
- Node.js v20+
- Flutter SDK
- Supabase account (free)
- OpenRouteService API key (free)

### 1. Environment Variables
Create a `.env.local` file in the project root:
```
NEXT_PUBLIC_SUPABASE_URL=your_supabase_project_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_supabase_anon_key
ORS_API_KEY=your_openrouteservice_api_key
```

### 2. LGU Dashboard Setup (Next.js)
```bash
# From the project root
npm install
npm run dev
```
Access at: `http://localhost:3000`

### 3. Client App Setup (Flutter)
```bash
cd client_app
flutter pub get
flutter run
```
> Make sure an Android emulator is running or a physical device is connected before `flutter run`.

### 4. Database Setup (Supabase)
In your Supabase project, go to **SQL Editor** and run the schema found in:
```
/supabase/schema.sql
```
Then go to **Database → Extensions** and enable **PostGIS**.

## License
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
