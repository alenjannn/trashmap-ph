# TrashMap PH — test accounts

**Dev / QA only.** Passwords and emails here are intentional for local demos. **Do not use in production**; rotate or delete these users before going live.

## Accounts

| Role | Where to sign in | Identifier | Password |
|------|------------------|------------|----------|
| **Admin (LGU dashboard)** | Web — admin gate before map (`AdminLoginGate`) | Username: `admin123` | `admin123` |
| **Citizen** | Flutter app — Supabase Auth (email) | `chiefestrabon04@gmail.com` | `123456` |
| **Driver** | Flutter app — Supabase Auth (email) | `distresscode04@gmail.com` | `123456` |

### Notes

- **Admin** uses the `public.admin_access_secrets` table and `/api/admin-auth`, **not** Supabase email login. The dashboard Supabase client uses the anon key; fleet/report RLS behavior is documented in `TEAM_HANDOFF_CONTEXT.md` and `HOW TOs.md` (HOW TO 18).
- **Citizen** and **driver** are created by `supabase/schema.sql` (end of file): rows in `auth.users` + `auth.identities`, with `app_user_profiles` role forced from email. Re-run the full schema in the Supabase SQL Editor if those users are missing.
- If an email is **already** registered (e.g. signed up in the Dashboard first), the seed block **skips** inserting that Auth user; adjust or delete the existing user in **Authentication → Users**, then re-run the seed section, or sign in with the password you set.

## Plain-text mirror

See `TEST_ACCOUNTS.txt` in this folder for the same content without tables.
