
import csv
import json
from datetime import datetime
from pathlib import Path
from typing import Any

import dataiku


OUTPUT_DIR = Path("/tmp")
OUTPUT_FILE = OUTPUT_DIR / f"connection_{datetime.now().strftime('%Y%m%d%H%M%S')}.csv"

FIELDNAMES = [
    "connection_name",
    "connection_type",
    "used",
    "usage_count",
    "usages",
    "error",
]

TABLE_COLUMNS = [
    ("connection_name", "CONNECTION"),
    ("connection_type", "TYPE"),
    ("used", "USED"),
    ("usage_count", "COUNT"),
    ("usages", "USAGES"),
    ("error", "ERROR"),
]

MAX_TABLE_WIDTHS = {
    "connection_name": 40,
    "connection_type": 18,
    "used": 5,
    "usage_count": 5,
    "usages": 90,
    "error": 60,
}

PROJECT_SCAN_SPECS = [
    {
        "usage_type": "DATASET",
        "list_method": "list_datasets",
        "get_method": "get_dataset",
        "id_keys": ("name", "datasetName", "id"),
        "list_kwargs": {"as_type": "objects", "include_shared": False},
    },
    {
        "usage_type": "MANAGED_FOLDER",
        "list_method": "list_managed_folders",
        "get_method": "get_managed_folder",
        "id_keys": ("id", "odbId", "folderId", "name"),
        "list_kwargs": {},
    },
    {
        "usage_type": "RECIPE",
        "list_method": "list_recipes",
        "get_method": "get_recipe",
        "id_keys": ("name", "recipeName", "id"),
        "list_kwargs": {"as_type": "objects"},
    },
    {
        "usage_type": "SCENARIO",
        "list_method": "list_scenarios",
        "get_method": "get_scenario",
        "id_keys": ("id", "scenarioId", "name"),
        "list_kwargs": {"as_type": "objects"},
    },
    {
        "usage_type": "SAVED_MODEL",
        "list_method": "list_saved_models",
        "get_method": "get_saved_model",
        "id_keys": ("id", "smId", "name"),
        "list_kwargs": {},
    },
    {
        "usage_type": "MODEL_EVALUATION_STORE",
        "list_method": "list_model_evaluation_stores",
        "get_method": "get_model_evaluation_store",
        "id_keys": ("id", "mesId", "name"),
        "list_kwargs": {},
    },
    {
        "usage_type": "EVALUATION_STORE",
        "list_method": "list_evaluation_stores",
        "get_method": "get_evaluation_store",
        "id_keys": ("id", "evaluationStoreId", "name"),
        "list_kwargs": {},
    },
    {
        "usage_type": "WEBAPP",
        "list_method": "list_webapps",
        "get_method": "get_webapp",
        "id_keys": ("id", "webAppId", "name"),
        "list_kwargs": {},
    },
    {
        "usage_type": "STREAMING_ENDPOINT",
        "list_method": "list_streaming_endpoints",
        "get_method": "get_streaming_endpoint",
        "id_keys": ("id", "streamingEndpointId", "name"),
        "list_kwargs": {},
    },
]


def get_attr_or_key(value: Any, *keys: str) -> Any:
    if isinstance(value, dict):
        for key in keys:
            child = value.get(key)
            if child not in (None, ""):
                return child

    for key in keys:
        if hasattr(value, key):
            child = getattr(value, key)
            if child not in (None, ""):
                return child

    return ""


def to_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, default=str)


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


def get_connection_inventory(client: Any) -> dict[str, dict[str, str]]:
    inventory: dict[str, dict[str, str]] = {}
    connections = client.list_connections(as_type="listitems")

    if isinstance(connections, dict):
        iterable = connections.values()
    else:
        iterable = connections

    for item in iterable:
        name = str(get_attr_or_key(item, "name", "connectionName", "id"))
        connection_type = str(get_attr_or_key(item, "type", "connectionType"))
        if name:
            inventory[name] = {"connection_type": connection_type}

    return inventory


def call_list_method(project: Any, method_name: str, kwargs: dict[str, Any]) -> list[Any]:
    method = getattr(project, method_name, None)
    if method is None:
        return []

    try:
        result = method(**kwargs)
    except TypeError:
        result = method()

    if isinstance(result, dict):
        return list(result.values())
    return list(result or [])


def object_identifier(item: Any, id_keys: tuple[str, ...]) -> str:
    identifier = get_attr_or_key(item, *id_keys)
    if identifier:
        return str(identifier)
    return str(item)


def object_handle(project: Any, item: Any, get_method_name: str, id_keys: tuple[str, ...]) -> Any:
    if not isinstance(item, dict) and (
        hasattr(item, "get_settings") or hasattr(item, "get_definition")
    ):
        return item

    identifier = object_identifier(item, id_keys)
    get_method = getattr(project, get_method_name, None)
    if get_method is None:
        return item
    return get_method(identifier)


def raw_settings(obj: Any) -> Any:
    if hasattr(obj, "get_settings"):
        settings = obj.get_settings()
        if hasattr(settings, "get_raw"):
            return settings.get_raw()
        if hasattr(settings, "settings"):
            return settings.settings

    if hasattr(obj, "get_definition"):
        return obj.get_definition()

    return obj


def find_connection_refs(
    value: Any,
    known_connection_names: set[str],
    path: str = "$",
    connection_context: bool = False,
) -> list[tuple[str, str]]:
    refs: list[tuple[str, str]] = []

    if isinstance(value, dict):
        for key, child in value.items():
            child_path = f"{path}.{key}"
            child_context = connection_context or ("connection" in str(key).lower())
            refs.extend(find_connection_refs(child, known_connection_names, child_path, child_context))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            refs.extend(
                find_connection_refs(child, known_connection_names, f"{path}[{index}]", connection_context)
            )
    elif connection_context and isinstance(value, str) and value in known_connection_names:
        refs.append((value, path))

    return refs


def add_usage(
    usages_by_connection: dict[str, list[dict[str, Any]]],
    connection_name: str,
    usage_type: str,
    project_key: str,
    object_id: str,
    ref_paths: list[str],
) -> None:
    usage = {
        "usage_type": usage_type,
        "project_key": project_key,
        "object_id": object_id,
        "paths": sorted(set(ref_paths)),
    }

    existing = usages_by_connection.setdefault(connection_name, [])
    if usage not in existing:
        existing.append(usage)


def scan_project(
    project: Any,
    project_key: str,
    known_connection_names: set[str],
    usages_by_connection: dict[str, list[dict[str, Any]]],
    scan_errors: list[str],
) -> None:
    for spec in PROJECT_SCAN_SPECS:
        try:
            items = call_list_method(project, spec["list_method"], spec["list_kwargs"])
        except Exception as exc:
            scan_errors.append(f"{project_key}: {spec['list_method']} failed: {exc}")
            continue

        for item in items:
            item_id = object_identifier(item, spec["id_keys"])
            try:
                handle = object_handle(project, item, spec["get_method"], spec["id_keys"])
                settings = raw_settings(handle)
                refs = find_connection_refs(settings, known_connection_names)
            except Exception as exc:
                scan_errors.append(f"{project_key}: {spec['usage_type']} {item_id} failed: {exc}")
                continue

            refs_by_connection: dict[str, list[str]] = {}
            for connection_name, ref_path in refs:
                refs_by_connection.setdefault(connection_name, []).append(ref_path)

            for connection_name, ref_paths in refs_by_connection.items():
                add_usage(
                    usages_by_connection,
                    connection_name,
                    spec["usage_type"],
                    project_key,
                    item_id,
                    ref_paths,
                )


def scan_plugins(
    client: Any,
    known_connection_names: set[str],
    usages_by_connection: dict[str, list[dict[str, Any]]],
    scan_errors: list[str],
) -> None:
    try:
        plugins = client.list_plugins()
    except Exception as exc:
        scan_errors.append(f"list_plugins failed: {exc}")
        return

    for plugin in plugins or []:
        plugin_id = str(get_attr_or_key(plugin, "id", "pluginId", "name"))
        refs_by_connection: dict[str, list[str]] = {}
        for connection_name, ref_path in find_connection_refs(plugin, known_connection_names):
            refs_by_connection.setdefault(connection_name, []).append(ref_path)

        for connection_name, ref_paths in refs_by_connection.items():
            add_usage(
                usages_by_connection,
                connection_name,
                "PLUGIN_METADATA",
                "",
                plugin_id,
                ref_paths,
            )


def build_rows(
    inventory: dict[str, dict[str, str]],
    usages_by_connection: dict[str, list[dict[str, Any]]],
    connection_errors: dict[str, str],
) -> list[dict[str, Any]]:
    rows = []

    for connection_name in sorted(inventory, key=str.lower):
        usages = sorted(
            usages_by_connection.get(connection_name, []),
            key=lambda item: (
                item.get("usage_type", ""),
                item.get("project_key", ""),
                item.get("object_id", ""),
            ),
        )
        rows.append(
            {
                "connection_name": connection_name,
                "connection_type": inventory[connection_name].get("connection_type", ""),
                "used": bool(usages),
                "usage_count": len(usages),
                "usages": to_json(usages),
                "error": connection_errors.get(connection_name, ""),
            }
        )

    return rows


def main() -> None:
    client = dataiku.api_client()
    connection_errors: dict[str, str] = {}
    scan_errors: list[str] = []

    inventory = get_connection_inventory(client)
    known_connection_names = set(inventory)
    usages_by_connection = {name: [] for name in known_connection_names}

    try:
        project_keys = client.list_project_keys()
    except Exception as exc:
        project_keys = []
        scan_errors.append(f"list_project_keys failed: {exc}")

    for project_key in project_keys:
        try:
            project = client.get_project(project_key)
        except Exception as exc:
            scan_errors.append(f"{project_key}: get_project failed: {exc}")
            continue

        scan_project(project, project_key, known_connection_names, usages_by_connection, scan_errors)

    scan_plugins(client, known_connection_names, usages_by_connection, scan_errors)

    rows = build_rows(inventory, usages_by_connection, connection_errors)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    with OUTPUT_FILE.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} row(s) to {OUTPUT_FILE}")
    print_table(rows)

    if scan_errors:
        print()
        print("Scan warnings:")
        for error in scan_errors:
            print(f"  - {error}")


if __name__ == "__main__":
    main()
