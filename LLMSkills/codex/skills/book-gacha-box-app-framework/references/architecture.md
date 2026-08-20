# Book GACHA Box Architecture Reference

This reference captures the reusable application framework behind Book GACHA Box. Use it to build another app with the same structure, not to copy the exact product domain.

## Framework Overview

The app is a Cloudflare-first Next.js application:

- Next.js App Router provides routes, server components, metadata, and API handlers.
- React client components are used only for interactive UI such as forms, modals, carousels, sharing, and local validation.
- OpenNext packages the Next.js app for Cloudflare Workers.
- Wrangler deploys the Worker and binds D1, R2, and environment variables.
- D1 is the source of truth for application records.
- R2 stores generated public assets such as share-card JPEG images.
- Plain CSS files define the visual system.

## Recommended Root Files

```text
package.json
next.config.ts
open-next.config.ts
wrangler.jsonc
tsconfig.json
middleware.ts
app/
components/
lib/
migrations/
public/
scripts/
docs/
plans/
```

## App Router Layout

Use the following route groups as the baseline:

```text
app/layout.tsx
app/page.tsx
app/about/page.tsx
app/contact/page.tsx
app/gallery/page.tsx
app/guide/page.tsx
app/privacy/page.tsx
app/result/page.tsx
app/share/[shareId]/page.tsx
app/share/[shareId]/submitted/page.tsx
app/share/[shareId]/received/page.tsx
app/terms/page.tsx
app/ads.txt/route.ts
```

API routes should live under `app/api` and stay focused on one responsibility per route.

## Component Layers

Use `components` for reusable UI and client behavior. Typical components:

```text
components/book-form.tsx
components/result-client.tsx
components/exchange-history-modal.tsx
components/public-share-shelf-page.tsx
components/shelf-card.tsx
components/gallery-preview.tsx
components/amazon-affiliate-link.tsx
components/site-hero.tsx
components/site-footer.tsx
components/x-login-button.tsx
```

Recommended split:

- Server page fetches data and passes safe props.
- Client component handles local state, form validation, modal state, and click handlers.
- Shared components avoid direct DB access.
- Privacy filtering happens before props reach UI.

## Library Layers

Use `lib` for all reusable non-UI logic:

```text
lib/db.ts
lib/db-cloudflare.ts
lib/db-node.ts
lib/cloudflare-env.ts
lib/request-security.ts
lib/response-security.ts
lib/rate-limit.ts
lib/rate-limit-cloudflare.ts
lib/x-auth.ts
lib/x-auth-cookies.ts
lib/book-metadata.ts
lib/book-utils.ts
lib/amazon-affiliate.ts
lib/public-share.ts
lib/public-share-og-r2.ts
lib/i18n.ts
```

The key pattern is the DB provider boundary:

- `db.ts` exposes stable application functions.
- `db-cloudflare.ts` uses Cloudflare D1 bindings.
- `db-node.ts` supports local development and tests.

## Styling System

Default to plain CSS:

```text
app/globals.css
app/ui-brushup.css
```

Use semantic class names that describe product UI, not framework internals. Keep responsive rules close to the relevant component class names. Avoid adding Tailwind unless the new app explicitly chooses Tailwind as its design system.

## Deployment Model

Baseline production deployment:

- Build with `next build` and OpenNext Cloudflare.
- Deploy with Wrangler.
- Bind D1 database as the primary DB binding.
- Bind R2 bucket for generated public assets.
- Configure secrets and environment variables in Cloudflare, not in source.
- Apply D1 migrations before traffic depends on new schema.

## Required Cloudflare Bindings

Use names that match the app code:

```text
DB                         D1 database binding
PUBLIC_SHARE_OG_BUCKET     R2 bucket binding
```

The exact binding names can differ only if the env access layer maps them consistently.

## Standard Environment Variables

```text
SITE_URL
X_CLIENT_ID
X_CLIENT_SECRET
X_REDIRECT_URI
X_AUTH_SCOPE
NEXT_PUBLIC_TURNSTILE_SITE_KEY
TURNSTILE_SECRET_KEY
ISBNDB_API_KEY
AMAZON_ASSOCIATE_TAG
AMAZON_STORE_DOMAIN
PUBLIC_SHARE_OG_BASE_URL
CLICK_LOG_SECRET
ADMIN_X_USER_IDS
NEXT_PUBLIC_ENABLE_ADSENSE
NEXT_PUBLIC_ADSENSE_CLIENT
ADS_TXT_CONTENT
```

Do not confuse `AMAZON_ASSOCIATE_TAG` with similarly named variables. The source should read one canonical variable, with any aliases handled explicitly if needed.

## Metadata and Sharing

Every shareable page should define:

- `title`
- `description`
- `openGraph.siteName`
- `openGraph.images`
- `twitter.card`
- `twitter.images`

For X card reliability, prefer a static public JPEG URL:

```text
https://assets.example.com/public-share-og/{cardVersion}/{shareId}/{section}.jpg
```

Avoid relying on dynamic OG image generation at crawl time when generated cards include external book-cover images.

## Local Development

Local development should work without Cloudflare services where practical:

- Use local DB implementation.
- Stub or gracefully fail external services.
- Keep `.dev.vars` or local env files out of commits.
- Provide scripts to apply local migrations.

## Production Guardrails

Do not ship a new app without:

- D1 migrations committed.
- Mutating APIs protected by validation and rate limiting.
- OAuth callback and logout paths tested.
- Turnstile configured on high-risk forms.
- Privacy policy and contact page present.
- Public share metadata verified with direct HTML inspection.
- Static OG image URLs returning `200`, `image/jpeg`, and the expected dimensions.
