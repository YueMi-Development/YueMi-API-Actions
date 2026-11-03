#!/usr/bin/env python3
"""Validate a GitHub Actions action.yml file."""

import argparse
import sys

try:
    import yaml
except ImportError as exc:
    raise SystemExit("PyYAML is required: pip install pyyaml") from exc


def validate(path: str) -> int:
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f)
    except FileNotFoundError:
        print(f"Error: {path} not found", file=sys.stderr)
        return 1
    except yaml.YAMLError as exc:
        print(f"Error: {path} is not valid YAML:\n{exc}", file=sys.stderr)
        return 1

    if not isinstance(data, dict):
        print(f"Error: {path} root must be a mapping", file=sys.stderr)
        return 1

    if "name" not in data or "runs" not in data:
        print(f"Error: {path} is missing required 'name' or 'runs' key", file=sys.stderr)
        return 1

    print(f"{path} is valid")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Validate a GitHub Actions action.yml file")
    parser.add_argument("path", nargs="?", default="action.yml", help="Path to action.yml")
    args = parser.parse_args()
    sys.exit(validate(args.path))
