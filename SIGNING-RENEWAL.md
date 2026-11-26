# Renew Workout Plus signing

A free Apple Developer account's provisioning profile expires seven days after
issuance. Rebuilding with the same profile does not reset its expiration date.

You can run this a day or two before expiration. A new profile is needed;
reinstalling with the old profile keeps the old deadline.

## Build and install with one command

Connect and unlock your iPhone, quit Xcode, and run this in Terminal from the repository
folder:

```bash
python3 Tools/renew_signing_profiles.py --install YOUR_IPHONE_UDID
```

To save the default device for this checkout, create `Tools/signing.local.json`:

```json
{"iphone_udid": "YOUR_IPHONE_UDID", "team_id": "YOUR_TEAM_ID", "bundle_id": "com.example.workoutplus"}
```

Use the same team and bundle ID as `Config/Signing.local.xcconfig`.
This file is ignored by Git. With it configured, `--install` needs no value.
To use another iPhone, pass an override:

```bash
python3 Tools/renew_signing_profiles.py --install OTHER_IPHONE_UDID
```

Your Apple account must already be signed in under
**Xcode → Settings → Apple Accounts** (called **Accounts** in older versions).
The Mac needs internet access, and the iPhone must trust it and have Developer
Mode enabled, as for a normal Xcode run.

The script backs up the cached app and widget profiles, builds in a new temporary
directory with automatic provisioning updates, and checks the profiles embedded
in the result. It installs over the existing app only if **both** profiles have
at least six days remaining and later deadlines than the matching cached
profiles, if any were found. It prints the earliest app/widget deadline after
installation. Open the app afterward to refresh its expiry reminder.

If Apple/Xcode returns an old profile, the script exits with an error before
installation. Clearing the cache requests a new profile; it cannot change an
Apple-signed expiration date itself. No certificates are revoked, bundle IDs
changed, or apps uninstalled. Updating over the existing app preserves its data.

On failure or interruption, the script copies backed-up profiles to any original
cache paths that are still missing, leaving any new downloads in place. For
**HTTP 403**, **Unable to log in**, or signing-account failures, follow the
[account and network recovery steps in README.md](README.md#if-renewal-fails-with-http-403-or-unable-to-log-in)
before retrying. A script cannot renew profiles while Apple refuses Xcode's
account requests.

## Refresh profiles, then build in Xcode

1. Quit Xcode.
2. Open Terminal in this project's root folder and run:

   ```bash
   python3 Tools/renew_signing_profiles.py
   ```

   The script moves only this team's Workout Plus app and widget profiles out of
   Xcode's cache into a temporary backup directory. It prints the backup location
   and leaves other apps' profiles and signing certificates alone.

3. Reopen `Workout Plus.xcodeproj` in Xcode.
4. Ensure **Automatically manage signing** is enabled for both the **Workout Plus**
   and **WorkoutPlusWidget** targets, with your usual team selected.
5. Select the **Workout Plus** scheme and your **physical iPhone** as the destination.
6. Press **Command-R** to request profiles, build, and install the app.
7. In the iPhone app, open **Settings → App signing → Expires** and confirm that
   the deadline has moved forward.

Using Build alone or choosing a simulator does not update the app on your iPhone.
Install over the existing app; there is no need to delete it or its workout data.

To see which profiles the script would move without changing anything:

```bash
python3 Tools/renew_signing_profiles.py --dry-run
```

The script checks the current Xcode profile location
(`~/Library/Developer/Xcode/UserData/Provisioning Profiles`) and the older location
(`~/Library/MobileDevice/Provisioning Profiles`).

The printed temporary backup directory includes `restore-paths.json`, which maps
each backed-up file to its original location. To undo the cache cleanup, quit
Xcode and copy the backed-up profiles to those original paths. Temporary backups
and build output may be removed by macOS; retain a copy if you need them longer.

To check a built app's actual signing window without changing anything:

```bash
python3 Tools/renew_signing_profiles.py --verify '/path/to/Workout Plus.app'
```

This check requires at least six days left on both the app and widget profiles.
It checks the files on the Mac; it does not inspect the installed iPhone app.

Apple documents the seven-day lifetime in its
[developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account).
Apple also documents clearing cached profiles under
[Configuring Xcode to request new provisioning profiles for automatic signing](https://developer.apple.com/help/account/provisioning-profiles/edit-download-or-delete-profiles/).
For the Xcode 27 interface, see Apple's instructions for
[opening Device Hub](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)
and [locating device identifiers](https://developer.apple.com/documentation/xcode/locating-device-identifiers).
