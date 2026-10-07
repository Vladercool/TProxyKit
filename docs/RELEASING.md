# Publishing and releases

## First publication

1. Choose the actual GitHub repository and replace every `OWNER/REPO` occurrence in this project, including `BOOT_REPO` in bootstrap.sh.
2. Enable private vulnerability reporting and branch protection with the Checks workflow required. Review the MIT/third-party boundaries.
3. Execute the real Debian VPS acceptance checklist. Set the changelog release date and ensure the installer `VERSION` matches the intended tag.
4. Commit the reviewed tree, push `main`, and check CI. Publish a stable semantic-version tag such as `v1.0.0` only after approval.

No repository or release was created as part of preparing this source package. The one-liner cannot work before the first release exists. README intentionally has no claimed live CI/release status badge.

The release workflow runs reusable CI first. It validates a numeric stable tag against `VERSION`, checks a changelog entry, refuses an unsubstituted bootstrap repository, generates `SHA256SUMS`, then publishes `install.sh`, `bootstrap.sh` and the checksum manifest with GitHub's CLI. Publication permissions are restricted to the release job. Reusing/overwriting an existing release is not automatic. Treat published tags/assets as immutable.

Action revisions, Bats and check-tool versions are pinned. Python package pins rely on PyPI/TLS, not vendored wheels or independent package signatures. Review and bump pins deliberately. The pinned upstream fixture in CI is the audited contract; it does not track HEAD automatically or claim to test every future runtime revision.

## Inspect and pin before execution

In a trusted working directory, as an operator:

```bash
repo=OWNER/REPO
version=v1.0.0
curl --proto '=https' --proto-redir '=https' -fLSs \
  "https://github.com/$repo/releases/download/$version/install.sh" -o install.sh
curl --proto '=https' --proto-redir '=https' -fLSs \
  "https://github.com/$repo/releases/download/$version/SHA256SUMS" -o SHA256SUMS
```

Inspect the script and the manifest. Verify the one expected installer entry before executing:

```bash
awk '$2 == "install.sh" && length($1) == 64 && $1 !~ /[^0-9a-f]/ {print; n++} END {if (n != 1) exit 1}' \
  SHA256SUMS > installer.sha256 && sha256sum --check installer.sha256
```

After successful verification and inspection, run `bash install.sh install` in a root shell. The checksum is distributed through the same GitHub release, so it is not independent publisher authentication. Obtain a checksum through a separate trusted channel if that is part of your threat model.

An inspected local bootstrap can pin this wrapper's release with `WEBPROXY_RELEASE=v1.0.0 bash bootstrap.sh install`. Pinning the wrapper is separate from `--upstream-ref`, which pins the official relay source.
