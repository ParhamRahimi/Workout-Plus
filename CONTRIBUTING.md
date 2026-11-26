# Contributing

Use synthetic fixtures only. Keep signing overrides and generated artifacts out
of Git. Do not add analytics, image hosts, cloud storage, or SDKs without
reviewing the privacy policy, manifest declarations, consent, and deletion paths.

Run `bash Tools/run_checks.sh` and build the app/widget. Data model changes need
a new frozen versioned schema, a migration stage, and migration coverage. Backup
changes need backward compatibility and round-trip coverage. Failed writes must
not lose data or report success.

Update both the public example and bundled starter JSON together. Keep plan
content free of personal performances, dates, symptoms, and equipment history.
Test meaningful behavior rather than implementation details.

## License and attribution

Original contributions submitted for inclusion must be provided under the
project's PolyForm Noncommercial License 1.0.0. Preserve existing attribution
and add appropriate contributor notices for material you own. Do not import
third-party code unless its terms are compatible and documented. By submitting
a contribution for inclusion, you agree to license that contribution under
these project terms; you retain ownership of your contribution.
