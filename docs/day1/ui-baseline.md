# TrashMap PH Day 1 UI Baseline

## Purpose
Keep LGU web shell and Flutter client shell visually consistent during static-first sprint phase.

## Core Tokens
- **Primary**: `#166534` (Green 800)
- **Primary Soft**: `#DCFCE7` (Green 100)
- **Surface (App Background)**: `#F8FAFC`
- **Card Background**: `#FFFFFF`
- **Border**: `#E5E7EB`
- **Text Primary**: `#0F172A`
- **Text Secondary**: `#4B5563`

## Status Colors
- **Dumpsite**: Amber (`#D97706`)
- **Missed Pickup**: Blue (`#2563EB`)
- **Hotspot / High Severity**: Red (`#DC2626`)
- **Collecting / Healthy**: Emerald (`#16A34A`)

## Typography + Spacing Rules
- Use semibold headers with clear hierarchy:
  - Page title: ~20px
  - Section title: ~15px
  - Meta text: 11px–12px
- Card radius: 14px to 16px.
- Default section spacing: 12px outer, 14px inner card padding.

## Day 1 Shell Application
- Web (`src/`):
  - Header badge uses primary-soft background + primary text.
  - Panel/card style uses white surfaces with subtle border.
- Mobile (`client_app/lib/`):
  - Shared `AppTheme` controls app bar, cards, inputs, nav bar, snackbar.
  - Reusable `SectionCard` component inherits style from theme.

## Day 2 Integration Note
No visual redesign needed before data wiring. New screens should reuse these tokens to prevent style drift while features are connected to Supabase.
