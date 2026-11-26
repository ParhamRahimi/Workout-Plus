#!/bin/bash
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Copyright (c) 2026 Parham Rahimi
# See LICENSE and NOTICE for license terms and required attribution.

set -euo pipefail
cd "$(dirname "$0")/.."
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c 'import sys,json; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and ".iOS-" in x["identifier"] and int(x["version"].split(".")[0])>=26]; assert r, "Install an iOS 26+ simulator runtime in Xcode first"; print(r[-1]["identifier"])')
DEVICE_TYPE=$(xcrun simctl list devicetypes -j | python3 -c 'import sys,json; d=[x for x in json.load(sys.stdin)["devicetypes"] if "iPhone" in x["name"] and "Pro" in x["name"]]; print(d[-1]["identifier"])')
QA_DEVICE=$(xcrun simctl create 'Workout Plus isolated QA' "$DEVICE_TYPE" "$RUNTIME")
trap 'xcrun simctl shutdown "$QA_DEVICE" >/dev/null 2>&1 || true; xcrun simctl delete "$QA_DEVICE" >/dev/null 2>&1 || true' EXIT
mkdir -p TestResults
RESULTS="TestResults/UI-$(date +%Y%m%d-%H%M%S).xcresult"
if [[ "${WORKOUT_CAPTURE_GALLERY:-0}" == "1" ]]; then
  TEST_SUITE=WorkoutPlusUITests/FeatureGalleryTests
else
  TEST_SUITE=WorkoutPlusUITests/WorkoutPlusUITests
fi
xcodebuild -project 'Workout Plus.xcodeproj' -scheme 'Workout Plus' -configuration Debug \
  -destination "platform=iOS Simulator,id=$QA_DEVICE" -resultBundlePath "$RESULTS" -only-testing:"$TEST_SUITE" \
  CODE_SIGNING_ALLOWED=NO WORKOUT_DEVELOPMENT_TEAM= \
  WORKOUT_BUNDLE_IDENTIFIER=org.workoutplus.qa WORKOUT_APP_GROUP=group.org.workoutplus.qa test
xcrun xcresulttool export attachments --path "$RESULTS" --output-path "${RESULTS%.xcresult}-attachments"
