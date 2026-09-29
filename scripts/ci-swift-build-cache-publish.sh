#!/usr/bin/env bash
set -euo pipefail

# CI_CACHE_API is an executable command prefix. Production sets it to `gh api`;
# tests inject a fixture-backed command that accepts METHOD and API PATH.
exec python3 - "$@" <<'PY'
import json
import os
import re
import shlex
import subprocess
import sys
from urllib.parse import quote

CACHE_NAMESPACE = os.environ.get("CI_SWIFT_CACHE_NAMESPACE", "swift-build-v1-")
TRUSTED_PRODUCER_REF = os.environ.get("CI_SWIFT_TRUSTED_PRODUCER_REF", "refs/heads/main")
OWNED = re.compile(r"^" + re.escape(CACHE_NAMESPACE) + r"[^-]+-[^-]+-[a-f0-9]{64}-r([0-9]+)-[a-f0-9]+$")
LIMIT = 8_500_000_000


def api(method, path):
    prefix = shlex.split(os.environ.get("CI_CACHE_API", "gh api"))
    if not prefix:
        raise ValueError("CI_CACHE_API is empty")
    command = prefix + ["--method", method, path]
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        raise RuntimeError("cache API " + method + " failed: " + result.stderr.strip())
    if method == "DELETE":
        return None
    return json.loads(result.stdout)


def cache_entries():
    repository = os.environ["GITHUB_REPOSITORY"]
    entries = []
    page = 1
    while True:
        path = "repos/{}/actions/caches?per_page=100&page={}".format(repository, page)
        result = api("GET", path)
        if not isinstance(result, dict) or not isinstance(result.get("actions_caches"), list):
            raise ValueError("cache API listing has no actions_caches")
        batch = result["actions_caches"]
        for entry in batch:
            if not isinstance(entry, dict) or not all(
                field in entry for field in ("id", "key", "ref", "size_in_bytes")
            ):
                raise ValueError("cache API listing has incomplete entry")
        entries.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    return entries


def owned_main(entry):
    if entry["ref"] != TRUSTED_PRODUCER_REF:
        return None
    match = OWNED.fullmatch(entry["key"])
    return int(match.group(1)) if match else None


def plan_save(key, run_number, seed_bytes):
    if OWNED.fullmatch(key) is None or int(OWNED.fullmatch(key).group(1)) != run_number:
        raise ValueError("save key does not name the producer run")
    entries = cache_entries()
    if any(number is not None and number > run_number
           for entry in entries if (number := owned_main(entry)) is not None):
        print("skipped-newer")
        return
    total_bytes = sum(int(entry["size_in_bytes"]) for entry in entries)
    if total_bytes + seed_bytes > LIMIT:
        print("skipped-budget")
        return
    print("saved " + key)


def prune(disposition, key, run_number):
    if disposition not in ("saved", "skipped-budget"):
        print("prune-skipped " + disposition)
        return
    key_match = OWNED.fullmatch(key)
    if key_match is None or int(key_match.group(1)) != run_number:
        raise ValueError("prune key is outside the configured namespace or run")
    entries = cache_entries()
    if disposition == "saved" and not any(
        entry["key"] == key and entry["ref"] == TRUSTED_PRODUCER_REF for entry in entries
    ):
        raise ValueError("new seed key was not confirmed on trusted ref")
    older = [entry for entry in entries if (number := owned_main(entry)) is not None and number < run_number]
    failed = []
    for entry in older:
        try:
            api("DELETE", "repos/{}/actions/caches/{}".format(
                os.environ["GITHUB_REPOSITORY"], quote(str(entry["id"]), safe="")))
        except RuntimeError:
            failed.append(entry["key"])
    if failed:
        reason = "retained new seed" if disposition == "saved" else "no seed saved after budget skip"
        print("prune-failed; " + reason + "; older entries remain: " + ", ".join(failed), file=sys.stderr)
        sys.exit(1)
    print("pruned " + str(len(older)))


def main():
    if len(sys.argv) == 5 and sys.argv[1] == "plan-save":
        plan_save(sys.argv[2], int(sys.argv[3]), int(sys.argv[4]))
    elif len(sys.argv) == 5 and sys.argv[1] == "prune":
        prune(sys.argv[2], sys.argv[3], int(sys.argv[4]))
    else:
        raise ValueError("expected plan-save KEY RUN SEED_BYTES or prune DISPOSITION KEY RUN")


try:
    main()
except (KeyError, ValueError, RuntimeError, json.JSONDecodeError) as error:
    print("ci-swift-build-cache-publish: " + str(error), file=sys.stderr)
    sys.exit(1)
PY
