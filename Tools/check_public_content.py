#!/usr/bin/env python3
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Copyright (c) 2026 Parham Rahimi
# See LICENSE and NOTICE for license terms and required attribution.

"""Fail closed on common personal-data/credential patterns in public plan assets."""
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[1]
patterns = [r"0000[0-9A-Fa-f]{4}-[0-9A-Fa-f]{16}", r"/Users/", r"(?i)you hit|you broke|your (?:previous|recent|logs|discomfort|switch|available|best|existing)|the movement you described|yours uses", r"\b\d{2}-\d{2}\b", r"(?i)median duration|completed working sets per session|your \d+ (?:usable )?session logs", r"(?i)start \d+(?:\.\d+)? kg", r"github_pat_|gh[pousr]_[A-Za-z0-9]{20,}|-----BEGIN .*PRIVATE KEY"]
plans = [root / 'Examples/minimal-plan.json', root / 'Examples/three-day-full-body.json', root / 'Workout Plus/starter-plan.json']
for path in plans:
    content = path.read_text()
    json.loads(content)
    for pattern in patterns:
        assert not re.search(pattern, content), f'Personal or sensitive content in {path.relative_to(root)}'
assert plans[1].read_bytes() == plans[2].read_bytes(), 'Starter plan has drifted from the public example'
print('Public plan content checks passed')
