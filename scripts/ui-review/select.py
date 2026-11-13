"""Choose a local browser review from the task's effective diff (no network)."""
import os
import subprocess


def git(*args):
    return subprocess.check_output(["git", *args], stderr=subprocess.DEVNULL)


def reason(path):
    if path.startswith("assets/js/"):
        return "interaction"
    if path.startswith(("assets/css/", "priv/static/images/", "priv/static/fonts/")):
        return "appearance"
    if path.startswith("priv/gettext/"):
        return "copy"
    if path.endswith((".heex", ".eex")) or path.startswith((
        "lib/agent_board_web/components/", "lib/agent_board_web/live/",
    )) or path in ("lib/agent_board_web/router.ex", "lib/agent_board_web.ex"):
        return "screen"
    if path.startswith("lib/agent_board_web/controllers/") and ("_html" in path or "locale_controller" in path):
        return "screen"
    return None


def select():
    try:
        base = git("merge-base", "HEAD", "origin/main").decode().strip()
        changed = git("diff", "--name-only", "--no-renames", "-z", base, "--")
        untracked = git("ls-files", "--others", "--exclude-standard", "-z")
    except (OSError, subprocess.CalledProcessError):
        return "unknown"  # Run conservatively; an unavailable base is not an empty diff.
    reasons = {reason(os.fsdecode(path)) for path in (changed + untracked).split(b"\0")}
    return next((key for key in ("interaction", "screen", "appearance", "copy") if key in reasons), "none")


if __name__ == "__main__":
    print(select())
