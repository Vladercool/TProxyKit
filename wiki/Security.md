# Security

The repository's [SECURITY.md](https://github.com/Vladercool/TProxyKit/blob/main/SECURITY.md) is the authoritative policy and trust-model document. This page focuses on operator decisions.

## Credentials and root access

TProxyKit performs privileged installation and trusts the administrator, downloaded project code and the host's root account. It cannot defend against malicious root access.

Profiles and token keys remain in canonical upstream locations with restrictive permissions; the relay uses systemd credential delivery. Metadata records deployment identity and ownership rather than another proxy secret value. Ordinary install/update/status output does not print client links.

`bash install.sh show-link` intentionally discloses credentials. Both generated links grant access; treat clipboard history, terminal recordings and shared screenshots accordingly. The official MTProxy service can expose its secret to sufficiently privileged process/diagnostic inspection through arguments or environment.

## Network boundaries

| Boundary | Operator responsibility |
|---|---|
| Caddy | Public TCP 80/443 and valid DNS/certificate routing |
| Relay/admin | Keep 8080/8081 on loopback and blocked externally |
| MTProxy backend | Deny external 2398/8888 with provider firewall and the managed host rule |

The provider firewall is required. Upstream's backend table reload deletes then recreates the table, so host-only protection has a short gap. Do not infer external protection solely from a local service being active. Real IPv4/IPv6 probes, reload and reboot acceptance remain necessary.

## Downloads and updates

The planned bootstrap fetches HTTPS release assets into a private temporary directory and verifies installer SHA256 before execution. It fails on download or checksum errors. See [Getting Started](Getting-Started) for the current publication blocker.

A checksum obtained from the same publisher does not independently authenticate that publisher or defeat compromise of the release and its manifest. The one-liner also fetches mutable bootstrap code. Inspecting and pinning source/release versions improves reproducibility; it does not remove repository and maintainer trust.

The upstream contract gate rejects changed deployment interfaces before activation. It is not a general security proof of every future Go revision. Updates preserve operator files and provide bounded binary rollback; see [Updates & Recovery](Updates-and-Recovery).

## Sharing diagnostics

Do not post config/profile dumps, token bytes, WEB Proxy links or unredacted MTProxy logs. `systemctl status`, process listings and `journalctl` can include credentials or sensitive operational data. Inspect locally and redact before filing an issue.

Use the private reporting route described in repository SECURITY.md when available. If it is not enabled, request a private contact without disclosing exploit details publicly. Component licensing boundaries are documented in [THIRD_PARTY_NOTICES.md](https://github.com/Vladercool/TProxyKit/blob/main/THIRD_PARTY_NOTICES.md).
