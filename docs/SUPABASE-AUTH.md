# Supabase Auth activation - 2026-11-10

## Project

- Project: `tevel-invoice-eu`
- Reference: `lyfojepvxzskyoesbmqx`
- Organization: `INVOICE` (`uboofdcpllajcxrjeyhl`)
- Region: Frankfurt (`eu-central-1`)
- Dashboard: https://supabase.com/dashboard/project/lyfojepvxzskyoesbmqx
- Auth origin: https://lyfojepvxzskyoesbmqx.supabase.co
- Publishable key: `sb_publishable_BmkATzD42YOWhoT09KG6pw_tqbA7CaL`

The publishable key is client configuration, not a server secret. No secret or
service-role key belongs in the Flutter build. The original Sydney project
`tniftazhovxafftqyzbr` was preserved and is not the selected target.

Project creation, an empty public schema and a security advisor result with
no findings were verified. No invoice data, production
database, storage objects or existing users were migrated. An empty project's
advisory result does not qualify the existing backend for production.

## Authentication boundary

Flutter exchanges an email/password for a Supabase access token, then sends
that token to the existing Tevel API's `POST /auth/supabase`. The backend
validates it online with the fixed project's `/auth/v1/user` endpoint. It
requires a confirmed, non-anonymous user and an explicit, operator-managed
`app_metadata.tevel_user_id` containing an existing active Tevel user UUID.

The backend does not infer a link from email or editable `user_metadata`, and
does not create a business or grant ownership from a Supabase login. Tevel's
existing cookie phase, MFA, device-token exchange, business memberships and
authorization remain in force. Supabase tokens are transient in Flutter;
only the existing Tevel device token is stored in Keychain.

Supabase logout or removal of the mapping prevents a new exchange; it does
not revoke existing Tevel sessions/device tokens. Account offboarding must
revoke those in Tevel as well. Account deletion's ACTIVE-user check continues
to prevent the deleted account from signing in.

Native Apple sign-in and legacy email/password authentication remain on their
existing paths. A build with Supabase settings uses Supabase for email/password
only. The legacy invitation/password-reset system is not an Auth user migration.
For Supabase builds, the password-help sheet directs users to support rather
than resetting a different password in Tevel. Self-service Supabase recovery,
invitation onboarding and provider migration require a separate lifecycle flow
before a wider rollout.

## Activation order

1. Choose the first existing Tevel account and verify its production user UUID.
2. Create its Supabase Auth identity directly in Supabase, confirm the email,
   and explicitly set `app_metadata.tevel_user_id` using an authenticated
   operator/admin interface. Passwords must stay outside chat and Git.
3. Deploy the changes in the existing `invoiceproject` backend. Set only these
   public settings for the API service:

   ```sh
   SUPABASE_AUTH_URL=https://lyfojepvxzskyoesbmqx.supabase.co
   SUPABASE_AUTH_PUBLISHABLE_KEY=sb_publishable_BmkATzD42YOWhoT09KG6pw_tqbA7CaL
   ```

4. Verify a real login, MFA and business isolation against the deployed API
   before enabling Supabase in a distributable app. Existing passwords are
   not automatically copied into Supabase. New Supabase identities without
   an operator mapping must receive `NO_LINKED_ACCOUNT`.
5. Build with the guarded release helper after the server/account checks pass:

   ```sh
   export SUPABASE_AUTH_URL=https://lyfojepvxzskyoesbmqx.supabase.co
   export SUPABASE_AUTH_PUBLISHABLE_KEY=sb_publishable_BmkATzD42YOWhoT09KG6pw_tqbA7CaL
   export FLUTTER_BIN=/Users/eyalatiya/flutter/bin/flutter
   /Users/eyalatiya/flutter/bin/dart run tool/build_release.dart
   ```

   Without these settings the helper preserves existing authentication.
   Partial configuration, insecure origins and secret keys are rejected.
   Increment the build number before uploading a new candidate to Apple.

The API/worker run on their existing Oracle host; Supabase hosts Auth. On
2026-11-10, backend commit `b6c6fe3` was deployed through the guarded rollout,
including backup/restore rehearsal and all pending migrations. Postflight
passed 28 checks with zero failures/warnings. API readiness and the worker
were verified; an invalid Supabase token returned HTTP 401.

Signed Build 4 includes this configuration and passed 791 mobile tests plus
two separately configured Auth tests. It remains an internal candidate:
the first Auth user is created, confirmed and explicitly mapped (see below),
but real login remains pending. No TestFlight/App Store upload was performed.

### Account activation verified 2026-11-11

The owner created `eyalatiyawork@gmail.com` privately in Supabase. The confirmed
Auth identity `3c82512e-e306-4082-b547-a5af2621a090` is now linked through
operator-managed `app_metadata.tevel_user_id` to existing ACTIVE, non-demo
Tevel user `b866fb9b-37ce-46b0-a756-b8bcd34f77ea`. The update preserved existing
metadata and refused conflicting mappings. Exactly one identity has this link.
No password was read or changed. Production `/health` and `/ready` returned 200;
unauthenticated `/me` returned 401. The owner must complete an actual app sign-in
before the login/MFA/business-access flow can be marked verified.

Account deletion currently requires the existing Tevel/provider reauthentication
and does not remove the Supabase identity. A Supabase-only password cannot
satisfy that legacy password check. Recovery, deletion and offboarding need a
complete provider lifecycle before this candidate is distributed publicly.

## Verification

- Supabase project's status, public API configuration and security advisors.
- Mobile tests: safe Auth origins, password transport, explicit errors, clean
  token exchange, MFA parsing and signed-out/restoring route rejection.
- Backend unit tests: operator-only mapping, token/provider failures, unsafe
  origins, anonymous/unconfirmed users and refused secret keys.
- Backend HTTP integration tests with the test PostgreSQL database: successful
  mapped exchange, owner MFA enforcement, inactive/demo refusal and JSON-only
  requests. The Supabase transport is injected; these do not claim live login.

The production activation gates in `PRODUCTION-QUALIFICATION.md` still apply.
