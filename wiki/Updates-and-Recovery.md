# Updates & Recovery

## Update the relay

```bash
bash install.sh update
# Unattended confirmation:
bash install.sh update --yes
```

The managed deployment must be in `ready` state. The update sequence is:

1. Lock and validate the installed topology, secret consistency, NAT and running stack.
2. Select official upstream and resolve its exact commit.
3. If the installed SHA matches, report **Already up to date** and stop.
4. For a different SHA, fetch it and check deployment compatibility and reference integrations.
5. Confirm the update and back up the current binary/metadata.
6. Run the reviewed upstream relay updater to test, build and activate the candidate.
7. Check health/readiness, HTTPS, backend protection and preservation of operator files.
8. Record the new installed SHA only after success.

An ordinary update preserves the secret, token key, base path and public site. It does not rerun the full installer or upgrade Caddy/MTProxy dependencies. It also does not update your local copy of TProxyKit itself.

## Version policy

The wrapper prefers the official relay's latest stable GitHub release. A no-release response selects the official default-branch HEAD; network/API failures do not trigger that fallback. `--upstream-ref` optionally selects a full 40-character SHA or official tag.

The selected revision must pass the deployment-file/encoding-document compatibility gate. A mismatch stops activation and requires a reviewed wrapper change. There is no automatic downgrade to an older compatible revision.

The gate checks deployment interfaces, not all future runtime behavior. A SHA identifies source; it is not proof that arbitrary upstream code is safe.

## Rollback boundaries

Root-only update backups are stored below `/var/lib/tproxy-installer/backups/`. On failure after rollback is armed, cleanup attempts to restore the previous relay binary, restart it and verify local health/readiness. After successful binary recovery it restores saved deployment metadata. Failure is reported and backups are retained.

Rollback is not a filesystem snapshot. It does not guarantee recovery from arbitrary upstream file mutations, host failure, power loss or SIGKILL. Do not assume it restores every service, package or site change. There is no supported `rollback` CLI command; use the repository's [operations guidance](https://github.com/Vladercool/TProxyKit/blob/main/docs/OPERATIONS.md) for manual recovery planning.

## Adopt a reference installation

```bash
bash install.sh install --adopt \
  --domain proxy.example.com --ip 203.0.113.10 \
  --email admin@example.com --yes
```

Use the existing deployment's actual values. Adoption requires `/var/lib/tproxy-installer/upstream.commit` from the earlier wrapper, a compatible reference revision, valid existing token key, matching service/Caddy/firewall configuration, matching NAT and a healthy stack.

It retains the secret, token bytes, base path and site. If needed, it changes the profile carrier to `websocket` with a rollback copy. The adopted site is treated as operator-owned and cannot be removed automatically by `--remove-site`.

Customized or ambiguous installations can be refused. Do not fabricate provenance, remove a working token key or delete configuration to bypass checks.

## Partial first install or removal

| Recorded state | Meaning |
|---|---|
| `installing` | Fresh installation did not finish all verification; some host changes may already exist |
| `ready` | Managed deployment completed its verification |
| `removed` | Managed runtime was removed; retained data still needs review before reinstall |

Metadata lives in `/var/lib/tproxy-installer/deployment.json`. An incomplete first install lacks a completed ownership manifest; automatic retry and uninstall are refused. Preserve canonical configuration and backups, inspect the actual failure, and follow [documented recovery](https://github.com/Vladercool/TProxyKit/blob/main/docs/OPERATIONS.md#failed-first-installation). Do not delete lifecycle metadata and rerun blindly.

Use [Troubleshooting](Troubleshooting) to gather diagnostics, and redact them before sharing.
