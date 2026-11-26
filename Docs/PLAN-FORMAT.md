# Workout plan JSON format

Start by copying [minimal-plan.json](../Examples/minimal-plan.json). Import it
from the Plans screen. JSON does not support comments: put general instructions
in `summary`, `steps`, or `tip`. Do not put personal training history into a plan
that you intend to share.

A plan describes what to do. A backup contains what someone actually did and
may include private notes, dates, measurements, and Apple Health identifiers.
Never use a training-data backup as a public sample.

| Field | Meaning |
| --- | --- |
| `id` | Stable plan ID, 1–100 characters; importing the same ID replaces that plan after confirmation. |
| `name` | Display name, 1–200 characters. |
| `summary` | General plan description; up to 8000 characters. |
| `daysPerWeek` | Integer 1–7; a scheduling suggestion. |
| `rotation` | Ordered workout IDs, up to 100 entries; empty uses workout order. |
| `workouts` | Array of 1–14 workouts. |

Each workout requires `id`, `name`, `focus`, and `exercises`. Workout IDs must be
unique within a plan. Each workout contains 1–40 exercises.

Each exercise requires these fields:

| Field | Meaning |
| --- | --- |
| `name`, `category` | Display name and grouping; nonempty. |
| `sets` | Integer 1–20. |
| `repRangeLow`, `repRangeHigh` | Ordered positive targets, up to 1000 repetitions or 3600 seconds. |
| `isTimed` | If true, targets are seconds rather than repetitions. |
| `imageURLs` | Array, which can be empty; at most eight approved HTTPS image URLs. |
| `feel` | General muscle-effort description; may be empty. |
| `steps` | Up to 20 instruction strings; may be empty. |
| `tip` | General technique note; may be empty. |

Optional fields:

- `id`: stable exercise slot identity. Keep it when renaming an exercise. Names
  are used as fallback identities for older plans. Exercise IDs are local to a workout.
- `supersetGroup`: adjacent exercises with the same label are a superset.
- `isBodyweight`: explicitly says whether load is relative to bodyweight;
  recommended rather than relying on an English exercise-name heuristic.
- `isAssisted`: default assisted loading for the exercise. Each recorded set can
  override it. Assistance is help subtracted from bodyweight, not added load.
- `restSeconds`: integer 0–1800; absent uses a target-based default.
- `weightIncrementKg`: number greater than 0 and at most 50; the available
  equipment increment. It is a suggestion, not a requirement to increase load.

Targets and stored loads use metric units. For dumbbells, choose a consistent
per-dumbbell or combined convention and state it in a general tip. Do not mix
machine loads between different equipment designs.

Only URLs under
`https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/`
are supported. Credentials, query strings, fragments, custom ports, redirects
to other hosts, and other image providers are rejected. Leave `imageURLs: []`
for an image-free plan. Downloading still requires enabling remote images in
Settings. An imported plan never starts a download automatically.

Plan files and pasted JSON are limited to 2 MB. Installed plans are limited to
100; training-data backups have a separate 32 MB limit. Unknown optional fields
are currently ignored. Use [plan.schema.json](../Examples/plan.schema.json) for
editor assistance and the app validator for the final check.

The example three-day plan is also copied to `Workout Plus/starter-plan.json`.
When changing it, update both files; `Tools/run_checks.sh` verifies equality.
