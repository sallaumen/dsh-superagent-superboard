#!/usr/bin/env python3
"""Install the worker-title plugin in DSH_HOME; preserve other home patch entries."""
import json
import os
from pathlib import Path
import shutil
import tempfile

root = Path(os.getenv("DSH_HOME", Path.home() / ".dsh")).expanduser().resolve()
root.mkdir(parents=True, exist_ok=True)
source = Path(__file__).resolve().parents[2] / "ops/harness-worker-titles"
target = root / "superboard-plugins/worker-titles"
target.mkdir(parents=True, exist_ok=True)


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
if begin in original or end in original:
    if original.count(begin) != 1 or original.count(end) != 1 or original.index(begin) > original.index(end):
        raise SystemExit("Incomplete managed block; existing configuration left unchanged")
    before, rest = original.split(begin)
    _, after = rest.split(end)
    result = before + block.rstrip("\n") + after
else:
    result = (original.rstrip("\n") + "\n" if original.strip() else "") + block
for file in ("package.json", "index.js"):
    replace(target / file, (source / file).read_bytes())
replace(patch, result.encode())
print(f"Worker titles installed in {root}; running hosts use the change on their next load.")
