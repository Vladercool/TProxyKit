#!/usr/bin/env python3
"""Scan publication files without storing the previous private values in the repo."""
import hashlib
import re
from pathlib import Path
import sys

# Fingerprints of the six values prohibited by the private-to-public migration.
DENIED = {
    (18, "9c8ffa00e7d558f9a0d5b551708db5a0081429d9a2b9acc42a92fd9f0ce311a8"),
    (12, "a58eb214b5ea0d38166a14af524c59b5ac7fe54b557da6631088bdefd9d39ae9"),
    (17, "28150f781179d71adda250c2f5ccd8f9f30f1202f4438eedb7c8b5b3eed93dee"),
    (10, "9677c98fd2e007338a3ecf38c54ed4bbf9f6618071043b918558fb31626b0277"),
    (10, "8d194df74d56f570a2a8aa3759994fd08b0d08d2b1af734438c6a86cd4bda9fe"),
    (4, "b092aeb3b2b942cc09ab5e2606c8903531b2a847d735e5f300c0c1f8c8419cf6"),
}
ROOT = Path(__file__).resolve().parents[1]
ALLOWED = {".sh", ".bats", ".md", ".py", ".yml", ".yaml"}
failures = []
for path in sorted(ROOT.rglob("*")):
    relative = path.relative_to(ROOT)
    if any(part in {".git", ".tools", ".upstream", "__pycache__"} for part in relative.parts):
        continue
    if path.is_symlink():
        failures.append(f"Symlink in publication tree: {relative}")
        continue
    if not path.is_file():
        continue
    if path.suffix not in ALLOWED and path.name not in {"LICENSE", ".gitignore"}:
        failures.append(f"Unexpected publication artifact: {relative}")
        continue
    try:
        text = path.read_text(encoding="utf-8").casefold()
    except UnicodeError:
        failures.append(f"Non-text publication artifact: {relative}")
        continue
    for length, fingerprint in DENIED:
        if any(hashlib.sha256(text[i:i + length].encode()).hexdigest() == fingerprint
               for i in range(len(text) - length + 1)):
            failures.append(f"Private deployment value in {relative}")
            break
    if re.search(r"^-----begin [a-z ]*private key-----$", text, re.MULTILINE):
        failures.append(f"Private key material in {relative}")
if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
print("Publication hygiene passed.")
