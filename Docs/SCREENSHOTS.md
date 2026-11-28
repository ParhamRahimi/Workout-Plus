# Screenshot gallery

These are unedited PNG captures of the running app on a fresh, isolated iPhone
simulator. All session dates, loads, repetitions, measurements, and notes are
invented by the simulator-only fixture. The exercise plan is the public starter
example. Progress-photo views use drawings labeled **DEMO ILLUSTRATION** and
**NOT A REAL PROGRESS PHOTO**. No personal device records or photographs were
used to generate these images.

The fixture is excluded from physical-device and Release builds, uses an
in-memory training database, disables Health writes and remote image downloads,
and runs under separate test bundle and App Group identifiers. Optional profile
fields remain unset. Workout details in widgets/Live Activities are enabled in
this demonstration; the app defaults them off.

Capture sources: [28 November 2026](https://github.com/ParhamRahimi/Workout-Plus/actions/runs/46111878628)
and [26 November 2026](https://github.com/ParhamRahimi/Workout-Plus/actions/runs/45819272799).
Images 04 and 30 use the earlier capture of the same interface to avoid a
navigation-transition frame and a partly offscreen control. The final gallery
validation passed all seven UI tests; data-safety checks and Debug/Release
app/widget builds also passed.

## Captures

| Screenshot | Surface shown |
| --- | --- |
| [01-workouts](screenshots/features/01-workouts.png) | Plan rotation and next workout |
| [02-plans](screenshots/features/02-plans.png) | Installed plan selection |
| [03-plan-editor](screenshots/features/03-plan-editor.png) | Plan name, description, and rotation editor |
| [04-workout-editor](screenshots/features/04-workout-editor.png) | Workout and exercise order editor |
| [05-exercise-editor](screenshots/features/05-exercise-editor.png) | Exercise prescription and loading options |
| [06-workout-plan](screenshots/features/06-workout-plan.png) | Workout overview before starting |
| [07-active-workout](screenshots/features/07-active-workout.png) | Active workout controls |
| [08-exercise-guide](screenshots/features/08-exercise-guide.png) | Exercise guide with remote images disabled |
| [09-exercise-instructions](screenshots/features/09-exercise-instructions.png) | Technique instructions and tips |
| [10-exercise-substitution](screenshots/features/10-exercise-substitution.png) | Substitution choices and search |
| [11-set-logging](screenshots/features/11-set-logging.png) | Numeric set entry and synthetic progression suggestion |
| [12-set-rest-timer](screenshots/features/12-set-rest-timer.png) | Rest countdown inside set logging |
| [13-workout-rest-timer](screenshots/features/13-workout-rest-timer.png) | Workout rest countdown and completed set indicator |
| [14-finish-confirmation](screenshots/features/14-finish-confirmation.png) | Workout save confirmation |
| [15-saved-demo-workout](screenshots/features/15-saved-demo-workout.png) | Newly saved synthetic session |
| [16-history](screenshots/features/16-history.png) | Synthetic training history |
| [17-session-detail](screenshots/features/17-session-detail.png) | Recorded exercises and sets |
| [18-edit-recorded-set](screenshots/features/18-edit-recorded-set.png) | Recorded set editor |
| [19-measurement-trends](screenshots/features/19-measurement-trends.png) | Invented bodyweight and waist trends |
| [20-exercise-progress](screenshots/features/20-exercise-progress.png) | Exercise progression chart and metric controls |
| [21-weekly-volume](screenshots/features/21-weekly-volume.png) | Weekly volume by muscle |
| [22-progress-summary](screenshots/features/22-progress-summary.png) | Training summary |
| [23-export-options](screenshots/features/23-export-options.png) | CSV export and JSON backup/restore controls |
| [24-synthetic-backup-ready](screenshots/features/24-synthetic-backup-ready.png) | Prepared synthetic JSON backup |
| [25-body-measurements](screenshots/features/25-body-measurements.png) | Invented measurements and illustration thumbnails |
| [26-demo-illustration-viewer](screenshots/features/26-demo-illustration-viewer.png) | Progress image viewer with a labeled illustration |
| [27-demo-photo-comparison](screenshots/features/27-demo-photo-comparison.png) | Comparison of labeled illustrations |
| [28-add-body-entry](screenshots/features/28-add-body-entry.png) | Measurement entry and camera/library controls |
| [29-settings-rest-and-health](screenshots/features/29-settings-rest-and-health.png) | Rest preferences and optional Health controls |
| [30-settings-image-controls](screenshots/features/30-settings-image-controls.png) | Image opt-in and cache controls |
| [31-optional-profile](screenshots/features/31-optional-profile.png) | Unset optional profile fields |
| [32-settings-privacy-and-deletion](screenshots/features/32-settings-privacy-and-deletion.png) | Privacy, authentication, and erase controls |
| [33-privacy-policy](screenshots/features/33-privacy-policy.png) | In-app privacy policy |
| [34-import-plan](screenshots/features/34-import-plan.png) | Plan JSON paste/file import screen |
| [35-create-plan](screenshots/features/35-create-plan.png) | New plan form |
| [36-volume-by-week](screenshots/features/36-volume-by-week.png) | Training volume over time |

The earlier [welcome](screenshots/welcome.png), [plan creation](screenshots/plans.png),
and [privacy controls](screenshots/privacy.png) captures also come from an
isolated synthetic simulator run.

## Coverage limits

This gallery shows the main in-app flows. It does not show home/lock-screen
widgets, the Live Activity/Dynamic Island, delivered notifications, Health
permission or sync results, device authentication, the live camera or system
photo/file/share pickers, or remote image downloads. Backup preparation and
erase/restore controls are shown; the gallery does not demonstrate destructive
erasure or a full restore. Simulator captures do not verify those physical-device
and OS-controlled integrations.

## Reproduce

With an iOS 26+ simulator runtime installed:

```sh
WORKOUT_CAPTURE_GALLERY=1 bash Tools/run_ui_checks.sh
```

Alternatively run **Build and data safety** in GitHub Actions with
`capture_gallery` enabled. The runner creates and removes a separate simulator.
The `gallery-screenshots` artifact contains PNGs and their capture manifest;
`ui-results` contains the full test results. Both expire after seven days.
Review every exported image before copying selected PNGs into this directory;
keep private device backups, identifiers, signing logs, and credentials ignored.
