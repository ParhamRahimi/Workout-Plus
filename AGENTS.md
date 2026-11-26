# Agent instructions for Workout Plus

## Public repository and private data

- This repository is public. Treat every pushed file, commit, screenshot, log,
  issue attachment, and CI artifact as publicly readable.
- Never publish real workout history, exact personal loads or measurements,
  progress photos, health/profile details, personal plan commentary, device IDs,
  private email addresses, signing material, credentials, or local file paths.
  The author name Parham Rahimi and public GitHub identity are intentional attribution.
- Use clearly synthetic fixtures and explicitly marked demo illustrations in
  screenshots and tests. Never derive demo values or images from the user's
  records, exports, photo library, or private backups.
- Never replace or erase personal device data to obtain screenshots. Prefer a
  fresh simulator with separate identifiers. Any demo mode must be isolated from
  real persistence and Health; simulator-only debug fixtures are preferred.
- Keep local signing overrides, private exports, audits, device logs, test output,
  and backups ignored. `.gitignore` is filename filtering, not a privacy scanner.
  Check new filenames and file contents; never force-add private files.
- Inspect the staged diff and all new assets before committing or pushing. Run
  the public-content check, but remember it covers sample plans only. Secret
  scanning does not recognize arbitrary fitness details or photographs; CI runs
  after a push and cannot undo an exposure.

## Git history and collaboration

- Xcode and agents can use this same working tree. Preserve user edits; review
  status/diffs first. Use normal incremental commits and pushes to the intended
  branch. Preserve honest authorship and dates; never invent past activity.
- Never reset/squash/rewrite public history, force-push, replace/recreate/rename
  repositories, or publish private archive history merely for routine cleanup.
  Explain any exceptional need and obtain explicit authorization first.
- This checkout may contain private recovery refs under `refs/local-backups/`
  and internal agent refs. NEVER use `git push --mirror`, push recovery refs, or
  merge private archive history into a public branch. Push only the intended branch.
- Keep all archival repositories private. Do not change visibility without an
  explicit user request naming the intended repository/audience.
- Keep PolyForm Noncommercial 1.0.0, its unmodified LICENSE, NOTICE, required
  Parham Rahimi attribution, and separately licensed third-party notices.

## App behavior, updates, and device safety

- Clearly describe visible UI changes, removals, changed defaults, and behavior
  changes. Do not describe feature changes as just repository/privacy cleanup.
  Separate proposed UX changes from bug fixes and avoid unrelated redesigns.
- Before installing a data-model update over the personal phone app, create and
  verify a local backup of its app container if device tooling permits. Keep it
  outside tracked source in a protected, ignored location. Stop rather than
  uninstalling, resetting, or overwriting records if backup/migration checks fail.
- Preserve the existing personal bundle ID, App Group, signing team, and data
  container through ignored local settings. Never change these for convenience.
  Install updates over the existing app; do not uninstall it to resolve signing.
- Keep current versioned model schemas frozen. Add a new schema/migration for
  persisted changes and test real prior model definitions with synthetic data.
- JSON training backups exclude photos and optional profile/settings. Do not
  claim they are full device backups. Never silently ignore save/restore/erase errors.
- Health, authentication, lock-screen details, and image downloads are optional.
  Never seed fake data into real Health or enable syncing while creating demos.
- Run checks appropriate to the actual changes. Distinguish compilation, simulator
  smoke tests, signed device installs, and broader physical-device validation.
  Do not claim coverage for features that were not exercised.

## Reports and screenshots

- Use Markdown for reports. If a PDF is requested, preserve the Markdown source
  and convert that same file with `md2pdf`; inspect the PDF for readable tables,
  complete plots, and sensible pagination.
- Review each screenshot visually before publication. Maintain a capture index
  listing screens covered, synthetic-data provenance, and any features that could
  not be captured. Do not pass mockups off as screenshots of the running app.
