#!/usr/bin/env python3
"""
Check Dataiku project params.json files for recipeEnginesPreferences values.

By default this scans every params.json under:
  data/dataiku/dss_data/config/projects/<project-name>/...

Statuses:
  EMPTY      recipeEnginesPreferences exists and all nested values are empty
  NOT_EMPTY  recipeEnginesPreferences exists and at least one nested value is set
  ERROR      params.json could not be read or parsed
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


DEFAULT_PROJECTS_ROOT = Path("data/dataiku/dss_data/config/projects")
PREFERENCE_KEY = "recipeEnginesPreferences"

FIELDNAMES = [
    "project_key",
    "params_scope",
    "params_path",
    "preference_path",
    "status",
    "empty",
    "non_empty_paths",
    "top_level_summary",
    "error",
]

TABLE_COLUMNS = [
    ("project_key", "PROJECT"),
    ("params_scope", "SCOPE"),
    ("status", "STATUS"),
    ("preference_path", "PREFERENCE_PATH"),
    ("non_empty_paths", "NON_EMPTY_PATHS"),
    ("error", "ERROR"),
]

MAX_TABLE_WIDTHS = {
    "project_key": 28,
    "params_scope": 45,
    "status": 9,
    "preference_path": 45,
    "non_empty_paths": 70,
    "error": 60,
}


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def project_parts(projects_root: Path, params_path: Path) -> tuple[str, str]:
    rel_path = params_path.relative_to(projects_root)
    parts = rel_path.parts
    project_key = parts[0] if parts else ""

    if len(parts) == 2 and parts[1] == "params.json":
        return project_key, "."

    return project_key, str(Path(*parts[1:-1])) if len(parts) > 2 else "."


def iter_params_files(projects_root: Path, project_root_only: bool) -> list[Path]:
    if not projects_root.is_dir():
        raise FileNotFoundError(f"Projects root not found: {projects_root}")

    if project_root_only:
        params_files = [path / "params.json" for path in projects_root.iterdir() if path.is_dir()]
        return sorted(path for path in params_files if path.is_file())

    return sorted(projects_root.rglob("params.json"))


def find_key_occurrences(value: Any, wanted_key: str, path: str = "$") -> list[tuple[str, Any]]:
    occurrences: list[tuple[str, Any]] = []

    if isinstance(value, dict):
        for key, child in value.items():
            child_path = f"{path}.{key}"
            if key == wanted_key:
                occurrences.append((child_path, child))
            occurrences.extend(find_key_occurrences(child, wanted_key, child_path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            occurrences.extend(find_key_occurrences(child, wanted_key, f"{path}[{index}]"))

    return occurrences


def is_empty_value(value: Any) -> bool:
    if value is None:
        return True
    if isinstance(value, str):
        return value.strip() == ""
    if isinstance(value, (list, tuple, set)):
        return all(is_empty_value(item) for item in value)
    if isinstance(value, dict):
        return all(is_empty_value(child) for child in value.values())
    return False


def find_non_empty_paths(value: Any, path: str = "$") -> list[str]:
    if is_empty_value(value):
        return []

    if isinstance(value, dict):
        paths: list[str] = []
        for key, child in value.items():
            paths.extend(find_non_empty_paths(child, f"{path}.{key}"))
        return paths or [path]

    if isinstance(value, list):
        paths = []
        for index, child in enumerate(value):
            paths.extend(find_non_empty_paths(child, f"{path}[{index}]"))
        return paths or [path]

    return [path]


def summarize_top_level(value: Any) -> str:
    if not isinstance(value, dict):
        return f"$={json.dumps(value, ensure_ascii=False, default=str)}"

    parts = []
    for key in sorted(value):
        child = value[key]
        if is_empty_value(child):
            parts.append(f"{key}=empty")
        else:
            parts.append(f"{key}=not_empty")
    return "; ".join(parts)


def table_value(value: Any) -> str:
    if isinstance(value, bool):
        return "YES" if value else "NO"
    return "" if value is None else str(value)


def truncate(value: str, width: int) -> str:
    if len(value) <= width:
        return value
    if width <= 3:
        return value[:width]
    return value[: width - 3] + "..."


def print_table(rows: list[dict[str, Any]]) -> None:
    if not rows:
        print("No rows matched the selected filters.")
        return

    widths = {}
    for key, header in TABLE_COLUMNS:
        max_value_width = max(len(table_value(row.get(key, ""))) for row in rows)
        widths[key] = min(max(len(header), max_value_width), MAX_TABLE_WIDTHS[key])

    header = " | ".join(header.ljust(widths[key]) for key, header in TABLE_COLUMNS)
    separator = "-+-".join("-" * widths[key] for key, _ in TABLE_COLUMNS)
    print(header)
    print(separator)

    for row in rows:
        print(
            " | ".join(
                truncate(table_value(row.get(key, "")), widths[key]).ljust(widths[key])
                for key, _ in TABLE_COLUMNS
            )
        )


def build_rows(projects_root: Path, params_files: list[Path]) -> list[dict[str, Any]]:
    rows = []

    for params_path in params_files:
        project_key, params_scope = project_parts(projects_root, params_path)
        rel_params_path = str(params_path.relative_to(projects_root))

        try:
            data = load_json(params_path)
        except (OSError, json.JSONDecodeError) as exc:
            rows.append(
                {
                    "project_key": project_key,
                    "params_scope": params_scope,
                    "params_path": rel_params_path,
                    "preference_path": "",
                    "status": "ERROR",
                    "empty": "",
                    "non_empty_paths": "",
                    "top_level_summary": "",
                    "error": str(exc),
                }
            )
            continue

        occurrences = find_key_occurrences(data, PREFERENCE_KEY)
        for preference_path, preference_value in occurrences:
            non_empty_paths = find_non_empty_paths(preference_value, preference_path)
            empty = not non_empty_paths
            rows.append(
                {
                    "project_key": project_key,
                    "params_scope": params_scope,
                    "params_path": rel_params_path,
                    "preference_path": preference_path,
                    "status": "EMPTY" if empty else "NOT_EMPTY",
                    "empty": empty,
                    "non_empty_paths": ", ".join(non_empty_paths),
                    "top_level_summary": summarize_top_level(preference_value),
                    "error": "",
                }
            )

    return rows


def default_output_path() -> Path:
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    return Path(f"recipe_engine_preferences_{timestamp}.csv")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check recipeEnginesPreferences in Dataiku project params.json files."
    )
    parser.add_argument(
        "--projects-root",
        type=Path,
        default=DEFAULT_PROJECTS_ROOT,
        help=f"Projects root to scan. Default: {DEFAULT_PROJECTS_ROOT}",
    )
    parser.add_argument(
        "--project-root-only",
        action="store_true",
        help="Only scan <project>/params.json files, not nested params.json files.",
    )
    parser.add_argument(
        "--only-problems",
        action="store_true",
        help="Only display NOT_EMPTY and ERROR rows.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        nargs="?",
        const=default_output_path(),
        help="Write a CSV report. If no path is supplied, a timestamped filename is used.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        params_files = iter_params_files(args.projects_root, args.project_root_only)
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    rows = build_rows(args.projects_root, params_files)
    display_rows = [row for row in rows if row["status"] != "EMPTY"] if args.only_problems else rows

    status_counts = {}
    for row in rows:
        status_counts[row["status"]] = status_counts.get(row["status"], 0) + 1

    print(
        f"Scanned {len(params_files)} params.json file(s). "
        f"Found {len(rows)} recipeEnginesPreferences occurrence(s). "
        f"EMPTY={status_counts.get('EMPTY', 0)} "
        f"NOT_EMPTY={status_counts.get('NOT_EMPTY', 0)} "
        f"ERROR={status_counts.get('ERROR', 0)}"
    )
    print()
    print_table(display_rows)

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=FIELDNAMES)
            writer.writeheader()
            writer.writerows(rows)
        print()
        print(f"Wrote CSV report to {args.output}")

    return 1 if status_counts.get("ERROR", 0) else 0


if __name__ == "__main__":
    raise SystemExit(main())
