# Block F Validation Log (Day 1)

## Validation Rule
Local-first checks must pass before integration or Day 2 data wiring.

## Web Checks
- `npm run lint` -> pass
- `npm run build` -> pass

## Flutter Checks
- `flutter analyze` -> pass
- `flutter test` -> pass
- `flutter build apk --debug` -> pass
- APK output verified at `client_app/build/app/outputs/flutter-apk/app-debug.apk`

## Database Checks
- `supabase/schema.sql` updated with Day 1 entities and constraints
- no IDE lint diagnostics reported on schema or touched app files

## Day 1 Block Completion
- Block A: setup + structure done
- Block B: backend schema foundation done
- Block C: Next.js static LGU shell done
- Block D: Flutter static citizen shell done
- Block E: shared UI baseline done
- Block F: validation + handoff done
