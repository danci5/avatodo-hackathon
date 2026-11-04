#!/usr/bin/env python3
"""Check direct Meta model-catalog access without printing the credential."""

import argparse
import json
import subprocess
import sys


def main():
    argparse.ArgumentParser(description=__doc__).parse_args()
    credential = subprocess.run(
        ["/usr/bin/security", "find-generic-password", "-a", "avatodo",
         "-s", "app.avatodo.development.meta", "-w"],
        capture_output=True,
        text=True,
        check=False,
    )
    if credential.returncode:
        print("No accessible development key. Open scripts/configure-meta-key.command first.")
        return 2
    key = credential.stdout.rstrip("\r\n")
    if not key or any(ord(c) < 33 or ord(c) > 126 for c in key):
        print("The saved key contains invalid characters. Replace it in Keychain.")
        return 2

    # Headers travel through stdin, never process arguments or a project file.
    response = subprocess.run(
        ["/usr/bin/curl", "-q", "--silent", "--show-error", "--proto", "=https",
         "--connect-timeout", "15", "--max-time", "40", "--header", "@-",
         "--write-out", "\n%{http_code}", "https://api.meta.ai/v1/models"],
        input=f"Authorization: Bearer {key}\nAccept: application/json\n",
        capture_output=True,
        text=True,
        check=False,
    )
    if response.returncode:
        print("Network check failed. No response body or credentials were printed.")
        return 3
    body, _, status = response.stdout.rpartition("\n")
    if status != "200":
        print(f"Meta model-catalog request returned HTTP {status}.")
        print("Check account access, key validity and provider setup. Response body withheld.")
        return 4
    try:
        models = json.loads(body)["data"]
        if not isinstance(models, list):
            raise ValueError("Invalid catalog")
        ids = {m["id"] for m in models if isinstance(m, dict) and isinstance(m.get("id"), str)}
    except (ValueError, KeyError, TypeError):
        print("Meta responded, but its model catalog was not in the expected format.")
        return 5
    print("Meta model-catalog access: OK (HTTP 200).")
    for model in ("muse-spark-1.3", "muse-image-1.0"):
        print(f"{model}: {'listed' if model in ids else 'not listed; check enabled model IDs'}")
    print("No inference or image-generation request was sent. Those require separate checks.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
