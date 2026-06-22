
import csv
import json
from datetime import datetime
from pathlib import Path
from typing import Any

import dataiku


OUTPUT_DIR = Path("/tmp")
OUTPUT_FILE = OUTPUT_DIR / f"code_env_{datetime.now().strftime('%Y%m%d%H%M%S')}.csv"

FIELDNAMES = [
    "env_name",
    "env_lang",
    "python_version",
    "python_interpreter",
    "used",
    "usage_count",
    "usages",
    "error",
]

TABLE_COLUMNS = [
    ("env_name", "ENV_NAME"),
    ("env_lang", "LANG"),
    ("python_version", "PYTHON"),
    ("python_interpreter", "INTERPRETER"),
    ("used", "USED"),
    ("usage_count", "COUNT"),
    ("usages", "USAGES"),
    ("error", "ERROR"),
]

MAX_TABLE_WIDTHS = {
    "env_name": 45,
    "env_lang": 8,
    "python_version": 8,
    "python_interpreter": 14,
    "used": 5,
    "usage_count": 5,
    "usages": 80,
    "error": 60,
}


def get_first(data: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        value = data.get(key)
        if value not in (None, ""):
            return value
    return ""


def find_value_by_key(value: Any, wanted_keys: set[str]) -> Any:
    if isinstance(value, dict):
        for key, child in value.items():
            if key in wanted_keys and child not in (None, ""):
                return child
        for child in value.values():
            found = find_value_by_key(child, wanted_keys)
            if found not in (None, ""):
                return found
    elif isinstance(value, list):
        for child in value:
            found = find_value_by_key(child, wanted_keys)
            if found not in (None, ""):
                return found
    return ""


def to_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, default=str)


def normalize_python_version(interpreter: Any) -> str:
    value = str(interpreter or "").strip().upper()
    if not value.startswith("PYTHON"):
        return str(interpreter or "")

    digits = value.replace("PYTHON", "")
    if len(digits) == 2:
        return f"{digits[0]}.{digits[1]}"
    if len(digits) == 3:
        return f"{digits[0]}.{digits[1:]}"
    return value


def get_python_interpreter(env_info: dict[str, Any], code_env: Any) -> str:
    interpreter = find_value_by_key(
        env_info,
        {
            "pythonInterpreter",
            "resolvedPythonInterpreter",
            "basePythonInterpreter",
        },
    )
    if interpreter:
        return str(interpreter)

    try:
        settings = code_env.get_settings()
        settings_data = getattr(settings, "settings", {})
    except Exception:
        return ""

    return str(
        find_value_by_key(
            settings_data,
            {
                "pythonInterpreter",
                "resolvedPythonInterpreter",
                "basePythonInterpreter",
            },
        )
    )


def format_usages(usages: list[dict[str, Any]]) -> str:
    usage_items = []
    for usage in usages:
        usage_items.append(
            {
                "usage_type": usage.get("envUsage", ""),
                "project_key": usage.get("projectKey", ""),
                "object_id": usage.get("objectId", ""),
            }
        )
    return to_json(usage_items)


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
        print("No rows to display.")
        return

    widths = {}
    for key, header in TABLE_COLUMNS:
        max_value_width = max(len(table_value(row.get(key, ""))) for row in rows)
        widths[key] = min(max(len(header), max_value_width), MAX_TABLE_WIDTHS[key])

    header = " | ".join(header.ljust(widths[key]) for key, header in TABLE_COLUMNS)
    separator = "-+-".join("-" * widths[key] for key, _ in TABLE_COLUMNS)
    print()
    print(header)
    print(separator)

    for row in rows:
        print(
            " | ".join(
                truncate(table_value(row.get(key, "")), widths[key]).ljust(widths[key])
                for key, _ in TABLE_COLUMNS
            )
        )


def main() -> None:
    client = dataiku.api_client()
    rows_written = 0
    output_rows: list[dict[str, Any]] = []

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    with OUTPUT_FILE.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES)
        writer.writeheader()

        for env_info in client.list_code_envs():
            env_name = get_first(env_info, "envName", "name")
            env_lang = get_first(env_info, "envLang", "language")

            if str(env_lang).upper() != "PYTHON":
                continue

            base_row = {
                "env_name": env_name,
                "env_lang": env_lang,
            }

            try:
                code_env = client.get_code_env(env_lang, env_name)
                python_interpreter = get_python_interpreter(env_info, code_env)
                python_version = normalize_python_version(python_interpreter)
                usages = code_env.list_usages() or []
            except Exception as exc:
                row = {
                    **base_row,
                    "python_version": "",
                    "python_interpreter": "",
                    "used": "",
                    "usage_count": "",
                    "usages": "[]",
                    "error": str(exc),
                }
                writer.writerow(row)
                output_rows.append(row)
                rows_written += 1
                continue

            if not usages:
                row = {
                    **base_row,
                    "python_version": python_version,
                    "python_interpreter": python_interpreter,
                    "used": False,
                    "usage_count": 0,
                    "usages": "[]",
                    "error": "",
                }
                writer.writerow(row)
                output_rows.append(row)
                rows_written += 1
                continue

            row = {
                **base_row,
                "python_version": python_version,
                "python_interpreter": python_interpreter,
                "used": True,
                "usage_count": len(usages),
                "usages": format_usages(usages),
                "error": "",
            }
            writer.writerow(row)
            output_rows.append(row)
            rows_written += 1

    print(f"Wrote {rows_written} row(s) to {OUTPUT_FILE}")
    print_table(output_rows)


if __name__ == "__main__":
    main()
