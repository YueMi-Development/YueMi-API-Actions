#!/usr/bin/env python3
"""Validate the GitHub Actions action.yml manifests in this repository."""

import argparse
import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError as exc:
    raise SystemExit("PyYAML is required: pip install pyyaml") from exc

MANIFEST_NAMES = ("action.yml", "action.yaml")
SKIPPED_DIRS = {".git", "node_modules", "dist", "build", ".venv", "venv", "__pycache__"}
OUTPUT_STEP_REF = re.compile(r"\$\{\{\s*steps\.([A-Za-z0-9_-]+)\.outputs\.([A-Za-z0-9_-]+)\s*\}\}")


def repo_root() -> Path:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        result = None
    if result and result.returncode == 0 and result.stdout.strip():
        return Path(result.stdout.strip()).resolve()
    return Path(__file__).resolve().parents[2]


def discover_actions(root: Path) -> list[Path]:
    found: list[Path] = []
    for path in root.rglob("*"):
        if path.name not in MANIFEST_NAMES or not path.is_file():
            continue
        if any(part in SKIPPED_DIRS for part in path.relative_to(root).parts[:-1]):
            continue
        found.append(path)
    return sorted(found)


def validate_composite(runs: dict, errors: list[str]) -> None:
    using = runs.get("using")
    if not using:
        errors.append("'runs.using' is missing")
        return
    if using != "composite":
        return

    steps = runs.get("steps")
    if not isinstance(steps, list) or not steps:
        errors.append("'runs.steps' must be a non-empty list for a composite action")
        return

    step_ids: set[str] = set()
    for index, step in enumerate(steps):
        if not isinstance(step, dict):
            errors.append(f"runs.steps[{index}] must be a mapping")
            continue
        if not step.get("run"):
            errors.append(f"runs.steps[{index}] is missing a 'run' script")
        if not step.get("shell"):
            errors.append(f"runs.steps[{index}] is missing 'shell'")
        step_id = step.get("id")
        if step_id:
            step_ids.add(str(step_id))


def validate(data: dict) -> list[str]:
    errors: list[str] = []

    if "name" not in data or "runs" not in data:
        errors.append("missing required 'name' or 'runs' key")
        return errors

    runs = data["runs"]
    if not isinstance(runs, dict):
        errors.append("'runs' must be a mapping")
        return errors

    validate_composite(runs, errors)

    inputs = data.get("inputs")
    if inputs is not None:
        if not isinstance(inputs, dict):
            errors.append("'inputs' must be a mapping")
        else:
            for name, spec in inputs.items():
                if not isinstance(spec, dict):
                    errors.append(f"inputs.{name} must be a mapping")
                    continue
                if "required" in spec and not isinstance(spec["required"], bool):
                    errors.append(f"inputs.{name}.required must be a boolean")

    outputs = data.get("outputs")
    if outputs is not None:
        if not isinstance(outputs, dict):
            errors.append("'outputs' must be a mapping")
        else:
            step_ids = {
                str(step.get("id"))
                for step in (runs.get("steps") or [])
                if isinstance(step, dict) and step.get("id")
            }
            for name, spec in outputs.items():
                if not isinstance(spec, dict):
                    errors.append(f"outputs.{name} must be a mapping")
                    continue
                value = spec.get("value")
                if not isinstance(value, str):
                    errors.append(f"outputs.{name}.value must be a string")
                    continue
                for ref_step, _ref_output in OUTPUT_STEP_REF.findall(value):
                    if ref_step not in step_ids:
                        errors.append(
                            f"outputs.{name}.value references unknown step id '{ref_step}'"
                        )

    return errors


def validate_file(path: Path) -> list[str]:
    try:
        with path.open("r", encoding="utf-8") as f:
            data = yaml.safe_load(f)
    except FileNotFoundError:
        return ["file not found"]
    except yaml.YAMLError as exc:
        return [f"not valid YAML:\n{exc}"]

    if not isinstance(data, dict):
        return ["root must be a mapping"]

    return validate(data)


def display_path(path: Path, cwd: Path) -> str:
    try:
        return path.resolve().relative_to(cwd).as_posix()
    except ValueError:
        return path.as_posix()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate the GitHub Actions action.yml manifests in this repository"
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help="Specific action.yml files to validate (default: all of them)",
    )
    parser.add_argument(
        "--root",
        default=None,
        help="Directory to search for action.yml files (default: repository root)",
    )
    args = parser.parse_args(argv)

    if args.paths:
        targets = [Path(p) for p in args.paths]
    else:
        root = Path(args.root).resolve() if args.root else repo_root()
        if not root.is_dir():
            print(f"Error: {root} is not a directory", file=sys.stderr)
            return 1
        targets = discover_actions(root)
        if not targets:
            print(f"Error: no action.yml files found under {root}", file=sys.stderr)
            return 1

    failures = 0
    cwd = Path.cwd()
    for target in targets:
        errors = validate_file(target)
        display = display_path(target, cwd)
        if errors:
            failures += 1
            print(f"FAIL {display}")
            for error in errors:
                print(f"  - {error}", file=sys.stderr)
        else:
            print(f"OK   {display}")

    print(f"Validated {len(targets)} action.yml file(s), {failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
