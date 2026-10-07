# Validation

Local preparation results are recorded in [the public audit](../AUDIT_PUBLIC_RELEASE.md). Bats tests use mocks and temporary files; they do not modify real system services or prove a deployment works on a VPS.

## Reproduce local checks

From the repository root, install Bash, git, jq, curl, OpenSSL, Python 3 and coreutils. Tool versions used: Bats 1.12.0, ShellCheck 0.11.0, shfmt 3.14.1.

```bash
python3 -m venv .tools/venv
.tools/venv/bin/pip install shellcheck-py==0.11.0.1 shfmt-py==4.2.0
git clone https://github.com/bats-core/bats-core.git .tools/bats
git -C .tools/bats checkout --detach 713504bc0224a19b3d7c7958c18dc07f64f54b44
git clone https://github.com/telegramdesktop/tproxy-server.git .upstream
git -C .upstream checkout --detach c8adb8b7c6b7fc46c12ae3acb68be9070c26a8e8
for script in install.sh bootstrap.sh; do bash -n "$script"; done
.tools/venv/bin/shellcheck install.sh bootstrap.sh
.tools/venv/bin/shfmt -d -i 2 -ci install.sh bootstrap.sh tests/*.bats
UPSTREAM_SOURCE="$PWD/.upstream" .tools/bats/bin/bats tests
```

`UPSTREAM_SOURCE` enables both source-contract tests; do not count a run with skipped compatibility tests as complete. The publication scan includes documentation and workflow files, uses fingerprints rather than embedding former private values, and rejects unexpected artifact types and private-key blocks. It is a targeted hygiene check, not a general secret-detection guarantee.

CI repeats these checks on Ubuntu 24.04 and separately runs `go test ./...`, `go test -race ./...` and `go vet ./...` against the audited upstream checkout with Go 1.26.5. These checks are useful for source and interface regressions; no container result substitutes for the following acceptance.

## Real Debian 13 VPS acceptance — required before production

Use a disposable dedicated VPS with actual DNS, inbound forwarding and provider firewall. Keep SSH recovery access and a host snapshot.

- Fresh interactive and unattended installation: ACME issuance, site response, private file modes, expected listeners and active services.
- Confirm external connections cannot reach 2398/8888/8080/8081 over IPv4 or IPv6; verify the provider boundary separately from nftables.
- Exercise nftables start/reload/restart and reboot: backend protection must return, services must recover, no unexpected units or rules may disappear.
- Verify Telegram Desktop WEB Proxy connection, message/media transfer and reconnection using explicit `show-link` output; inspect base-path/root-path behavior where applicable.
- Exercise measured NAT on the actual provider; include different inbound and egress addresses if used.
- Adopt a healthy reference deployment: byte-compare secret/profile, token key, base path and site; confirm ownership stops for customized/ambiguous variants.
- Update to a genuinely distinct compatible official revision: verify preservation and exact SHA commit. Inject candidate activation/readiness failure and verify binary rollback, including reboot/SIGKILL recovery procedures separately.
- Runtime uninstall must preserve secrets/site, provider/global firewall and unrelated services/containers. Test purge/site flags on disposable copies; test refusal after resource changes and daily DC refresh.
- After publication, exercise the actual GitHub bootstrap/release redirect/assets and checksum-failure path from a clean host.

No live VPS operation, ACME issuance, kernel firewall mutation or Telegram client E2E was performed during Phase 2. Prior reference-topology observations are not evidence that the new lifecycle passes these gates.
