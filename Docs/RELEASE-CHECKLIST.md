# Release checklist

Updated 26 November 2026. Build completion is not distribution approval.

## Implemented

- [x] Sanitize the latest three-day plan without changing its exercise selection,
  prescriptions, or rotation; add an image-free minimal example and JSON Schema.
- [x] Use the same JSON for the app starter plan and public example; check for drift.
- [x] Add a plan editor, first-run guidance, explicit metric-unit support, direct
  numeric input, wider measurement ranges, and configurable equipment increments.
- [x] Generic display name/icon; preserve installed personal app identifiers in
  ignored local settings and document public signing configuration.
- [x] Add license/provenance, support, security and contribution documents.
- [x] Preserve assistance, historical bodyweight, exercise IDs, and Health state in backups.
- [x] Reject unsupported versions, duplicate IDs, invalid values, and oversized imports.
- [x] Restore database records using an isolated context with rollback on failure.
  Plans persist first; interrupted cross-store restores can be retried idempotently.
- [x] No writable fallback if the persistent database cannot open.
- [x] Failed plan/photo writes surface errors; failed session/body saves discard
  only the attempted inserts rather than duplicating them on retry.
- [x] Photo deletion waits for successful database save; photo reads are downsampled.
- [x] Remote images off by default; approved library only; redirect checks,
  streaming limits, decoded-pixel limits, a disk budget, and no cache backups.
- [x] Privacy policy in app and repository; truthful device-backup/export descriptions.
- [x] Local erase flow, separate linked-Health deletion choice, protected temporary
  exports, local expiring clipboard, and formula-safe CSV text.
- [x] Optional device authentication, whole-window privacy cover, reduced-motion
  support, and opt-in workout details outside the app.
- [x] Health sync identity metadata/reconciliation, tracked body sample IDs,
  visible workout-deletion failures, and private logging of sensitive errors.
- [x] Remove unsupported calorie-accuracy bounds; retain opt-in estimated-energy writes.
- [x] Add focused checks and CI. Tests use synthetic data only.

## Verify before public source visibility

- [x] Confirm the clean pushed snapshot and all reachable history contain no
  original personal plan, portrait icon, device IDs, raw exports, or secrets.
- [x] Publish from a fresh repository/history rather than making an archive of
  the old private repository public. Rewriting refs alone may leave old GitHub
  objects accessible by SHA; retain the old repository strictly private.
- [x] First CI run passed: native checks, Debug/Release builds, compiled UI target, and all three isolated simulator smoke tests.
- [x] Enable private vulnerability reporting, secret scanning, and push protection on the public repository.
- [x] Add the PolyForm Noncommercial license, Parham Rahimi attribution, and source/asset provenance; code-drawn icon replaces the portrait asset.

## Requires an installed runtime or physical device

The local simulator runtime download was stopped after GitHub CI supplied a
supported runtime and passed the three UI smoke tests. Broader device coverage
below remains open; compilation alone is not a substitute for it.

- [x] CI launched an isolated simulator, passed onboarding, create/select-plan,
  and privacy-default/policy tests, and captured screenshots using synthetic data.
  The existing personal app container was not used. Screenshots were visually
  inspected and saved in `Docs/screenshots/`; the sampled screens are readable.
- [ ] Exercise create/edit/import/replace plans, finish/resume/discard workouts,
  failed saves, and restore of old backups on iOS.
- [ ] Test VoiceOver, large Dynamic Type, contrast, reduced motion, small screens,
  Persian/Gregorian calendars, decimal separators, RTL where supported, week and
  time-zone boundaries; fix any resulting layout or interaction issues.
- [ ] Verify app-switcher covers presented sheets, authentication cancellation,
  optional app lock, disabled widget details, and locked-device behavior.
- [ ] Verify camera/photo permissions, photo save/delete failures, memory use,
  file protection, and deletion while image transfers are in flight.
- [ ] Verify Health permission denial, interrupted writes/backfill deduplication,
  missing/legacy sample links, edit/deletion messages, and deletion retries.
- [ ] Test years of synthetic history, disk-full behavior, long workouts,
  background/resume, timers, notifications, widgets, and Live Activities.

## Requires publisher/account decisions and external review

- [ ] Choose and register production bundle IDs/App Groups and an eligible Apple
  Developer Program membership. Current generic IDs are build defaults, not
  proof that these identifiers are owned or registered.
- [ ] Validate a **signed** Release archive in Xcode/App Store Connect. The local
  unsigned archive verifies compilation and packaging only.
- [ ] Make the privacy policy/support URL publicly reachable, enable private
  security reporting, and review App Store privacy answers against actual
  request handling. No backend analytics or account system is implemented.
- [ ] Review health-data handling, OS-backup behavior, manifests/required-reason
  APIs, publisher identity, age/content declarations, and regional requirements
  for the chosen release. Have qualified reviewers assess these where needed.
- [ ] Have a qualified trainer review the default routine and movement guidance.
  Example content is not an individualized prescription; calorie estimates have
  no measured confidence interval. No clinical validation is claimed.
- [ ] Run a small TestFlight beta, resolve findings, and submit accurate screenshots,
  description, support details, review notes, and release metadata to App Review.

## Deliberate scope

The app remains English/metric and iPhone/iOS 26+. It does not add accounts,
cloud sync, analytics, subscriptions, or encrypted full-photo backup archives.
Training-data backups explicitly exclude photos and optional profile/settings;
users can rely on separately controlled device backups for those. Legacy Health
records without saved links may need removal directly in Health. Local edits
are not mirrored retroactively to Health. Expanding these behaviors requires
new policy, migration, test, and product decisions.

## Validation evidence

[Passing implementation CI run](https://github.com/ParhamRahimi/Workout-Plus-Preparation-Archive/actions/runs/45805126271): 27 data-safety checks, Debug and Release builds, and three isolated simulator UI tests. Plan selection is explicitly asserted before its screenshot. Synthetic screenshots were inspected for readability and saved in `Docs/screenshots/`.

A local unsigned Release archive was also built with generic identifiers and
verified to include the starter plan, both privacy manifests, and matching App
Group keys. Ignored local signing settings were checked to preserve the existing
personal bundle IDs and shared group. No phone app was installed or erased.

The original repository is retained as a private archive. The current repository
was created fresh; its API does not resolve the old personal-history commit.
Keep the archive private. Source publication has been authorized after license and privacy checks. The
public snapshot uses PolyForm Noncommercial 1.0.0 with required author attribution;
pre-publication archives must stay private.

Final privacy cleanup: the publication snapshot uses general content checks,
without embedding statistics or names from the private training history. Prior
preparation history and its validation artifacts are preserved privately.

Licensing update: the public release contains the unmodified PolyForm
Noncommercial License 1.0.0 and a required notice naming Parham Rahimi. Earlier
private snapshots are not offered as part of its public history. Changing terms
does not retroactively revoke rights already granted to recipients of prior
versions. Third-party material retains its original terms.
