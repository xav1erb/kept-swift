# M6 — CONTRACTS: Check-in engine + notifications

<!-- APPROVED by Xavier 2026-07-25 — all four §9 questions ruled (§10). Sources: whitepaper
     §13/§14/§16/§19, C10 (APPROACH.md), F10/F12 rulings, M4 §2 (checkInArmed handoff), M5 §8
     deferrals, supabase/README.md:65 (the server-plaintext ruling, closed here),
     docs/PROVISIONING.md item 3. -->

## 1. Scope

**In (the vertical):** the check-in engine end to end — client publishes content-free schedule
rows → pg_cron + Edge Function dispatch APNs push (F12 generic copy) → tap deep-links through
the Router into the owning chapter → the check-in question materializes in chapter chat → the
reply files through the one pipeline (C1). Plus: device-token registration, the local tiny-task
reminder engine (Reminder CRUD + quiet hours + per-reminder exemptions), notification-prefs
setter commands (consumed here, UI at M7), the contextual pre-permission re-ask at the arming
moment, awareness decay as a client scheduled write, and the cron ops README (born the day the
first job is wired, C10).

**Out:** monthly recap letter + its push (M8) · streak nudge (M7, with the streak page) ·
milestone unlocks (M7) · prefs/reminders UI (M7 profile) · paywall trigger on first check-in
answer (M8) · exact-content lock-screen opt-in (mechanism ruled here in §9.2, ships M7) ·
`/acknowledge` (stays deferred; replies are `/chat`'s job) · the in-app "Pom asks" solicitation
cluster (§9.4 rules its fate).

**Hard gate (👤):** live push needs PROVISIONING item 3 (APNs auth key + `aps-environment`
entitlement — the affirmly silent-403 lesson). Everything below builds and tests headless;
device-verify (§8.11) waits on the key.

## 2. The alarm-clock architecture (C2 × C10)

The tension this package resolves: C10 says check-ins are server-driven; C2 says the server
holds ciphertext only. The resolution: **the server owns WHEN, never WHAT.**

- The **client is the scheduler-of-record.** At arm/pin/foreground it computes desired
  check-ins from store state × prefs — quiet hours, frequency tier, and timezone math all run
  on device, so **prefs never leave the phone either.**
- The server holds an **alarm-row table** (`scheduled_checkins`, §4.1): `user_id, fire_at,
  kind, chapter_id`. No titles, no bodies, no valence, no prefs. A chapter UUID is opaque; the
  server learns only "this user has a moment on Tuesday at 09:00."
- **pg_cron is a dumb alarm clock:** every 5 minutes, fire due rows → APNs with a fixed
  generic line per kind + the deep-link route → delete the row. Zero content, zero AI.
- **Reconciliation, not messaging:** `desiredCheckIns(store, prefs, now)` is a pure function;
  the client diffs its output against the server's rows and upserts/deletes. Row ids are
  deterministic (UUIDv5 of eventId+kind) so the pass is idempotent and self-healing — a missed
  network call is repaired at next foreground.
- **C10 amendment (ratified with §9.1):** "decay" leaves the server-driven list. Awareness
  lives inside ciphertext; the server cannot compute it. Awareness decay becomes a **client
  scheduled write at app-foreground/day-close** (C6: computed at write, deterministic rule from
  `docs/extraction.md`). C10's graduate text becomes: *"the server drives timing (push); content
  and derived numbers are computed client-side or in flight — never at rest on the server."*
  The M8 recap letter fits the same split (server pushes "it's ready"; generation is a
  client-initiated proxy call, plaintext in flight only).

## 3. Data-model amendments

- `Event.checkInAskedAt: Date?` — stamped when the materialized question lands in chapter chat
  (§6); dedupes the ask and disarms (`checkInArmed → false`). Blob-carried, tolerant decode,
  envelope version unchanged (additive — the M4 pattern).
- `Reminder` gets its command surface (model exists since M0, restore-only until now):
  `createReminder(chapterId:title:schedule:) -> UUID`, `setReminderEnabled(id:enabled:)`,
  `deleteReminder(id:)`, `reminders() -> [ReminderSnapshot]` (new snapshot). **No surveillance
  tasks:** reminders are title+schedule rows only — there is no field a "check his followers
  weekly" watcher could live in (§19, structural).
- `NotificationPrefs` setters: `setCheckInFrequency(_:)`, `setQuietHours(startMinute:endMinute:)`
  (minutes-past-midnight, window may wrap midnight; nil/nil clears), `setReminderExemption(id:exempt:)`,
  `setGenericLockScreenCopy(_:)`. Defaults unchanged: `.moderate`, generic ON (F12), quiet hours
  nil until the user sets them (M7 UI).
- `CheckInKind: String Codable enum { postEvent, eventMorning }` — **structurally, there is no
  kind that isn't anchored to a stored event.** A schedule-less "we miss you" ping cannot be
  expressed (§19, never-test asserts the case list).

## 4. Server contracts

### 4.1 Migration — `scheduled_checkins`
`id uuid PK` (client-computed UUIDv5) · `user_id` FK auth.users ON DELETE CASCADE ·
`fire_at timestamptz` · `kind text CHECK (kind in ('postEvent','eventMorning'))` ·
`chapter_id uuid` · `created_at`. RLS owner-only for the client; service-role reads for
dispatch. `revoke all from anon`. Sign-out deletes the user's rows + device tokens (client
command); account deletion cascades.

### 4.2 Dispatch — pg_cron + `checkin-dispatch` Edge Function
- Job `checkin-dispatch-5min` (`*/5 * * * *`): invokes the function with the service key.
- The function: select rows `fire_at <= now()` → join `device_push_tokens` → APNs HTTP/2
  (ES256 JWT from `APNS_KEY_P8`/`APNS_KEY_ID`/`APNS_TEAM_ID` secrets; `apns-push-type: alert`;
  sandbox/production per token row) → delete fired rows (at-most-once; a failed send logs and
  deletes — a check-in is a courtesy, never a retry-storm).
- **Payload is typed and content-free by construction:** `{aps: {alert: {title, body}},
  route: "kept://chapter/<uuid>"}` where title/body come ONLY from the per-kind copy bank
  (§4.3). The payload builder's input type has no field an event title could enter through
  (C3 structural; keyless Deno test).
- **Log contract (C2, code-reviewed):** row counts, kinds, token counts, APNs status codes,
  timing. Never `chapter_id`→user correlation beyond what dispatch requires, never copy text
  interpolated with anything, no content fields exist to leak.
- `scripts/deploy-checkin.sh` mirrors the existing deploy scripts; `verify_jwt` stays ON for
  any client-facing path (dispatch itself is service-role, cron-invoked).

### 4.3 Push copy bank (⚠ copy review)
Fixed strings per kind, in-repo, guilt-scanned by a Deno never-test AND mirrored in the Swift
scan list: `postEvent` → title "Pom 🤍", body "thinking about how it went — whenever you're
ready." · `eventMorning` → body "Pom is thinking about tonight 🤍". Generic by default (F12);
no name, no event title, no question counts, ever, at this layer — exact content is
architecturally impossible server-side, not just configured off.

### 4.4 Cron ops README — `supabase/cron/README.md`
Born in this milestone with the first wired job: registry table (job name · schedule ·
function · wired date · verified date) + a post-mortems section (the affirmly device-token
incident is the standing cautionary tale).

## 5. Client notification layer

- **Token registration:** `UIApplicationDelegateAdaptor` lands in `KeptApp` for
  `didRegisterForRemoteNotifications`; token upserts via `BackendServicing.registerDeviceToken
  (token:environment:)` on launch-when-authorized + post-sign-in. Sign-out revokes.
- **Tap routing (C8):** `UNUserNotificationCenterDelegate` reads `userInfo["route"]` →
  `Router.open(deepLink:)` — the one navigation door; unknown routes refused loudly. Works
  cold and warm start (device-verify).
- **Frequency tiers (typed mapping, C4):** `importantOnly` → `postEvent` only · `moderate` →
  + `eventMorning`, ≤3 pushes/week total (client drops lowest-priority rows when the cap hits)
  · `daily` → both kinds, uncapped. **No tier generates an event-less ping.**
- **Fire-time math (pure, golden-tested):** `postEvent` → next calendar day 09:00 local;
  `eventMorning` → event day 09:00 local, skipped when the event is before 10:00; a computed
  time inside the quiet window shifts to window end. Timezone changes repair at next reconcile.
- **Local reminders (C10 local path):** `LocalReminderScheduler` behind a protocol (fake in
  tests) building `UNCalendarNotificationTrigger` requests from `ReminderSchedule`. Quiet
  hours are OUR logic (AGENTS.md tripwire): non-exempt reminders inside the window deliver at
  `.passive` interruption level (present quietly, never wake the screen); exempt reminders use
  `.timeSensitive` (entitlement noted for device-verify). The user's chosen time is never
  silently moved. `content.badge` is never set (§19 — no badges, for anything).
- **Pre-permission re-ask (whitepaper §16):** one contextual moment — completing prep with
  notifications undetermined/denied shows our soft card ("so I can ask how it went — that's
  the whole point of me") before/instead of the system prompt; at most once per session, never
  a second ask, never blocks prep completion. Copy ⚠.
- **Awareness decay sweep:** deterministic client write at app-foreground applying the
  `docs/extraction.md` decay rule to stale chapters (C6: stored at write; views only read).

## 6. The in-app moment (push is transport, not truth)

The check-in exists in the STORE, not in the notification. When a chapter opens (or the app
foregrounds into it) with `checkInArmed && event.date < now && checkInAskedAt == nil`, the
client appends Pom's question to the chapter chat as a **typed template line** (per-kind copy
bank, ⚠) via the existing `appendChatMessage`, stamps `checkInAskedAt`, disarms. So:

- **No permission, no push, airplane mode — the check-in still happens** the moment she opens
  the chapter. The push only shortens the distance.
- The reply is an ordinary utterance → queue + `/chat` (C1 — no second write path).
- Asked exactly once, never re-raised (never-test); folded/quarantine rules of M4 untouched.
- The M5 vent smart prompt keeps doing its job unchanged; answering in either surface is fine —
  the vent path already files by C1, and the ask-once stamp only governs the chat materialization.

## 7. Softness enforcement (structural, per C3)

- No guilt copy: both push and in-app check-in banks join the Swift source scan; the server
  bank gets the same list in Deno. The M2 forbidden list extends with "you haven't", "overdue",
  "streak is about to", "last chance".
- No badges: no code path sets `content.badge` or the app icon badge (source scan).
- No timers on reconciliation, no countdowns: `scheduled_checkins` has no user-visible
  surface; nothing renders a "time since" anywhere in M6 (type design — no field to render).
- No event-less pings: `CheckInKind` case-list never-test (§3).
- No surveillance reminders: `Reminder` field-set never-test (§3).
- Sensitive chapters: check-ins for grief/privateCorner chapters use the generic push copy
  ALWAYS (even under a future exact-content opt-in) — carried as a rule in §9.2's mechanism.

## 8. Acceptance (M6 done =)

1. Arming prep for a pinned "talk tonight" publishes exactly one `postEvent` row at next-day
   09:00 local (fake backend records; timezone + quiet-hours goldens).
2. The reconcile pass is idempotent and self-healing: re-run produces no duplicates; unpinning
   or disarming deletes the row; a dropped network call repairs at next foreground.
3. Keyless Deno: dispatch selects due rows, builds the exact generic payload (golden), the
   payload type admits no content field, copy bank passes the guilt scan.
4. A push tap with `route` deep-links into the owning chapter through `Router.open` (fake
   center → routed, unknown route refused).
5. Opening the chapter post-event materializes Pom's question once — with no push and no
   notification permission — stamps `checkInAskedAt`, disarms, and the reply enqueues through
   the utterance queue (C1). Re-open never re-asks.
6. Reminder CRUD + scheduler goldens: correct triggers per `ReminderSchedule`, non-exempt
   in-window → `.passive`, exempt → `.timeSensitive`, disable cancels the pending request,
   `badge` never set.
7. Frequency mapping goldens incl. the moderate weekly cap; `importantOnly` still always gets
   `postEvent`; no kind exists without an owning event (never-test).
8. F12: prefs default generic ON; the payload builder can only emit bank strings.
9. All §7 never-tests green; the extended guilt scan covers the new client + server banks.
10. Blob round-trip: `checkInAskedAt`, `Reminder`, prefs survive seal → restore (tolerant
    decode on the new field).
11. **Device-verify checklist (👤, needs APNs key):** sandbox push arrives next-morning for a
    real armed event on a confirmed build number · lock-screen shows generic copy only · tap
    routes correctly from cold AND warm start · quiet-hours `.passive` delivery verified ·
    a real reminder fires · time-sensitive entitlement present · re-ask moment shows once ·
    sign-out leaves no token row.

## 9. Open questions (Xavier rules; answers recorded in §10)

1. **Server-plaintext metadata shape** (closes `supabase/README.md:65`): content-free alarm
   rows written by the client (§2 — prefs stay on device, server owns WHEN never WHAT, C10
   decay amendment included)? Or a richer mirror (server-side scheduling logic over event-date
   metadata)? Or encrypted schedule payloads now?
2. **Exact-content mechanism (F12 opt-in):** ship generic-only in M6 and commit now to the
   Notification Service Extension path for M7 (push stays generic in flight; the NSE decrypts
   locally and rewrites the banner — plaintext never stored server-side, permanently closing
   the "upload the phrase" door)? Or build the NSE inside M6? Or drop the opt-in entirely?
3. **The in-app moment:** materialize the check-in question in the owning chapter chat (§6,
   push-independent)? Or push-only (vent smart prompt remains the only in-app echo)? Or
   materialize into the vent sheet instead?
4. **The deferred "Pom asks in-app" cluster** (followupQueue world-idle ask surface — F10,
   still unbuilt; the global "questions Pom is holding" affordance + wider disambiguation
   surfaces from M5 §8; cached model phrases from M3/M5): keep M6 the notification vertical
   and move the whole cluster to M7 rows? Or pull part/all into M6?

## 10. Rulings (Xavier, 2026-07-25)

1. **Content-free alarm rows.** The client is scheduler-of-record; fire times computed from
   events × prefs on device; the server holds only `{fire_at, kind, chapter-uuid}` rows and
   deletes them after firing. Prefs never leave the phone. **C10 amended as drafted in §2:**
   the server drives timing; content and derived numbers (incl. awareness decay, now a client
   scheduled write) are computed client-side or in flight, never at rest on the server.
2. **Generic now, NSE path committed.** M6 ships the generic-only copy bank (F12 default ON).
   Exact-content opt-in arrives at M7 via a Notification Service Extension that decrypts
   locally and rewrites the banner — the plaintext-upload door is permanently closed, and
   sensitive chapters stay generic even under the opt-in.
3. **Materialize in chapter chat.** The check-in is stored truth; the push is transport.
   Opening the chapter post-event appends Pom's typed question once (`checkInAskedAt` stamps,
   disarms) — works with no permission/push; the reply files through C1.
4. **All to M7 — M6 stays the notification vertical.** The followupQueue world-idle ask
   surface (F10), the global "questions Pom is holding" affordance + wider disambiguation
   surfaces, and cached model phrases become dated M7 rows with the profile/prefs UI.
