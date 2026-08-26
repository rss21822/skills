# Implementation Checklist

Use this checklist when building a new app with the Book GACHA Box framework.

## 1. Project Setup

- Create a Next.js App Router TypeScript project.
- Add OpenNext Cloudflare and Wrangler.
- Add scripts for local dev, build, Cloudflare build, deployment, typecheck, lint, and migrations.
- Add `app/globals.css` and a second app-specific CSS file for the visual system.
- Add `wrangler.jsonc` with D1 and R2 bindings.
- Add local environment examples without real secrets.

## 2. Data Layer

- Create D1 migrations for the primary content table and all supporting logs.
- Implement the provider boundary: shared `db.ts`, Cloudflare implementation, and local Node implementation.
- Keep all DB writes in library functions or API routes, not UI components.
- Add indexes for lookup by result ID, owner, status, public share ID, created time, and match eligibility.
- Add diagnostics tables before debugging production incidents.

## 3. Authentication

- Implement X OAuth or the chosen OAuth provider.
- Store minimal identity data.
- Implement login, callback, logout, and current-session helpers.
- Use secure cookies in production.
- Add owner-token cookies for result ownership when the domain flow needs browser-level ownership.
- Redirect or block logged-out users for login-required pages and actions.

## 4. Main Domain Flow

- Build the primary form as a client component.
- Validate all inputs on the client for usability and on the server for security.
- Add external metadata lookup only behind an API route.
- Add candidate selection and validation so users submit canonical item records, not only free text.
- Add Turnstile or equivalent anti-abuse verification before final submit.
- Add one transaction for create-and-match where the domain requires consistency.
- Return stable result IDs.

## 5. Result and History UI

- Build a result page that shows the submitted side and received side.
- Add a history modal for previous results.
- Ensure modals are top-layer and do not sit behind page controls.
- Add copy/share actions.
- Add resend or reuse behavior if the product benefits from repeating previous submissions.
- Add rating and report actions only where semantically valid.

## 6. Public Sharing

- Add public share enable/disable API.
- Add submitted and received public share pages.
- Add localized titles and descriptions.
- Generate static R2 OG images before opening X share intents.
- Metadata must use the exact static image for the current share ID, section, and card version.
- Verify `og:image` and `twitter:image` return `200`, `image/jpeg`, and 1200x630.

## 7. Privacy

- Add public status columns.
- Add identity-hidden columns.
- Add anonymization API with owner checks.
- Ensure anonymous content never renders private identity fields.
- Ensure gallery, result, public share, history, and API responses all use the same privacy shaping.
- Add privacy audit logs.

## 8. Monetization

- Build affiliate links as direct `href` links.
- Add affiliate click logging without blocking navigation.
- Add Origin validation, payload validation, duplicate event handling, and rate limits to the click-log API.
- Hash sensitive log signals with a secret.
- Add environment-driven AdSense script and slots.
- Keep ad slots off unsafe or transactional pages unless deliberately approved.
- Add `ads.txt` environment integration.
- Add affiliate and external-link language to the privacy policy.

## 9. Legal and Trust Pages

- Add terms, privacy, guide, about, and contact pages.
- Add footer links to all legal and contact surfaces.
- Add contact form validation, rate limiting, and storage.
- Add content report flow for user-generated content.
- Avoid wording that claims monetization is active before IDs and disclosures are actually configured.

## 10. Security Review

- Check all POST routes for Origin validation where browser initiated.
- Check all POST routes for body-size limits.
- Check all POST routes for action-specific rate limits.
- Check every ownership-sensitive route server-side.
- Confirm private and anonymous records cannot be enumerated.
- Confirm raw secrets, tokens, IP addresses, and external user IDs are not logged unnecessarily.
- Confirm 500 responses include request IDs but no internal details.

## 11. Production Setup

- Create Cloudflare D1 database.
- Create Cloudflare R2 bucket and public asset domain if public images are required.
- Configure Workers/Pages bindings.
- Configure all production secrets.
- Apply D1 migrations remotely.
- Deploy from the intended branch.
- Test OAuth callback URLs against the production domain.
- Test Turnstile site key and secret key against the production domain.
- Test public share cards in X after cache-sensitive metadata changes.

## 12. Minimum Verification

Run these before release:

```bash
npm run typecheck
npm run build
npm run build:cf
```

Then manually verify:

- Login and logout.
- Main submit flow.
- Matching or result creation.
- Result page access with and without owner proof.
- Public share submitted and received pages.
- Static OG image URLs.
- Gallery or listing page.
- Rating/report/contact APIs.
- Affiliate link attributes and tag behavior.
- Privacy/anonymization behavior.
