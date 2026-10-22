"""Read-only release/history hygiene gate; identity migration is a separate action."""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN = (
    ".local/", "_build/", "target/", ".mooncakes/", "docs/adr/", "context.md",
    "申报", "审查", "验收记录", "汇总", "ai辅助", "ai-report", "review-report",
    "acceptance-report", "research-report", "summary-report", "proposal", "研究报告", "调研报告",
    "ai测试", "ai_test", "ai-test-output", "test-output", "test-results", "测试输出",
)


def git(*args):
    return subprocess.run(["git", "-c", f"safe.directory={ROOT.as_posix()}",
                           "-c", "core.quotepath=false", *args], cwd=ROOT,
                          check=True, capture_output=True).stdout.decode("utf-8")


def forbidden(path):
    path = path.replace("\\", "/").lower()
    name = path.rsplit("/", 1)[-1]
    return (any(marker in path for marker in FORBIDDEN)
            or name.endswith((".log", ".pyc", "-results.json", "_results.json"))
            or "__pycache__" in path.split("/"))


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def effective_lines(paths):
    total = 0
    files = 0
    for name in paths:
        path = Path(name)
        # This gate intentionally counts only the implementation package, excluding
        # examples, CLI, tests and generated declarations from the 4k floor.
        if path.parent != Path(".") or path.suffix != ".mbt" or name.endswith(("_test.mbt", "_wbtest.mbt")):
            continue
        # Count committed source, not a larger uncommitted working copy. The
        # pre-commit hook uses --staged-only and does not run this final gate.
        text = git("show", f"HEAD:{path.as_posix()}")
        in_block = False
        for line in text.splitlines():
            stripped = line.strip()
            if in_block:
                if "*/" in stripped:
                    in_block = False
                continue
            if stripped.startswith("/*"):
                in_block = "*/" not in stripped
                continue
            if stripped and not stripped.startswith("//"):
                total += 1
        files += 1
    return files, total


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", action="store_true", help="also require actual publishing ownership fields")
    parser.add_argument("--staged-only", action="store_true", help="fast pre-commit report exclusion check")
    args = parser.parse_args()
    staged = [name for name in git("diff", "--cached", "--name-only", "-z").split("\0") if name]
    require(not any(forbidden(name) for name in staged), "forbidden local report/cache in staging")
    if args.staged_only:
        print("PASS: staged files contain no local reports or caches")
        return
    tracked = [name for name in git("ls-files", "-z").split("\0") if name]
    require(not any(forbidden(name) for name in tracked), "forbidden local report/cache in tracked files")
    commits = git("rev-list", "HEAD").splitlines()
    require(len(commits) > 30, "more than 30 meaningful commits are required")
    # rev-list --objects emits one name per object and can miss a forbidden
    # historical filename when the blob is also reused under a permitted name.
    # Inspect every reachable tree, including other local refs, instead.
    for commit in git("rev-list", "--all").splitlines():
        tree_paths = [name for name in git("ls-tree", "--full-tree", "-r", "--name-only", "-z", commit).split("\0") if name]
        require(not any(forbidden(name) for name in tree_paths),
                f"forbidden local report/cache in Git tree {commit}")
    for commit in commits:
        require(bool(git("diff-tree", "--root", "--no-commit-id", "--name-only", "-r", commit).strip()),
                f"empty commit detected: {commit}")
    files, lines = effective_lines(tracked)
    require(lines > 4000, f"core effective implementation lines {lines} must exceed 4000")
    module = (ROOT / "moon.mod").read_text(encoding="utf-8")
    name = re.search(r'^name\s*=\s*"([^\"]+)"', module, re.M)
    require(name is not None, "missing module name")
    owner = name.group(1).split("/", 1)[0]
    if args.release:
        require(not git("status", "--porcelain").strip(),
                "commit all release deliverables before publishing; ignored local artifacts are permitted")
        require(owner.lower() not in {"local", "username", "user", "yourname"},
                "publishing account deliberately blank: set real owner only after user confirmation")
        require(re.search(r'^repository\s*=\s*"https://github\.com/[^\"]+"', module, re.M) is not None,
                "missing real public GitHub repository URL")
        require(bool(git("remote").strip()), "missing public repository remote")
        expected = f"{owner} <346264193+{owner}@users.noreply.github.com>"
        identities = git("log", "--all", "--format=%an <%ae>|%cn <%ce>").splitlines()
        require(owner == "FikaRomantic", "unexpected publishing owner")
        require(all(item == f"{expected}|{expected}" for item in identities),
                "all reachable author/committer identities must match publishing owner")
    print(f"PASS: report-free Git history, {len(commits)} nonempty commits, {files} core files, {lines} effective lines")
    if owner == "local":
        print("PENDING: account intentionally blank; this is a local-readiness result, not publication or contest acceptance")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
