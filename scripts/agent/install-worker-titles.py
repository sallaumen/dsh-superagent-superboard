#!/usr/bin/env python3
"""Install the worker-title plugin in DSH_HOME; preserve other home patch entries."""
import argparse
import json
import os
from pathlib import Path
import shutil
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true", help="inspect files without installing or starting Harness")
args = parser.parse_args()

root = Path(os.getenv("DSH_HOME", Path.home() / ".dsh")).expanduser().resolve()
source = Path(__file__).resolve().parents[2] / "ops/harness-worker-titles"
target = root / "superboard-plugins/worker-titles"


def replace(path, data):
    if path.exists() and path.read_bytes() == data:
        return
    fd, name = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        if path.exists():
            shutil.copymode(path, name)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


patch = root / "cordis.patch.yml"
original = patch.read_text() if patch.exists() else ""
begin, end = "# >>> superboard-worker-titles >>>", "# <<< superboard-worker-titles <<<"
block = f"{begin}\n- insert:\n    - id: superboard-worker-titles\n      name: {json.dumps(str(target / 'index.js'))}\n{end}\n"
markers = (original.count(begin), original.count(end))
conflict = markers not in ((0, 0), (1, 1)) or (markers == (1, 1) and original.index(begin) > original.index(end))

if args.check:
    files = ("package.json", "index.js")
    if not target.exists() and begin not in original and end not in original:
        print("missing")
    elif conflict:
        print("conflict")
    elif "\n" + block in "\n" + original + "\n" and all(
        (target / f).is_file() and (target / f).read_bytes() == (source / f).read_bytes() for f in files
    ):
        print("installed")
    else:
        print("needs-update")
    raise SystemExit(0)

if conflict:
    raise SystemExit("Incomplete managed block; existing configuration left unchanged")
if markers == (1, 1):
    before, rest = original.split(begin)
    _, after = rest.split(end)
    result = before + block.rstrip("\n") + after
else:
    result = (original.rstrip("\n") + "\n" if original.strip() else "") + block
target.mkdir(parents=True, exist_ok=True)
for file in ("package.json", "index.js"):
    replace(target / file, (source / file).read_bytes())
replace(patch, result.encode())
print(f"Worker titles installed in {root}; running hosts use the change on their next load.")
