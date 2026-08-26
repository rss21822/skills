# Data and API Reference

This reference defines the reusable data and API patterns used by the Book GACHA Box framework.

## Core Data Model

Use D1 migrations as the source of truth. The exact domain names may change in a new app, but keep the same structure: primary content records, relationship/result identifiers, public sharing state, privacy state, audit logs, contact/report records, and click logs.

## Primary Content Table Pattern

Book GACHA Box uses a `shelves` table for submitted gifts. Equivalent apps should create one primary content table with these categories of columns:

```text
id
result_id
owner_token
status
matched_record_id
created_at
matched_at
language
message
items_json
public_share_enabled
public_share_id
public_status
identity_hidden
anonymized_at
hidden
deleted_at
actor_external_user_id
actor_username
actor_display_name
actor_profile_image_url
```

Rules:

- Store the public item payload separately from private actor identity fields.
- Keep a stable result ID for result pages.
- Keep an owner token for browser-based access where OAuth alone is not enough.
- Keep explicit privacy flags so identity can be hidden without deleting the content.

## Supporting Tables

Use supporting tables for:

```text
book_catalog or item_catalog
provider_cache
api_request_logs
submit_diagnostics
ratings
rating_events
contact_messages
content_reports
share_audit_logs
privacy_action_logs
affiliate_click_logs
public_share_og_images
```

The app should be able to answer:

- Who owns this content?
- Is it public, private, anonymous public, hidden, or deleted?
- Which public share URL belongs to this content and section?
- Has this user already received or interacted with this content?
- Can this action be audited later without storing unnecessary personal data?

## Exchange or Matching Flow

For exchange-style apps, implement the flow as one transaction where possible:

1. Validate login and anti-abuse token.
2. Validate item payload and selected candidates.
3. Create the submitted content record.
4. Select a random eligible counterpart.
5. Exclude the current user's own records and same external user ID.
6. Exclude records the user has already received.
7. Exclude hidden, deleted, blocked, bad-quality, or already matched records.
8. Link both records when a match exists.
9. Set owner cookies and return the result ID.
10. Write diagnostics with a request ID for failure investigation.

If using ratings as a quality filter, keep the threshold in one place and document how unrated records are treated.

## API Route Pattern

Every mutating API should follow this shape:

```text
parse request
assign requestId
check method and content type
check Origin when browser initiated
enforce body size
authenticate if required
rate limit by action-specific key
validate payload
perform DB operation
return safe JSON with requestId on errors
```

Do not leak internal stack traces, SQL, tokens, raw provider responses, or private user fields.

## Typical API Routes

```text
POST /api/exchanges/search-books
POST /api/exchanges/validate-book
POST /api/exchanges
GET  /api/exchanges/history
POST /api/exchanges/[resultId]/rating
POST /api/exchanges/[resultId]/report
POST /api/exchanges/[resultId]/share
POST /api/exchanges/[resultId]/anonymize-x
POST /api/affiliate-click
POST /api/contact
GET  /api/gallery
POST /api/public-shares/[shareId]/og
GET  /api/auth/x/login
GET  /api/auth/x/callback
POST /api/auth/logout
```

Adapt names to the new domain, but keep the separation.

## Authentication and Ownership

Use two concepts:

- Login identity proves the current external account.
- Owner cookie proves browser ownership of a specific result or content record.

Do not rely on client-side UI visibility for authorization. APIs must check ownership server-side.

Common rules:

- Unauthenticated login-required actions return `401`.
- Authenticated but non-owner actions return `403`.
- Private result lookup without owner proof should return `404` to avoid enumeration.
- Already hidden or idempotent privacy actions should not corrupt state.

## Privacy and Anonymous Public Content

Anonymous public content must retain public item data while removing identity exposure.

When a record is anonymous:

- Do not render external user ID, handle, display name, profile image URL, or profile link.
- Do not include those fields in JSON props or API responses.
- Show a generic anonymous label.
- Keep public content and item data accessible if the record is otherwise public.

Privacy changes should write an audit log such as:

```text
action_type = anonymize_x_identity
actor hash or owner reference
target record
created_at
request_id
```

## Public Share and OG Images

For public share pages:

- Use stable routes for each share ID and section.
- Keep submitted and received sections separate.
- Generate one static R2 image per `shareId`, `section`, and `cardVersion`.
- Metadata must point to the exact static image for the current URL.
- Do not reuse another share ID, another section, or an older card version.
- Fallback should be a static default image, not a dynamic error-prone route.

Recommended image contract:

```text
format: image/jpeg
size: 1200x630
public URL: https://assets.example.com/public-share-og/{cardVersion}/{shareId}/{section}.jpg
```

## Affiliate Link Pattern

Affiliate links should be direct links:

```html
<a
  href="https://www.amazon.co.jp/s?k=9780000000000&i=stripbooks&tag=example-22"
  target="_blank"
  rel="sponsored noopener"
  referrerPolicy="strict-origin-when-cross-origin"
>
  Amazonでこの本を探す
</a>
```

Rules:

- Do not use immediate redirect routes for normal affiliate navigation.
- Use ISBN search when ISBN is available. Fall back to title and author search only if the product domain requires it.
- Add the associate tag only when configured.
- Do not put internal user IDs, email addresses, IP addresses, or private IDs in the Amazon URL.
- Log clicks with `navigator.sendBeacon`; fall back to `fetch(..., { keepalive: true })`.
- Logging failure must not block navigation.

Click logs should store aggregatable fields, not raw personal data:

```text
event_id
event_name
occurred_at
page_type
result_id
shelf_id or content_id
shelf_type or section
slot_index
book_id or item_id
link_mode
link_status
cta_label
locale
current_path
target_host
target_url_hash
ip_hash
user_agent_hash
actor_hash
```

## Ads and Legal Surfaces

Ads should be environment-driven:

- Ad script disabled unless the public enable flag is true.
- Ad slots only on safe informational pages unless the product policy says otherwise.
- `ads.txt` should be generated from environment content.
- Privacy policy must disclose click logging, affiliate links, external links, cookies, and ad behavior.

## Contact and Reports

Keep `contact_messages` for general contact submissions.

For content reports, prefer a dedicated `content_reports` table. If operational simplicity requires the same table as contact messages, add a `source` or `category` column so reports remain queryable.

Report records should include:

```text
id
source
result_id or content_id
section
message
reporter identity hash or nullable user reference
created_at
request_id
status
```

## Rate Limits

Rate limits should be action-specific. Do not use one global limit for unrelated flows.

Recommended buckets:

```text
search-books
exchange-submit
rating
share
anonymize-x
affiliate-click
contact
report
auth
```

Use keys based on the lowest-risk available signal: account ID, owner token hash, IP hash, or a combination.
