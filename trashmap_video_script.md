# 🎬 TrashMap PH — 3-Minute Hackathon Demo Script
### Total Runtime: ~3:00 | Format: Screen Recording + Voiceover

---

## ⏱ TIMING OVERVIEW
| Segment | Time | Duration |
|---|---|---|
| Cold Open / Hook | 0:00 – 0:15 | 15s |
| LGU Dashboard | 0:15 – 1:45 | 90s |
| Citizen Mobile App | 1:45 – 2:30 | 45s |
| Driver Mobile App | 2:30 – 2:50 | 20s |
| Closing | 2:50 – 3:00 | 10s |

---

## 🎙️ SEGMENT 1 — COLD OPEN / HOOK `[0:00 – 0:15]`

### 🖥️ On Screen:
> Show a **split screen**: left side is a photo of an overflowing garbage pile on a Philippine street. Right side slowly fades in to the TrashMap PH LGU Dashboard login page at `trashmap-ph.vercel.app`.

### 🎤 Narration:
> *"Every day, tonnes of waste are missed. Not because of lack of effort — but because LGUs have no real-time visibility. **TrashMap PH** changes that."*

---

## 🖥️ SEGMENT 2 — LGU DASHBOARD `[0:15 – 1:45]`

### 🎤 Narration intro:
> *"Let's start with the LGU Command Center — a live, web-based dashboard built for barangay and city administrators."*

---

### 📍 Step 2A — Login `[0:15 – 0:22]`
**🖥️ Action:** Type `admin123` / `admin123` into the login form and click **Sign In as Admin**. The dashboard loads.

**🎤 Narration:**
> *"Admins sign in securely. The dashboard immediately connects to live data from the field."*

---

### 📍 Step 2B — Live Map + Pins `[0:22 – 0:38]`
**🖥️ Action:** Pan and zoom the **interactive Leaflet map**. Show the teal **collection point** pins clustered around barangays. Hover over one to show the tooltip label. Then show a **red missed-pickup pin** or **orange garbage report pin** if any exist.

**🎤 Narration:**
> *"On the live map, we see all active collection points — pinned, labeled, and updated in real time. Citizen waste reports appear instantly as field pins: orange for illegal dumpsites, red for missed pickups. Every report from the public lands here — live."*

> ⭐ **WOW CALLOUT — say this with emphasis:**
> *"No refresh button. No waiting. The moment a citizen submits a report, it appears on this map."*

---

### 📍 Step 2C — Risk Zones & Barangay Leaderboard `[0:38 – 0:48]`
**🖥️ Action:** Scroll the right sidebar. Show the **Risk Zones panel** — zones labeled LOW / MEDIUM / HIGH / CRITICAL. Then show the **Barangay Leaderboard** with report counts per zone.

**🎤 Narration:**
> *"Our AI-powered risk scoring clusters reports into hotspots — automatically. The leaderboard shows which barangays need immediate attention, ranked by report volume."*

---

### 📍 Step 2D — Fleet Status `[0:48 – 0:58]`
**🖥️ Action:** Scroll the sidebar to show the **Fleet Status panel**. Highlight a truck showing `en_route` or `collecting` with a progress bar. If a live truck ping is available, point to its moving truck marker on the map.

**🎤 Narration:**
> *"Fleet status is tracked live. Each truck's progress — stop-by-stop — is visible here. Admins know exactly where their fleet is without calling a single driver."*

---

### 📍 Step 2E — Weekly Route Templates `[0:58 – 1:12]`
**🖥️ Action:** Scroll to the **Route Management** section on the left panel. Expand the **Weekly Routes** dropdown. Click on a template to select it. Show the **Route Planner** toggle — enable it and hover over collection point pins to show them being selected as draft stops. *Don't need to actually create one — just visually demonstrate the flow.*

**🎤 Narration:**
> *"Admins can create recurring weekly routes right here on the map — just click the collection points you want included. This template is then assigned to a driver and automatically materializes as a real route every week."*

---

### 📍 Step 2F — Route Ops Token + Driver Assignment `[1:12 – 1:28]`
**🖥️ Action:** Scroll to the **Driver Assignment** section. Paste or type a token into the **Route Ops Token** field. Then select a driver from the dropdown and assign them to a selected template. Show the success message.

**🎤 Narration:**
> *"Operations like assigning drivers or starting routes require a **Route Ops Token** — a shared secret that acts as a security gate for sensitive actions. Think of it as a digital authority key. This prevents unauthorized changes to live routes, even if someone opens the dashboard."*
> *"Once assigned, the driver instantly sees their route on the mobile app."*

---

### 📍 Step 2G — Ops Activity Log `[1:28 – 1:45]`
**🖥️ Action:** Scroll to the **Ops Activity Log** section. Click through the tabs: **All**, **Audit**, **Pickups**. Show entries like `stop_completed` events, with timestamps and area labels. Briefly show the **Pickups tab** with completed/missed labels.

**🎤 Narration:**
> *"And every action in the field feeds directly into this live Ops Activity Log — route starts, stop completions, and exceptions. Full traceability from barangay hall to the last pickup point."*

> ⭐ **WOW CALLOUT:**
> *"This isn't a report generated at the end of the day. This is a live feed — updated the moment a driver confirms a pickup from their phone."*

---

## 📱 SEGMENT 3 — CITIZEN MOBILE APP `[1:45 – 2:30]`

**🖥️ Action:** Switch to phone screen recording / emulator. Open the TrashMap app as a citizen.

**🎤 Narration intro:**
> *"Now let's look at the public-facing side — the Citizen app."*

---

### 📍 Step 3A — Home / Schedule Screen `[1:45 – 1:55]`
**🖥️ Action:** Show the **Schedule Screen**. The app uses GPS to find collection points within 200 meters. Show a route card with a time window and a **"TODAY" badge** if today's recurrence day matches.

**🎤 Narration:**
> *"Citizens open the app and immediately see which waste collection routes are active near them — no searching required. It uses their GPS to surface only the relevant schedules, right down to the pickup window."*

> ⭐ **WOW CALLOUT:**
> *"It even highlights today's collections with a 'TODAY' badge — so residents know exactly when to put out their trash."*

---

### 📍 Step 3B — Submit a Report `[1:55 – 2:18]`
**🖥️ Action:** Navigate to the **Report Screen**. Select `Illegal Dumpsite` as the report type. Choose waste type `Mixed`. Optionally type a short description. Tap **Submit Report**. The screen shows a success confirmation.

**Then immediately switch to the LGU Dashboard** — show the new pin appearing live on the map.

**🎤 Narration:**
> *"Any resident can report a waste issue in seconds: type of waste, location — automatically captured by GPS — and a brief description. They tap submit..."*

> *"...and watch. Back on the LGU Dashboard, the pin appears **immediately**. No email, no hotline, no waiting."*

> ⭐ **WOW CALLOUT:**
> *"That's citizen data directly powering government decision-making. In real time."*

---

### 📍 Step 3C — Near Missed Pickup `[2:18 – 2:30]`
**🖥️ Action:** Show the **Report Screen** again but select `Missed Pickup`. Submit it. Back on dashboard, show the red missed-pickup pin.

**🎤 Narration:**
> *"Residents can also flag a missed pickup — ensuring no zone is forgotten and building a transparent record of service accountability."*

---

## 🚛 SEGMENT 4 — DRIVER MOBILE APP `[2:30 – 2:50]`

**🖥️ Action:** Switch to the driver-side app. Log in as a driver.

**🎤 Narration intro:**
> *"Lastly, the driver experience — built for the field, not an office."*

---

### 📍 Step 4A — My Routes / Start Route `[2:30 – 2:40]`
**🖥️ Action:** Show the **Driver Home Screen** with an assigned weekly route card. Tap **Start Route**. The route activates.

**🎤 Narration:**
> *"Drivers see their assigned routes on login. One tap starts the route — triggering the live tracking on the LGU Dashboard and unlocking the navigation screen."*

---

### 📍 Step 4B — Navigation + Confirm Pickup `[2:40 – 2:50]`
**🖥️ Action:** Show the **Navigation Screen** with a map showing the route polyline and stops. Tap **Confirm Pickup** on a stop. Show the snackbar confirmation. Briefly cut back to the dashboard Ops Activity Log showing the new `stop_completed` entry appearing.

**🎤 Narration:**
> *"GPS navigation guides them stop to stop. Each confirmed pickup instantly logs to the LGU Activity feed. The loop is complete."*

---

## 🏁 SEGMENT 5 — CLOSING `[2:50 – 3:00]`

**🖥️ Action:** Show a final **split screen** of the LGU Dashboard map on the left and the mobile app on the right, both live and active.

**🎤 Narration:**
> *"**TrashMap PH** — citizen reporting, driver navigation, and LGU command — all in one connected system. Built for the Philippines. Built for impact."*

---

## 📋 PRODUCTION NOTES

| Item | Note |
|---|---|
| **Demo data** | Pre-seed at least 3–5 report pins and 1 active route for the day before recording |
| **Route Ops Token** | Pre-fill the token field to avoid wasting time typing during demo |
| **Mobile recording** | Use emulator or screen mirror (Scrcpy) — must match Manila timezone |
| **Cut style** | Use smooth transitions; zoom-in on pins for WOW moments |
| **Background music** | Upbeat, light-tech instrumental — fade to 20% during narration |
| **Hackathon framing** | Emphasize *real-time*, *citizen empowerment*, and *zero infrastructure cost* |
