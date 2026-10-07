# Operations and recovery

## State and compatibility

`/var/lib/tproxy-installer/deployment.json` is root-only metadata: schema/project version, domain, inbound IPv4, ACME email, exact upstream SHA/selection label, lifecycle phase, site creation ownership and per-file resource hashes. It contains no proxy secret value. Config/profiles/token remain authoritative in `/etc/tproxy-server`; backend settings remain in `/etc/mtproxy`.

Lifecycle phases are `installing`, `ready` and `removed`. An installation does not become `ready` until endpoint, TLS and backend protection checks pass. The wrapper does not infer successful deployment from an existing binary alone.

Default selection asks the official GitHub latest-release endpoint. HTTP 404 means no stable release and selects official `HEAD`; rate limiting, malformed responses and network failures abort. Tags resolve to exact commits, including annotated tags. An explicit full SHA or official tag is available with `--upstream-ref`.

Every fetch verifies the resolved commit. SHA256 checks cover the reviewed deployment files and BASE_PATH encoding document, followed by shell syntax and transformation-anchor checks. A mismatch aborts before activation. Runtime-only changes are permitted by this contract; it is not a whole-repository security audit. Upstream retains control of its pinned Caddy, Go and MTProxy dependencies.

## Updates

The wrapper holds `/run/lock/tproxy-installer.lock` and `/run/lock/tproxy-server-update.lock`. It removes the reviewed child updater's redundant lock acquisition to avoid self-deadlock. The remaining updater is checksum-gated upstream code with bounded curl checks. It tests/builds a relay candidate and changes only the relay binary/service.

Before activation, the wrapper saves the old binary and deployment metadata to a root-only update backup. It hashes config, profiles, token key, backend environment, Caddyfile and public-site files before/after. Successful health/readiness, HTTPS, firewall and preservation checks precede metadata commit. Update does not rotate credentials or refresh backend dependencies.

The EXIT trap restores the binary on failure and checks local health/readiness. Backup paths are printed without credential contents. A failed rollback leaves the backup in place and reports failure. There is no claim that rollback reverses arbitrary filesystem mutations or SIGKILL/power loss.

## Adoption

Use `install --adopt` with the existing deployment's actual domain, inbound IPv4 and ACME email. Adoption requires the previous wrapper's `upstream.commit` provenance, a compatible source revision, exact service/Caddy/persisted firewall configuration, existing valid token key, matching secrets and NAT mapping, plus healthy endpoints.

The existing profile's secret is preserved. If carrier mode is not `websocket`, only that field changes, with a root-only rollback copy. The existing site is classified as operator-owned even if the old wrapper originally created it. It cannot be deleted by `--remove-site`.

A missing provenance file, missing token key, custom service drop-in or custom Caddyfile is a manual migration boundary. Back up the deployment; compare it with the official reference configuration and resolve each difference deliberately. Do not fabricate provenance or delete healthy configuration merely to make this wrapper accept it. Legacy token migration must first follow the official reviewed upstream migration procedure.

## Removal

The manifest's exact allowlisted runtime paths and hashes establish removal candidates. Effective unit fragments and drop-ins must still match the managed integration; the backend table must contain only the expected protection. Changed/foreign files and extra firewall objects stop removal before services are stopped. The wrapper never runs Docker cleanup during uninstall.

`--purge` additionally selects unchanged owned configuration and secret files. The daily refreshed `/etc/mtproxy/proxy-multi.conf` is intentionally retained; it cannot be matched reliably to its original content hash. The MTProxy source/build tree is retained except for the owned executable. A `tproxy-server.previous` updater backup is also retained.

`--remove-site` requires recorded creation ownership and rejects symlink-containing trees. It explicitly removes current regular files in that dedicated site, including later operator changes. Keep your own backup if needed. Adopted or pre-existing sites are retained.

Uninstall does not remove packages, users, toolchains, backups, certificates or empty configuration directories. Those may serve other processes or contain recoverable data. Purge is not secure erasure. To reinstall, review and archive remaining paths and `deployment.json` first; the wrapper deliberately refuses to overwrite a `removed` deployment automatically.

## Failed first installation

An interrupted first install may have installed packages, downloaded sources, written canonical config and enabled some services. Metadata remains `installing`; an automatic retry is refused. It does not have a complete ownership manifest, so automatic uninstall also refuses.

1. Preserve `/var/lib/tproxy-installer`, `/etc/tproxy-server`, `/etc/mtproxy`, the public site and any existing backups in root-only storage. Never publish these files.
2. Check DNS/ACME, service journals, route source/egress and provider firewall. Redact credentials before sharing diagnostics.
3. Compare actual resources against the recorded revision and official reference topology. Restore from a known host snapshot, or complete/manual-remove only resources whose ownership you established.
4. Do not simply delete the lifecycle marker and rerun the full installer over partial resources. That bypasses recovery safeguards.

## Optional old-container migration

`install --remove-obsolete` recognizes only the two explicitly named historical container/image pairs in the code. It preserves Docker images, volumes, sources and unrelated containers. All site/deployment preflights run first; port availability is checked after requested removal. Container removal is not part of the installation rollback transaction. Use this option only after verifying backups and identity.
