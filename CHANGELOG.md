# GetWeChaat API — Changelog

All notable changes to the backend and WhatsApp bot, in plain language.
Versions follow v MAJOR.MINOR.PATCH — we stay on v0.x until the first real seller is live.

## v0.1.0 — 2026-07-07 · Foundation

- Node.js + Express skeleton with routes for WhatsApp webhook, products, and orders
- Supabase client wiring and `.env.example` with all keys the project will need
- Complete Postgres schema (`db/schema.sql`): sellers, products with per-seller
  serial numbers, customers with WhatsApp opt-in, orders, order items, invoices
- Atomic invoice numbering (INV-2026-0001 style, resets each year, duplicate-proof)
- GitHub repo set up with `main` (production) and `develop` (working) branches

## Planned

- v0.2.0 — Schema running live on Supabase
- v0.4.0 — WhatsApp bot answers its first message (AiSensy or Wati webhook)
- v0.6.0 — PDF invoice generation with Puppeteer
- v0.7.0 — UPI payment tracking via Razorpay/Cashfree
- v1.0.0 — First seller live, taking real orders
