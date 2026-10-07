# Uninstall & Cleanup

## Select the removal scope

```bash
# Interactive removal plan and confirmation:
bash install.sh uninstall

# Select private configuration purge, then confirm:
bash install.sh uninstall --purge

# Select removal of a wrapper-created website, then confirm:
bash install.sh uninstall --remove-site
```

Interactive mode may offer the remaining optional choices too. Check the final plan. For unattended runtime-only removal:

```bash
bash install.sh uninstall --yes
```

Add `--purge` and/or `--remove-site` explicitly when those actions are intended. `--yes` alone does not select either.

## What happens to each resource

| Resource | Normal runtime removal |
|---|---|
| Managed relay/MTProxy executables and dedicated Caddy runtime/integration | Removed after validation |
| Managed services, backend firewall service and refresh timer | Stopped/disabled; owned integration files removed |
| Private configuration, profiles and token key | Kept; unchanged owned files can be selected with `--purge` |
| Public website | Kept; `--remove-site` requires recorded creation ownership |
| Update/adoption backups and updater's previous binary | Kept |
| Packages, system users and Go toolchain | Kept |
| MTProxy source/build tree apart from owned executable | Kept |
| Caddy ACME storage and refreshed `/etc/mtproxy/proxy-multi.conf` | Kept even with purge |
| Unrelated Docker, services, sites and firewall configuration | Not selected; integration conflicts stop removal |

Removing Caddy also stops HTTPS serving of the preserved site. Retaining files does not mean the website remains online. Configuration directories and lifecycle metadata are retained; reinstall is a separate reviewed operation.

## Why ownership checks can stop uninstall

TProxyKit records managed paths and hashes and checks current service fragments/drop-ins and backend table structure. Removal may stop because a recorded file changed or disappeared, ownership is ambiguous, a service has unexpected overrides, or the firewall table has additional/different content.

This refusal prevents a filename match from authorizing deletion of an unrelated or modified resource. Review the reported difference instead of rewriting hashes to force acceptance. Automated removal requires `ready` metadata; an incomplete or already-removed deployment needs manual review.

## Website and secret cautions

A pre-existing or adopted site is never eligible for automatic site deletion. For a wrapper-created site, `--remove-site` selects its current files, including later operator edits; back them up if needed. Symlink-containing site trees are refused.

Purge is not secure erasure. Backups may retain credentials after canonical files are deleted. Keep those backups private and review their retention separately. See [Security](Security) and [recovery guidance](Updates-and-Recovery).
