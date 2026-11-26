#!/usr/bin/env python3
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Copyright (c) 2026 Parham Rahimi
# See LICENSE and NOTICE for license terms and required attribution.

"""
Standalone plan-to-PDF exporter for Workout Plus.

Not part of the Xcode project on purpose: `Workout Plus/` and `WorkoutPlusWidget/`
are Xcode-synchronized groups, so any .swift (or stray) file dropped in there
gets compiled into a target automatically. This script lives in `Tools/`,
outside both, and never touches the app build.

Purpose: turn the plan JSON (the same file imported by hand through the app's
Import Plan screen) into a printable/offline PDF, so there's a paper/PDF
backup of the plan that doesn't depend on the app being installed.

Usage:
    python3 Tools/plan_to_pdf.py [path/to/plan.json] [-o output.pdf]

Requires: Python 3 stdlib + WeasyPrint (already installed on this Mac via
Homebrew: `brew install weasyprint`). No paid tools, no Xcode involved.
"""
import argparse
import base64
import hashlib
import html
import json
import mimetypes
import sys
import urllib.request
from pathlib import Path

# Same category -> color mapping as Models.swift's `categoryColor`, so the
# PDF reads consistently with the app. Hex values are Apple's standard
# system-color palette (light mode).
CATEGORY_COLORS = {
    "legs": "#5856D6",
    "back": "#007AFF",
    "chest": "#FF3B30",
    "shoulders": "#FF9500",
    "arms": "#AF52DE",
    "core": "#30B0C7",
    "posture": "#34C759",
    "upper back": "#34C759",
    "forearms": "#A2845E",
    "calves": "#00C7BE",
    "grip": "#32ADE6",
    "mobility": "#FFCC00",
    "posterior chain": "#FF2D55",
}
DEFAULT_CATEGORY_COLOR = "#8E8E93"


def category_color(category: str) -> str:
    return CATEGORY_COLORS.get((category or "").strip().lower(), DEFAULT_CATEGORY_COLOR)


def fetch_image_data_uri(url: str, cache_dir: Path) -> str | None:
    """Download an exercise photo and inline it as a data: URI, so the PDF
    is self-contained forever after and doesn't depend on GitHub's raw
    endpoint staying up. Cached on disk so re-running the script offline
    (after the first successful run) still works."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha1(url.encode("utf-8")).hexdigest()
    cached = list(cache_dir.glob(key + ".*"))
    if cached:
        data = cached[0].read_bytes()
        mime = mimetypes.guess_type(cached[0].name)[0] or "image/jpeg"
        return f"data:{mime};base64,{base64.b64encode(data).decode('ascii')}"

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "workout-plus-pdf-export/1.0"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = resp.read()
            mime = resp.headers.get_content_type() or "image/jpeg"
    except Exception as e:
        print(f"warning: couldn't fetch image {url}: {e}", file=sys.stderr)
        return None

    ext = mimetypes.guess_extension(mime) or ".jpg"
    (cache_dir / f"{key}{ext}").write_bytes(data)
    return f"data:{mime};base64,{base64.b64encode(data).decode('ascii')}"


def load_plan(path: Path) -> dict:
    raw = path.read_bytes()
    # This specific file has a few stray bytes before the opening '{'
    # (looks like leftover IME keystrokes) - strip anything before it so
    # a plain json.loads doesn't choke.
    text = raw.decode("utf-8", errors="replace")
    brace = text.find("{")
    if brace == -1:
        raise ValueError(f"No JSON object found in {path}")
    if brace != 0:
        print(f"note: stripped {brace} stray character(s) before '{{' in {path.name}", file=sys.stderr)
    return json.loads(text[brace:])


def esc(value) -> str:
    return html.escape(str(value), quote=False)


def rep_range(ex: dict) -> str:
    low, high = ex.get("repRangeLow"), ex.get("repRangeHigh")
    unit = "sec" if ex.get("isTimed") else "reps"
    if low == high:
        return f"{low} {unit}"
    return f"{low}-{high} {unit}"


def badges(ex: dict) -> str:
    tags = []
    if ex.get("isBodyweight"):
        tags.append("bodyweight")
    if ex.get("isAssisted"):
        tags.append("assisted")
    if ex.get("supersetGroup"):
        tags.append(f"superset: {ex['supersetGroup']}")
    if not tags:
        return ""
    spans = "".join(f'<span class="badge">{esc(t)}</span>' for t in tags)
    return f'<div class="badges">{spans}</div>'


def image_row(ex: dict, cache_dir: Path) -> str:
    uris = [
        fetch_image_data_uri(url, cache_dir)
        for url in ex.get("imageURLs", [])[:2]
    ]
    uris = [u for u in uris if u]
    if not uris:
        return ""
    imgs = "".join(f'<img src="{u}" alt="">' for u in uris)
    return f'<div class="ex-images">{imgs}</div>'


def exercise_block(ex: dict, index: int, cache_dir: Path) -> str:
    steps = "".join(f"<li>{esc(s)}</li>" for s in ex.get("steps", []))
    feel = ex.get("feel")
    tip = ex.get("tip")
    color = category_color(ex.get("category", ""))
    notes = ""
    if feel:
        notes += f'<p class="feel"><strong>Feel:</strong> {esc(feel)}</p>'
    if tip:
        notes += f'<p class="tip"><strong>Tip:</strong> {esc(tip)}</p>'
    return f"""
    <div class="exercise" style="border-left-color: {color};">
      <div class="ex-head">
        <span class="ex-num" style="background: {color};">{index}</span>
        <span class="ex-name">{esc(ex['name'])}</span>
        <span class="ex-category" style="background: {color};">{esc(ex.get('category', ''))}</span>
      </div>
      <div class="ex-sets">{ex.get('sets', '?')} sets &times; {rep_range(ex)}</div>
      {badges(ex)}
      {image_row(ex, cache_dir)}
      <ol class="steps">{steps}</ol>
      {notes}
      <div class="log-row">
        <span>Set weights logged:</span>
        <span class="blank"></span>
      </div>
    </div>
    """


def workout_section(workout: dict, cache_dir: Path) -> str:
    exercises = "".join(
        exercise_block(ex, i + 1, cache_dir) for i, ex in enumerate(workout.get("exercises", []))
    )
    return f"""
    <section class="workout">
      <h2>{esc(workout['name'])}</h2>
      <p class="focus">{esc(workout.get('focus', ''))}</p>
      {exercises}
    </section>
    """


def build_html(plan: dict, cache_dir: Path) -> str:
    rotation = " → ".join(plan.get("rotation", []))
    workouts = "".join(workout_section(w, cache_dir) for w in plan.get("workouts", []))
    return f"""<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>{esc(plan.get('name', 'Workout Plan'))}</title>
<style>
  @page {{
    size: A4;
    margin: 1.6cm 1.4cm;
    @bottom-center {{
      content: "Workout Plus — offline backup";
      font-size: 8pt;
      color: #888;
    }}
  }}
  * {{ box-sizing: border-box; }}
  body {{
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
    color: #1a1a1a;
    font-size: 10.5pt;
    line-height: 1.45;
  }}
  h1 {{
    font-size: 20pt;
    margin: 0 0 4pt 0;
    color: #007AFF;
  }}
  .summary {{
    font-size: 9.5pt;
    color: #333;
    background: #F0F6FF;
    border-left: 3pt solid #007AFF;
    border-radius: 6pt;
    padding: 10pt 12pt;
    margin-bottom: 6pt;
  }}
  .meta {{
    font-size: 9pt;
    color: #555;
    margin-bottom: 14pt;
  }}
  .workout {{
    page-break-before: always;
  }}
  .workout:first-of-type {{
    page-break-before: avoid;
  }}
  h2 {{
    font-size: 15pt;
    color: #1a1a1a;
    border-bottom: 2pt solid #007AFF;
    padding-bottom: 3pt;
    margin-bottom: 2pt;
  }}
  .focus {{
    font-size: 9.5pt;
    font-style: italic;
    color: #444;
    margin-top: 0;
    margin-bottom: 12pt;
  }}
  .exercise {{
    border: 0.75pt solid #ddd;
    border-left: 4pt solid #ccc;
    border-radius: 5pt;
    padding: 8pt 10pt;
    margin-bottom: 8pt;
    page-break-inside: avoid;
  }}
  .ex-head {{
    display: flex;
    align-items: baseline;
    gap: 6pt;
  }}
  .ex-num {{
    display: inline-block;
    width: 16pt;
    height: 16pt;
    line-height: 16pt;
    text-align: center;
    border-radius: 50%;
    background: #1a1a1a;
    color: #fff;
    font-size: 8.5pt;
    flex-shrink: 0;
  }}
  .ex-name {{
    font-weight: bold;
    font-size: 11.5pt;
    flex-grow: 1;
  }}
  .ex-category {{
    font-size: 8.5pt;
    text-transform: uppercase;
    letter-spacing: 0.3pt;
    color: #fff;
    border-radius: 8pt;
    padding: 1pt 8pt;
  }}
  .ex-sets {{
    font-size: 10pt;
    font-weight: 600;
    margin: 3pt 0 4pt 22pt;
  }}
  .badges {{
    margin: 0 0 4pt 22pt;
  }}
  .badge {{
    display: inline-block;
    font-size: 7.5pt;
    background: #eee;
    border-radius: 6pt;
    padding: 1pt 6pt;
    margin-right: 4pt;
    color: #555;
  }}
  .ex-images {{
    margin: 4pt 0 4pt 22pt;
    display: flex;
    gap: 6pt;
  }}
  .ex-images img {{
    height: 105pt;
    width: auto;
    border-radius: 4pt;
    border: 0.5pt solid #ddd;
    object-fit: cover;
  }}
  .steps {{
    margin: 4pt 0 4pt 34pt;
    padding: 0;
    font-size: 9.3pt;
  }}
  .steps li {{
    margin-bottom: 2pt;
  }}
  .feel, .tip {{
    margin: 3pt 0 0 22pt;
    font-size: 9pt;
    color: #333;
  }}
  .tip {{
    color: #444;
  }}
  .log-row {{
    margin: 6pt 0 0 22pt;
    font-size: 8.5pt;
    color: #777;
    display: flex;
    align-items: center;
    gap: 6pt;
  }}
  .log-row .blank {{
    flex-grow: 1;
    border-bottom: 0.5pt dotted #aaa;
    height: 10pt;
  }}
</style>
</head>
<body>
  <h1>{esc(plan.get('name', 'Workout Plan'))}</h1>
  <div class="meta">{plan.get('daysPerWeek', '?')} days/week &middot; rotation {esc(rotation)}</div>
  <div class="summary">{esc(plan.get('summary', ''))}</div>
  {workouts}
</body>
</html>
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "plan_json",
        nargs="?",
        default=str(Path(__file__).resolve().parent.parent / "Examples" / "three-day-full-body.json"),
        help="Path to the plan JSON (defaults to the active plan in the app target)",
    )
    parser.add_argument("-o", "--output", default=None, help="Output PDF path")
    args = parser.parse_args()

    plan_path = Path(args.plan_json)
    plan = load_plan(plan_path)

    # Default output lives in Tools/, never next to the JSON: that JSON sits
    # inside the app's Xcode-synchronized source group, and anything dropped
    # there gets bundled into the app target automatically.
    default_out = Path(__file__).resolve().parent / (plan_path.stem + ".pdf")
    out_path = Path(args.output) if args.output else default_out

    cache_dir = Path(__file__).resolve().parent / ".image_cache"
    doc_html = build_html(plan, cache_dir)

    try:
        from weasyprint import HTML
        HTML(string=doc_html, base_url=str(plan_path.parent)).write_pdf(str(out_path))
        print(f"Wrote {out_path}")
        return
    except ImportError:
        pass

    # `pip install weasyprint` and `brew install weasyprint` can land in
    # different Python environments, so the import above can fail even when
    # the CLI (installed by Homebrew) works fine. Fall back to shelling out.
    import shutil
    import subprocess
    import tempfile

    weasyprint_cli = shutil.which("weasyprint")
    if weasyprint_cli:
        with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as f:
            f.write(doc_html)
            tmp_html = f.name
        try:
            subprocess.run([weasyprint_cli, tmp_html, str(out_path)], check=True)
            print(f"Wrote {out_path}")
        finally:
            Path(tmp_html).unlink(missing_ok=True)
        return

    html_fallback = out_path.with_suffix(".html")
    html_fallback.write_text(doc_html, encoding="utf-8")
    print(
        "WeasyPrint isn't installed, so I wrote the HTML instead:\n"
        f"  {html_fallback}\n"
        "Open it in a browser and use File > Export as PDF (or Cmd+P > Save as PDF).\n"
        "Or install WeasyPrint for a one-command PDF: brew install weasyprint",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
