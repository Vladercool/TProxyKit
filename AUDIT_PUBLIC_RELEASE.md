# Public release audit — 1.0.0 candidate

Prepared 2026-10-07. This is a source/release-artifact preparation result. No GitHub repository was changed, no release was published and no VPS was operated on during Phase 2.

## Baseline and targeted upstream check

Reused the prior reviewed `install-telegram-webproxy.sh`, `AUDIT.md` and all **30 Bats regression cases**. Private deployment values were replaced with standard example/TEST-NET values. The previous CWD, delayed-readiness, secret/token preservation, NAT, reference topology, permissions, firewall and rollback protections were retained or tightened.

The official `telegramdesktop/tproxy-server` default HEAD remained **`c8adb8b7c6b7fc46c12ae3acb68be9070c26a8e8`** at the targeted freshness check. The official [releases page](https://github.com/telegramdesktop/tproxy-server/releases) still had no releases. No upstream delta required repeating the original deep audit. The existing installer permission fix is present in that source; the known firewall reload concern remains relevant. A wrapper drop-in propagates nftables reload, while the provider firewall remains mandatory because upstream's table replacement is non-atomic.

The reviewed tproxy-server tree has no repository-level LICENSE. MTProxy's official repository contains GPLv2. This project includes no upstream implementation archive/binary; its original wrapper/tests/docs are MIT. See [third-party boundaries](THIRD_PARTY_NOTICES.md). Official source was used as the authority; Context7 was not needed for this targeted delta.

## Public behavior and ownership

| Area | Implemented behavior |
|---|---|
| CLI | One subcommand parser: install, update, status, uninstall, show-link, help; validated terminal prompts and explicit unattended inputs |
| Version resolution | Latest official stable release, otherwise default HEAD only on a no-release response; API failures abort; exact SHA/tag override optional |
| Compatibility | Exact deployment-file and BASE_PATH-document hashes, Bash syntax and transformation anchors; changed contract stops before activation |
| State | Root-only deployment identity, phase, SHA and resource manifest; canonical secret locations remain authoritative |
| Adoption | Explicit `--adopt`, private-wrapper provenance and reference topology required; token, secret, base path and operator site preserved |
| Update | Reviewed upstream relay-only updater under both locks; binary/metadata backup; endpoint/TLS/firewall and file-preservation checks before SHA commit |
| Rollback | Failed update restores previous binary and metadata through EXIT cleanup, verifies local health/readiness; reports rollback failure |
| Uninstall | Explicit owned paths/hashes and effective service/table checks; default keeps private config/site; purge/site options separate |
| Mutable/retained data | Daily DC list, source/build tree apart from executable, packages/users/toolchains, ACME storage and backups retained |
| Bootstrap | HTTPS-only stable release assets, restricted manifest parsing, SHA256 verification before execution, private temporary directory and cleanup |

A partial fresh install is marked `installing` and stops automated retry/removal. Uninstall is not full host restoration. Modified resources require manual review. `--remove-obsolete` is optional, identity-specific and not transactionally reversible. The normal public site has neutral domain welcome text; installation details are not exposed in its page copy.

## Checks actually performed

| Check | Local result |
|---|---|
| Bats 1.12.0 | **79/79 PASS**, zero skips: 30 retained regressions + 49 public/lifecycle/bootstrap/hygiene cases |
| `bash -n` | PASS for install.sh and bootstrap.sh separately; upstream deployment scripts checked by compatibility tests |
| ShellCheck 0.11.0 | PASS for both shipped Bash scripts |
| shfmt 3.14.1 | PASS with `-d -i 2 -ci` for both scripts and all Bats files |
| Publication hygiene | PASS across the complete source tree: prohibited-value fingerprints, text/artifact allowlist, no private-key blocks |
| Workflow YAML | Parsed locally; pinned action/tool refs and reusable release dependencies inspected |
| GitHub Actions execution | NOT RUN; workflows supplied, no GitHub publication authorized |
| Upstream Go test/race/vet | NOT RUN locally: Go unavailable. Implemented as separate CI gates against audited source |
| Fresh Debian/systemd/ACME/nftables/Telegram E2E | NOT RUN; real VPS acceptance remains required |

ShellCheck/shfmt became available after one successful package-tool installation attempt; the unavailable-tool limitation from Phase 1 no longer applies to those static checks. No repeated tooling-install attempts were made for Go.

Tests exercise interactive and unattended inputs, validation, fresh-state journaling, no-op preservation, release-vs-HEAD selection, SHA recording, changed contract refusal, success/failure update paths, secret/token/base-path/site preservation, adoption success/refusal, secret-free status, runtime/purge ownership behavior, foreign Caddy/nftables/Docker preservation, link vectors and bootstrap verify/cleanup/argument forwarding. Lifecycle tests isolate host operations with mocks and temporary files. They do not prove real installation or kernel behavior.

## Security review and fixes

Manual review covered credential output/argv/environment boundaries, permissions, path/symlink checks, temporary files, cleanup traps, bounded polling, Git/URL construction, release redirects, checksum order, rollback, uninstall ownership, NAT assumptions, systemd credentials, Caddy/listeners, logs and adoption. No `eval`, global Docker prune, global nftables flush or recursive removal of configuration trees is used. Recursive cleanup is limited to private temporary directories; site removal is explicit and scoped.

Codex Security was not installed/available; it was replaced by manual review plus **one independent agent review and a targeted fix follow-up**. The reviewer identified:

1. Fresh installation could overwrite a same-named unowned backend table. Fixed with a preflight table-absence check.
2. Fresh activation could inherit unowned systemd units/drop-ins. Fixed with effective LoadState/drop-in and directory checks.
3. Firewall validation accepted additional narrowing predicates. Fixed with exact canonical expression validation; adoption/update also compare persisted firewall source.
4. The daily refreshed DC list made hash-based purge fail after normal refresh. It is now deliberately retained even during purge.
5. Optional old-container removal preceded site validation. All source/destination site checks now precede it, including an incomplete destination when `--site-dir` is supplied.

The reviewer verified four primary fixes with five targeted tests and identified the final destination-site branch issue; the primary maintainer then added the unconditional destination check and inspected its ordering before container removal. Final suite/static checks cover the resulting tree. There is no claim of a clean live-host penetration test or Codex Security scan.

## Remaining gates and publication details

Complete [real VPS acceptance](docs/VALIDATION.md), including ACME, provider/host firewall reload/reboot behavior, IPv4/IPv6 external probes, NAT/Telegram Desktop E2E, live adoption, update rollback and uninstall on disposable fixtures. Run the supplied CI after publication preparation; run the actual release/bootstrap download path after the first release exists.

The only repository identity placeholder is **`OWNER/REPO`**. Substitute it consistently, enable private reporting/branch checks, date the changelog and approve publication/tagging separately. The README does not claim a live CI badge, published release, signed artifact or production certification.

Known limits: dynamic compatible runtime source is not wholly audited by deployment hashes; remote bootstrap/checksums share publisher trust; root and privileged process inspection can expose upstream MTProxy arguments; provider NAT can differ by destination; root races/SIGKILL/power loss are outside atomic rollback guarantees; backups can retain credentials after purge.
