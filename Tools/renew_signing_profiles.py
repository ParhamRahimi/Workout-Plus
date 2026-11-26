#!/usr/bin/env python3
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Copyright (c) 2026 Parham Rahimi
# See LICENSE and NOTICE for license terms and required attribution.

"""Refresh Workout Plus signing, optionally rebuilding and installing on an iPhone."""

import argparse
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile


# Keep the default device identifier local to this checkout.
LOCAL_CONFIG = Path(__file__).with_name("signing.local.json")
SETTINGS = json.loads(LOCAL_CONFIG.read_text()) if LOCAL_CONFIG.exists() else {}
IPHONE_UDID = SETTINGS.get("iphone_udid", "")
TEAM_ID = SETTINGS.get("team_id", "")
BUNDLE_ID = SETTINGS.get("bundle_id", "org.workoutplus.app")
APP_IDS = {f"{TEAM_ID}.{BUNDLE_ID}", f"{TEAM_ID}.{BUNDLE_ID}.WorkoutPlusWidget"}
PROFILE_FOLDERS = [
    Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
    Path.home() / "Library/MobileDevice/Provisioning Profiles",
]
PROJECT_ROOT = Path(__file__).resolve().parents[1]
MIN_REMAINING = timedelta(days=6)


def read_profile(path):
    """Read profile metadata without importing certificates into the keychain."""
    data = path.read_bytes()
    start, end = data.find(b"<?xml"), data.rfind(b"</plist>")
    if start >= 0 and end > start:
        # Apple embeds an XML plist in these CMS containers. Reading it directly
        # also works when security cms cannot access the keychain (e.g. a sandbox).
        # Xcode and iOS validate signatures when building/installing the app.
        return plistlib.loads(data[start:end + len(b"</plist>")])
    result = subprocess.run(
        ["/usr/bin/security", "cms", "-D", "-i", str(path)],
        check=True, capture_output=True,
    )
    return plistlib.loads(result.stdout)


def expiration(profile):
    value = profile["ExpirationDate"]
    # plistlib returns naive UTC dates on the macOS system Python.
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value


def format_date(value):
    return value.astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")


def cached_profiles():
    matches = []
    for folder in PROFILE_FOLDERS:
        for path in sorted(folder.glob("*.mobileprovision")):
            try:
                profile = read_profile(path)
            except (OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
                print(f"Warning: cannot decode {path}: {error}", file=sys.stderr)
                continue
            if profile.get("Entitlements", {}).get("application-identifier") in APP_IDS:
                matches.append((path, profile))
    return matches


def verify_app(app, previous=None):
    """Reject a successful build that still carries an old signing deadline."""
    bundles = [app] + sorted((app / "PlugIns").glob("*.appex"))
    seen = set()
    deadlines = []
    for bundle in bundles:
        profile = read_profile(bundle / "embedded.mobileprovision")
        app_id = profile.get("Entitlements", {}).get("application-identifier")
        if app_id not in APP_IDS:
            raise RuntimeError(f"Unexpected signing identity in {bundle}: {app_id}")
        seen.add(app_id)
        expires = expiration(profile)
        print(f"{bundle.name} expires: {format_date(expires)}", flush=True)
        if expires - datetime.now(timezone.utc) < MIN_REMAINING:
            raise RuntimeError(
                f"{bundle.name} has less than six days left. Apple/Xcode did not "
                "provide a fresh signing window. The deadline has not been reset."
            )
        if previous and app_id in previous and expires <= previous[app_id]:
            raise RuntimeError(
                f"{bundle.name} did not get a later expiry than its cached profile. "
                "The deadline has not been reset."
            )
        deadlines.append(expires)
    if seen != APP_IDS:
        raise RuntimeError("The build is missing the app or widget signing profile.")
    return min(deadlines)


def build_and_install(device, previous, backup):
    # An isolated output directory prevents an old signed .app being installed.
    derived = Path(tempfile.mkdtemp(prefix="workout-plus-renew-build-"))
    print("Build output:", derived, flush=True)
    if backup:
        print("Original cached profiles remain backed up in:", backup, flush=True)
    subprocess.run([
        "xcrun", "xcodebuild",
        "-project", str(PROJECT_ROOT / "Workout Plus.xcodeproj"),
        "-scheme", "Workout Plus", "-configuration", "Debug",
        "-destination", f"platform=iOS,id={device}",
        "-derivedDataPath", str(derived),
        "-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration",
        "build",
    ], check=True, cwd=PROJECT_ROOT)
    app = derived / "Build/Products/Debug-iphoneos/Workout Plus.app"
    deadline = verify_app(app, previous)
    # Install over the existing app; never uninstall it or change its bundle ID.
    subprocess.run([
        "xcrun", "devicectl", "device", "install", "app",
        "--device", device, str(app), "--timeout", "120",
    ], check=True)
    print(f"Installed. Earliest app/widget expiry: {format_date(deadline)}")
    print("Open Workout Plus on your iPhone to refresh its expiry reminder.")


def restore_cached_profiles(backup):
    """Recover missing cache files after failure, keeping any new downloads."""
    manifest = backup / "restore-paths.json"
    if not manifest.exists():
        return
    for saved, original in json.loads(manifest.read_text()).items():
        saved, original = Path(saved), Path(original)
        if not saved.is_file() or original.exists():
            continue
        try:
            original.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(saved, original)
            print("Restored cached profile:", original, flush=True)
        except OSError as error:
            print(f"Could not restore {original}: {error}. Backup: {saved}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="List matching profiles without moving them.")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--install", nargs="?", const=IPHONE_UDID, metavar="IPHONE_UDID",
        help="Build, verify a later expiry, and install on the configured iPhone; optionally override its UDID.",
    )
    mode.add_argument("--verify", type=Path, metavar="APP_PATH", help="Check that a built .app and its widget have at least six days left; change nothing.")
    args = parser.parse_args()

    if args.verify:
        if args.dry_run:
            parser.error("--verify is already read-only; omit --dry-run")
        deadline = verify_app(args.verify)
        print(f"Verified. Earliest app/widget expiry: {format_date(deadline)}")
        return

    if args.install == "":
        parser.error("Pass --install IPHONE_UDID or configure Tools/signing.local.json")

    if not TEAM_ID:
        parser.error("Configure team_id and bundle_id in Tools/signing.local.json before renewing profiles")

    matches = cached_profiles()
    if args.dry_run:
        for path, profile in matches:
            print(f"Would back up: {path} (expires {format_date(expiration(profile))})")
        if not matches:
            print("No cached Workout Plus profiles found.")
        if args.install:
            print(f"Would build with automatic provisioning, verify expiry, and install on {args.install}.")
        return

    previous = {}
    for _, profile in matches:
        app_id = profile["Entitlements"]["application-identifier"]
        previous[app_id] = max(expiration(profile), previous.get(app_id, expiration(profile)))
    backup = None
    try:
        if matches:
            backup = Path(tempfile.mkdtemp(prefix="workout-plus-profiles-"))
            # Persist recovery paths before moving anything, including partial failures.
            manifest = {str(backup / str(i) / path.name): str(path) for i, (path, _) in enumerate(matches)}
            (backup / "restore-paths.json").write_text(json.dumps(manifest, indent=2) + "\n")
            print("Backup directory:", backup, flush=True)
            for index, (path, _) in enumerate(matches):
                destination = backup / str(index)
                destination.mkdir()
                shutil.move(str(path), str(destination / path.name))
                print("Removed cached profile:", path, flush=True)
        else:
            print("No cached Workout Plus profiles found.", flush=True)

        if args.install:
            build_and_install(args.install, previous, backup)
            return
    except (Exception, KeyboardInterrupt):
        if backup:
            try:
                restore_cached_profiles(backup)
            except (OSError, ValueError) as error:
                print(f"Could not read recovery paths: {error}. Backup: {backup}", file=sys.stderr)
        raise

    print("Reopen Xcode, select your physical iPhone, and press Command-R.")
    print("Check Settings > App signing > Expires in the app to confirm the new deadline.")
    print("Clearing the cache alone does not renew or reinstall the app.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Renewal failed: {error}", file=sys.stderr)
        print("No app was uninstalled. A build/expiry check failure prevents installation.", file=sys.stderr)
        sys.exit(1)
