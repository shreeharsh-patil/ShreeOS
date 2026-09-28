#!/usr/bin/env python3
"""Validate every GitHub Actions `uses:` pin in the repository.

A fabricated or mistyped action SHA is invisible to YAML parsing and to
`bash -n`, and it fails only when the job actually starts -- costing a full CI
cycle to discover. This tool checks pins in two passes:

  offline   every `uses: owner/repo@ref` must be a full 40-character commit
            SHA, or a local `./path` action. Tags and branches are rejected
            because they are mutable and therefore not a supply-chain pin.

  online    each pinned SHA is resolved through the GitHub API to confirm the
            commit actually exists. This is the pass that catches a
            well-formed but nonexistent SHA, which no static check can detect.

Usage:
    python3 tools/check-action-pins.py                 # both passes
    python3 tools/check-action-pins.py --offline-only
    python3 tools/check-action-pins.py --token-env GITHUB_TOKEN

Exit status is 0 when every pin is valid, 1 otherwise.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request

SHA = re.compile(r"^[0-9a-f]{40}$")
USES = re.compile(r"^\s*-?\s*uses:\s*['\"]?([^'\"\s]+)['\"]?\s*$", re.M)
WORKFLOW_GLOBS = (".github/workflows/*.yml", ".github/workflows/*.yaml")

# Actions that are resolved by the runner, not by the GitHub API.
LOCAL_PREFIXES = ("./", "docker://")


def collect_pins(workflow_paths):
    """Return [{workflow, line, ref, owner, repo, sha, local}] for every pin."""
    pins = []
    for path in workflow_paths:
        try:
            with open(path, "r", encoding="utf-8") as handle:
                lines = handle.read().splitlines()
        except OSError as exc:
            print("error: cannot read %s: %s" % (path, exc), file=sys.stderr)
            continue
        for number, line in enumerate(lines, start=1):
            match = USES.match(line)
            if not match:
                continue
            ref = match.group(1)
            entry = {"workflow": path, "line": number, "ref": ref,
                     "owner": None, "repo": None, "sha": None,
                     "local": ref.startswith(LOCAL_PREFIXES)}
            if not entry["local"] and "@" in ref:
                name, _, version = ref.rpartition("@")
                parts = name.split("/")
                if len(parts) >= 2:
                    entry["owner"], entry["repo"] = parts[0], parts[1]
                    entry["sha"] = version
            pins.append(entry)
    return pins


def check_offline(pins):
    """Format gate: every remote pin must be a full, lowercase commit SHA."""
    failures = []
    for pin in pins:
        if pin["local"]:
            continue
        if pin["sha"] is None:
            failures.append((pin, "pin has no @version: " + pin["ref"]))
            continue
        if not SHA.match(pin["sha"]):
            failures.append((
                pin,
                "pin is not a full 40-character commit SHA (tags and "
                "branches are not immutable): " + pin["ref"]))
    return failures


def check_online(pins, token=None, timeout=30):
    """Confirm each pinned SHA resolves to a real commit."""
    failures = []
    cache = {}
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "shreeos-check-action-pins",
    }
    if token:
        headers["Authorization"] = "Bearer " + token
    for pin in pins:
        if pin["local"] or pin["sha"] is None:
            continue
        key = (pin["owner"], pin["repo"], pin["sha"])
        if key in cache:
            ok, reason = cache[key]
            if not ok:
                failures.append((pin, reason))
            continue
        url = "https://api.github.com/repos/%s/%s/commits/%s" % key
        request = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                json.loads(response.read().decode("utf-8"))
            ok, reason = True, None
        except urllib.error.HTTPError as exc:
            ok = False
            # The commits endpoint answers 404 for a missing repository and 422
            # for a reference that is well-formed but not a real commit, so
            # both mean the pin cannot be trusted.
            if exc.code in (404, 422):
                reason = ("pinned commit does not exist in %s/%s: %s"
                          % (pin["owner"], pin["repo"], pin["sha"]))
            elif exc.code in (403, 429):
                reason = ("GitHub API rate limit reached while verifying %s; "
                          "re-run or supply a token" % pin["ref"])
            else:
                reason = "GitHub API returned HTTP %d for %s" % (exc.code, pin["ref"])
        except urllib.error.URLError as exc:
            ok = False
            reason = "network error verifying %s: %s" % (pin["ref"], exc.reason)
        cache[key] = (ok, reason)
        if not ok:
            failures.append((pin, reason))
    return failures


def find_workflows(root):
    import glob
    paths = []
    for pattern in WORKFLOW_GLOBS:
        paths.extend(sorted(glob.glob(os.path.join(root, pattern))))
    return paths


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="repository root")
    parser.add_argument("--offline-only", action="store_true",
                        help="skip the GitHub API verification pass")
    parser.add_argument("--token-env", default="GITHUB_TOKEN",
                        help="environment variable holding an API token")
    args = parser.parse_args(argv[1:])

    paths = find_workflows(args.root)
    if not paths:
        print("error: no workflow files found under %s" % args.root, file=sys.stderr)
        return 1

    pins = collect_pins(paths)
    if not pins:
        print("error: no `uses:` pins found to verify", file=sys.stderr)
        return 1

    failures = check_offline(pins)
    remote = sum(1 for p in pins if not p["local"])
    print("checked %d pins (%d remote) across %d workflows"
          % (len(pins), remote, len(paths)))

    if not args.offline_only:
        online = check_online(pins, token=os.environ.get(args.token_env))
        failures.extend(online)
        print("verified %d remote pins against the GitHub API" % remote)

    for pin, reason in failures:
        print("FAIL %s:%d: %s" % (pin["workflow"], pin["line"], reason),
              file=sys.stderr)
    if failures:
        print("%d invalid action pin(s)" % len(failures), file=sys.stderr)
        return 1
    print("all action pins are valid immutable commits")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
