# Widget and Live Activities

The project already contains and embeds the `WorkoutPlusWidget` extension.
Both targets compile the shared snapshot and Activity attributes. App Groups
and bundle identifiers come from `Config/Project.xcconfig`; device-specific
settings belong in ignored `Config/Signing.local.xcconfig`.

Workout details outside the app are off by default. Enabling them publishes a
small shared snapshot; the extension never opens the SwiftData database.
Disable the setting to clear displayed details and end Live Activities.
