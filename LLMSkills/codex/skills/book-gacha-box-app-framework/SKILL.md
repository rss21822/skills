---
name: book-gacha-box-app-framework
description: "Create or rebuild apps using the Book GACHA Box architecture: Next.js App Router, React and TypeScript, Cloudflare Workers via OpenNext, D1, R2, X OAuth, Turnstile, public share OG images, Amazon affiliate links, ads and legal pages, and security/rate-limit patterns. Use when asked to recreate Book GACHA Box, build a similar anonymous exchange or social sharing app, or scaffold a Cloudflare-first production web service with the same structure."
---

# Book GACHA Box App Framework

Use this skill to build a new app with the same engineering structure as Book GACHA Box, even when the user only says they want "the same framework" or "a similar app."

The default output is a production-oriented Next.js App Router app deployed to Cloudflare Workers through OpenNext, with D1 as the relational database, R2 for generated public assets, OAuth login, anti-abuse checks, public sharing, legal pages, and monetization hooks.

## Default Stack

- Next.js App Router with React, TypeScript, and server components by default.
- Cloudflare Workers deployment through `@opennextjs/cloudflare` and `wrangler`.
- Cloudflare D1 for primary relational data.
- Cloudflare R2 for generated static share images and other public generated assets.
- X OAuth login, signed/session cookies, and owner-token cookies for result ownership.
- Cloudflare Turnstile for high-risk submit flows.
- Plain CSS style layers, not Tailwind or shadcn by default.
- Local development through Node-compatible adapters and SQLite-style local DB tooling.
- Security utilities for Origin checks, body-size checks, rate limits, request IDs, and safe errors.

## Build Workflow

1. Start with the repository layout in `references/architecture.md`.
2. Define the domain data model and migrations from `references/data-and-apis.md`.
3. Build pages as server components first. Move only interactive behavior into client components.
4. Put database access behind a provider boundary: Cloudflare D1 implementation for production, Node/local implementation for development and tests.
5. Centralize auth, rate limiting, Origin checks, response hardening, and privacy filtering in `lib`.
6. Add public sharing after the core domain flow works. Public pages must have stable URLs, metadata, and static OG images.
7. Add monetization hooks as optional environment-driven features. Do not hard-code live IDs.
8. Run the checklist in `references/implementation-checklist.md` before declaring the app ready.

## Repository Shape

Use this shape unless the user explicitly asks for a different framework:

```text
app/
  layout.tsx
  page.tsx
  api/
  about/
  contact/
  gallery/
  guide/
  privacy/
  result/
  share/
  terms/
components/
lib/
migrations/
public/
scripts/
docs/
plans/
```

## Core Implementation Rules

- Keep pages thin. Put reusable UI in `components` and domain logic in `lib`.
- Keep DB access out of components. Components receive already filtered data.
- Treat privacy as a data-shaping rule, not only a display rule. Anonymous records must not include private X fields in rendered HTML or API payloads.
- Generate public share images before opening share intents when possible. Metadata should point to static R2 image URLs, not dynamic image routes.
- Direct affiliate links should be normal `href` links. Logging must not block navigation.
- Legal, contact, privacy, terms, and disclosure surfaces are part of the framework, not post-launch extras.
- Every mutating API should have request validation, Origin checks where applicable, rate limiting, safe errors, and a request ID.
- Prefer additive D1 migrations. Do not depend on manual dashboard edits for schema changes.

## Reference Files

- Read `references/architecture.md` when scaffolding the app or deciding file placement.
- Read `references/data-and-apis.md` when creating migrations, data access functions, API routes, auth rules, or public sharing.
- Read `references/implementation-checklist.md` before final delivery or deployment.

## Standard Commands

Use project-specific scripts when present. A typical app based on this framework should support:

```bash
npm run dev
npm run build
npm run build:cf
npm run deploy:cf
npm run typecheck
npm run lint
```

For D1 projects, include scripts or documented commands for local and remote migrations:

```bash
wrangler d1 migrations apply <database_name> --local
wrangler d1 migrations apply <database_name> --remote
```

## Delivery Standard

When using this skill, final output should explain:

- The generated or changed structure.
- Which environment variables and Cloudflare bindings are required.
- Which migrations must be applied.
- Which verification commands were run.
- Any remaining production setup that cannot be completed from source code alone.
