# Phase 6 Validation Log (Day 2)

## Validation Rule
Local-first checks pass before demo and integration handoff.

## Automated Checks
- Web `npm run lint` -> pass
- Web `npm run build` -> pass
- Flutter `flutter analyze` -> pass
- Flutter `flutter test` -> pass
- Flutter `flutter build apk --debug` -> pass
- APK output verified at `client_app/build/app/outputs/flutter-apk/app-debug.apk`

## Functional Demo Checklist
- Admin dashboard auth gate works with seeded admin account (`admin123` / `admin123`)
- Mobile sign-up/sign-in works for `citizen` and `driver` roles
- Citizen map tap stores selected coordinates for report flow
- Citizen report submit writes to `reports` table
- Dashboard map pulls pins from Supabase `reports` table (no mock pin source)
- Dashboard map refreshes on realtime `reports` changes

## Manual End-to-End Demo Steps
1. Start web app and sign in as admin on dashboard.
2. Start mobile app with Supabase dart-define values.
3. On mobile map, tap location to set pin.
4. Open report tab, verify same coordinates shown.
5. Submit report with waste type + description.
6. Check Supabase `reports` table for new row.
7. Check web dashboard map for new/updated pin without page reload.

## Status
Phase 6 complete. Day 2 scope (Phases 1-6) validated locally.
