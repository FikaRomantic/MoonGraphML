"""Inspect and test a real Moon package archive without publishing anything.

Only `moon package --frozen` is used. In particular, `moon publish --dry-run`
is not a safe offline packaging API. All extracted files and logs stay in .local.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import traceback
import zipfile

from release_guard import forbidden

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / ".local" / "package-results.json"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def main() -> int:
    moon = shutil.which("moon")
    require(moon is not None, "moon is not on PATH")
    (ROOT / ".local").mkdir(exist_ok=True)
    report = {"passed": False, "publication_attempted": False, "commands": []}

    def invoke(args: list[str], directory: Path) -> subprocess.CompletedProcess:
        command = [moon, *args]
        result = subprocess.run(command, cwd=directory, capture_output=True,
                                encoding="utf-8", errors="strict", timeout=240)
        report["commands"].append({"command": command, "cwd": str(directory),
                                   "returncode": result.returncode,
                                   "stdout": result.stdout, "stderr": result.stderr})
        RESULTS.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        require(result.returncode == 0, f"failed: {command}; see {RESULTS}")
        return result

    try:
        packaged = invoke(["package", "--frozen"], ROOT)
        match = re.search(r"^Package to (.+)$", packaged.stdout + packaged.stderr, re.MULTILINE)
        require(match is not None, "moon did not report a generated package path")
        archive = Path(match.group(1).strip()).resolve(strict=True)
        require(archive.is_relative_to((ROOT / "_build" / "publish").resolve()),
                "archive is outside the intended generated-package directory")
        report["archive"] = {"path": str(archive), "bytes": archive.stat().st_size,
                             "sha256": hashlib.sha256(archive.read_bytes()).hexdigest()}
        # A new retained directory protects prior results and never deletes a
        # user directory, checkout, dependency cache, or other package attempt.
        extracted = Path(tempfile.mkdtemp(prefix="package-qa-", dir=ROOT / ".local"))
        report["extracted_directory"] = str(extracted)
        with zipfile.ZipFile(archive) as package:
            normalized = set()
            files = []
            for entry in package.infolist():
                name = entry.filename.replace("\\", "/")
                path = PurePosixPath(name)
                require(not path.is_absolute() and ".." not in path.parts,
                        f"unsafe archive entry: {name}")
                require(not any(":" in part for part in path.parts), f"invalid archive entry: {name}")
                require(name.casefold() not in normalized, f"duplicate archive entry: {name}")
                normalized.add(name.casefold())
                require(not stat.S_ISLNK(entry.external_attr >> 16), f"archive symlink: {name}")
                require(not forbidden(name) and ".git" not in path.parts
                        and "__pycache__" not in path.parts,
                        f"local report, cache or Git object in package: {name}")
                require(not name.startswith(("scripts/", ".github/")),
                        f"development-only file unexpectedly packaged: {name}")
                target = (extracted / Path(*path.parts)).resolve()
                require(target.is_relative_to(extracted.resolve()), f"escaping archive entry: {name}")
                if not entry.is_dir():
                    files.append(name)
            for required in ("moon.mod", "moon.pkg", "README.md", "LICENSE",
                             "cmd/graphml/main.mbt", "examples/dependencies/main.mbt",
                             "examples/topology/main.mbt", "examples/datasets/main.mbt"):
                require(required in files, f"missing deliverable in package: {required}")
            require(any(name.endswith("_test.mbt") for name in files), "missing public API tests in package")
            package.extractall(extracted)
        report["archive_files"] = files
        dependencies = ROOT / ".mooncakes"
        require(dependencies.is_dir(), "local dependency cache missing; resolve dependencies first")
        shutil.copytree(dependencies, extracted / ".mooncakes")
        # --frozen means the isolated build uses only the already resolved cache.
        for command in ("check", "build", "test"):
            invoke([command, "--frozen", "--deny-warn", "--target", "all"], extracted)
        for example in ("dependencies", "topology", "datasets"):
            invoke(["run", f"examples/{example}", "--frozen", "--deny-warn", "--target", "native"], extracted)
        invoke(["run", "cmd/graphml", "--frozen", "--deny-warn", "--target", "native", "--",
                "verify", "tests/fixtures/flat.graphml"], extracted)
        report["passed"] = True
        RESULTS.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"PASS: {len(files)} report-free packaged files; isolated check/build/test, three examples and CLI passed")
        print(f"LOCAL ONLY: no publication attempted; evidence in {RESULTS}")
        return 0
    except Exception as error:
        report["failure"] = {"type": type(error).__name__, "message": str(error),
                             "traceback": traceback.format_exc()}
        RESULTS.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
