# Security

## Reporting

Before publication, maintainers must enable GitHub private vulnerability reporting. Then use the repository's **Security → Report a vulnerability** flow. Do not publish live links, secrets, token keys, config dumps or unredacted logs in public issues. If private reporting is unavailable, ask for a private contact without disclosing the exploit or credentials publicly.

Only the latest reviewed wrapper release is maintained initially. A fail-closed upstream compatibility rejection is expected behavior, not a reason to disable checks.

## Trust model

This is a privileged deployment tool. Trust includes the wrapper repository and its maintainers, GitHub/release infrastructure, HTTPS PKI, official upstream repositories, pinned dependency downloads, package repositories and the root-controlled host. Fetching a commit by SHA proves which revision was used; it does not establish that its code is trustworthy.

The one-liner downloads mutable bootstrap code. The subsequent SHA256 check detects installer corruption or substitution inconsistent with the manifest; a checksum fetched from the same compromised release is not independent authentication. Releases are not signed or independently attested. Inspect and pin a release for stronger operational reproducibility; see [releasing](docs/RELEASING.md).

## Credentials and host boundaries

- Profiles and token key remain in canonical upstream locations, with restrictive permissions and systemd credentials for the relay. Metadata has paths/hashes and deployment identity, not another secret value.
- The MTProxy reference service uses its secret in its process arguments/environment. Root and sufficiently privileged host diagnostics can observe it. Do not claim argv secrecy for the backend.
- Install/update/status suppress client links. `show-link` is the deliberate disclosure command. No persistent installer transcript is generated; external shell/session recording is outside this tool's control.
- Private temporary directories, checked output paths and root-owned operator paths reduce symlink risks. There is no protection against a concurrent malicious root process; filesystem checks are not atomic security boundaries against root.
- Runtime source changes can pass the deployment-file contract gate. That gate validates known deployment interfaces, not arbitrary future Go code. The upstream updater runs source tests and candidate config validation; maintainers still need to review runtime changes.
- Public relay/admin sockets must remain loopback-only. MTProxy wildcard ports require both host and provider firewalls. The reviewed upstream firewall delete/recreate sequence is not atomic.
- HTTPS egress measurement may differ from Telegram routing. Validate the actual provider/NAT/client combination.

## Removal and recovery

Uninstall checks recorded hashes and effective service ownership before mutation. Modified resources stop removal. The daily refreshed Telegram DC list, source/build tree, packages, users, ACME storage and backups are retained. Site deletion requires recorded creation ownership and an explicit flag; an adopted site is retained.

A partial fresh installation is journaled as `installing`, not declared healthy. There is no full-host transaction or destructive automatic retry. Binary rollback does not restore arbitrary changes made by a hostile future upstream. Keep independent backups and follow [operations](docs/OPERATIONS.md).

## Review record

The [validation record](docs/VALIDATION.md) separates deterministic checks, independent review and unexecuted real-host acceptance. Codex Security was not installed/available for this work; manual security review plus an independent agent review were used instead.
