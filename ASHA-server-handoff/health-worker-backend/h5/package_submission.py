# -*- coding: utf-8 -*-
"""Builds the hackathon zip: a fresh git clone holding README.md, submission/, FULL_CODE/ and .gitignore.

    H5_DATA=/path/to/pack/data python -m h5.package_submission --team TEAMID --out /tmp/h5_pack

Steps: run the engine on the TEST questions -> submission/; copy the code (engine, tests, phone app, backend) into FULL_CODE/ without
secrets, models, build output or the pack's data; git init + commit in a stage folder; `git clone` it to a second folder; zip that clone.
Nothing is pushed anywhere."""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # the repository folder that holds health-worker-app and health-worker-backend

APP_SKIP = {"build", ".dart_tool", "apk-out", ".git", ".gradle", ".idea", "Pods", "h5"}  # "h5" only below assets/ (see _ignore_app)
BACKEND_SKIP = {".venv", "venv", "models", "demo", ".git", "__pycache__", ".pytest_cache", ".mypy_cache", "node_modules", "data"}
SKIP_FILES = {"key.properties", "local.properties", ".env", "demo.env", ".flutter-plugins", ".flutter-plugins-dependencies"}
SKIP_SUFFIX = (".zip", ".jks", ".keystore", ".db", ".sqlite", ".apk", ".pyc", ".onnx", ".gguf")

GITIGNORE = """# the pack's data and downloaded models stay out of git (see README: where to put them)
data/
models/
.env
.venv/
node_modules/
__pycache__/
*.pyc
# generated from the pack's data by FULL_CODE/backend/h5/export_assets.py
FULL_CODE/app/assets/h5/
# build output
FULL_CODE/app/build/
FULL_CODE/app/.dart_tool/
"""


def _ignore_app(src: str, names: list) -> set:
    here = Path(src)
    out = set()
    for n in names:
        if n in SKIP_FILES or n.endswith(SKIP_SUFFIX):
            out.add(n)
        elif n in APP_SKIP and not (n == "h5" and here.name != "assets"):
            out.add(n)
        elif n == "models" or n == "demo_models":
            out.add(n)
    return out


def _ignore_backend(src: str, names: list) -> set:
    return {n for n in names if n in BACKEND_SKIP or n in SKIP_FILES or n.endswith(SKIP_SUFFIX)}


def run(*cmd, cwd=None) -> None:
    subprocess.run(cmd, cwd=cwd, check=True)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--team", default="TEAMID")
    ap.add_argument("--out", required=True, help="empty or new folder for the stage, the clone and the zip")
    a = ap.parse_args(argv)
    out = Path(a.out).resolve()
    if out.exists() and any(out.iterdir()):
        sys.exit(f"{out} is not empty")
    stage, clone = out / "stage", out / "clone"
    (stage / "FULL_CODE").mkdir(parents=True)

    # 1. the three files, made from the TEST questions
    run(sys.executable, "-m", "h5.run", "--split", "test", "--out", str(stage / "submission"), cwd=ROOT / "health-worker-backend")

    # 2. the code
    shutil.copytree(ROOT / "health-worker-backend", stage / "FULL_CODE" / "backend", ignore=_ignore_backend)
    shutil.copytree(ROOT / "health-worker-app", stage / "FULL_CODE" / "app", ignore=_ignore_app)
    shutil.copy(ROOT / "health-worker-backend" / "h5" / "SUBMISSION_README.md", stage / "README.md")
    (stage / ".gitignore").write_text(GITIGNORE, encoding="utf-8")

    # 3. a git repository, then a fresh clone of it
    run("git", "init", "-q", cwd=stage)
    run("git", "add", "-A", cwd=stage)
    run("git", "-c", "user.name=H5 team", "-c", "user.email=team@example.invalid", "commit", "-q", "-m", "H5 submission", cwd=stage)
    run("git", "clone", "-q", str(stage), str(clone))
    shutil.rmtree(clone / ".git")
    z = shutil.make_archive(str(out / f"{a.team}_H5"), "zip", root_dir=clone)
    print("zip:", z)
    return 0


if __name__ == "__main__":
    sys.exit(main())
