#!/usr/bin/env python3
"""Print the macOS service configuration for this checkout. Never installs or starts it."""
import argparse
import os
import plistlib
import sys
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("service", choices=("board", "agent"))
args = parser.parse_args()
checkout = Path(__file__).resolve().parents[1]
home = Path.home()
prototype = os.environ.get("DSH_SUPERAGENT_HOME") or home / ".dsh" / "dsh-superagent"
name = "com.agentboard" if args.service == "board" else "com.dsh.superagent"
with (checkout / "ops" / (name + ".plist")).open("rb") as template:
    settings = plistlib.load(template)


def expand(item):
    if isinstance(item, dict):
        return {key: expand(value) for key, value in item.items()}
    if isinstance(item, list):
        return [expand(value) for value in item]
    if isinstance(item, str):
        return (item.replace("@HOME@", str(home)).replace("@CHECKOUT@", str(checkout))
                .replace("@PROTOTYPE@", str(prototype)))
    return item


document = expand(settings)
if os.environ.get("PATH"):
    document["EnvironmentVariables"]["PATH"] = os.environ["PATH"]
plistlib.dump(document, sys.stdout.buffer, sort_keys=False)
