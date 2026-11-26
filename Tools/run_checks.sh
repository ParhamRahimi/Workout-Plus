#!/bin/bash
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Copyright (c) 2026 Parham Rahimi
# See LICENSE and NOTICE for license terms and required attribution.

set -euo pipefail
cd "$(dirname "$0")/.."
CHECK_DIR=$(mktemp -d /private/tmp/workout-plus-checks.XXXXXX)
trap 'rm -rf "$CHECK_DIR"' EXIT
xcrun swiftc -parse-as-library -default-isolation MainActor \
  'Workout Plus/Models/Models.swift' 'Workout Plus/Data/CategoryMap.swift' \
  Tests/Legacy/Writer.swift -module-cache-path "$CHECK_DIR/modules" -o "$CHECK_DIR/legacy"
"$CHECK_DIR/legacy" "$CHECK_DIR/previous.store"
mkdir -p "$CHECK_DIR/runtime"
export TMPDIR="$CHECK_DIR/runtime/"
export WORKOUT_CHECK_DIR="$CHECK_DIR"
export WORKOUT_LEGACY_STORE="$CHECK_DIR/previous.store"
xcrun swiftc -parse-as-library -default-isolation MainActor \
  'Workout Plus/Models/Models.swift' 'Workout Plus/Models/LogModels.swift' \
  'Workout Plus/Models/BodyStat.swift' 'Workout Plus/Data/CategoryMap.swift' \
  'Workout Plus/Data/PlanValidation.swift' 'Workout Plus/Data/SeedData.swift' \
  'Workout Plus/Data/PlanStore.swift' 'Workout Plus/Data/BackupService.swift' \
  'Workout Plus/Data/ExportService.swift' 'Workout Plus/Data/Schema.swift' \
  'Workout Plus/Data/Log.swift' 'Workout Plus/Data/PrivateFiles.swift' 'Workout Plus/Data/PRService.swift' 'Workout Plus/Models/DraftSet.swift' Tests/RunChecks.swift \
  -module-cache-path "$CHECK_DIR/modules" -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks"
python3 Tools/check_public_content.py
