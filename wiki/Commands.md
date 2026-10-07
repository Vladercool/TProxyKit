# Commands

All examples assume an inspected `install.sh` in the current directory. Operational commands require root on supported Debian/systemd; `help` does not. Running the file without a subcommand defaults to `install`.

## Command reference

| Command and syntax | Useful example | Behavior |
|---|---|---|
| `install [options]` | `bash install.sh install` | Prompts for missing deployment inputs on a terminal; fresh install or validated no-op |
| `update [--upstream-ref SHA_OR_TAG] [--yes]` | `bash install.sh update --yes` | Validates current deployment and updates only the relay when the resolved SHA differs |
| `status` | `bash install.sh status` | Shows versions, carrier, services, endpoint/TLS/firewall checks and NAT measurement; no credentials |
| `show-link` | `bash install.sh show-link` | Prints both private WEB Proxy links from installed config/profile |
| `uninstall [--purge] [--remove-site] [--yes]` | `bash install.sh uninstall --yes` | Removes owned runtime; automation keeps secrets and site unless explicitly selected |
| `help` | `bash install.sh help` | Prints supported usage without deployment prerequisites |

## Options

| Option | Applies to | Meaning |
|---|---|---|
| `--domain HOST` | install | Lowercase ASCII public hostname |
| `--ip IPV4` | install | Expected inbound IPv4; resolved IPv4 records must match exclusively |
| `--email EMAIL` | install | ACME contact email |
| `--site-dir DIR` | Fresh install | Absolute, root-safe static directory with regular `index.html`; existing complete site is preserved |
| `--adopt` | install | Adopt a validated reference deployment with legacy provenance |
| `--remove-obsolete` | Fresh install | Remove only recognized historical container/image pairs; not general Docker cleanup |
| `--upstream-ref SHA_OR_TAG` | Fresh install, update | Select an exact full commit SHA or official upstream tag |
| `--yes` | Operations requiring confirmation | Skip confirmation; install still requires all deployment inputs |
| `--purge` | uninstall | Additionally remove unchanged owned private configuration/secrets |
| `--remove-site` | uninstall | Additionally remove a site whose creation ownership was recorded |

`--yes` is accepted by the parser for other commands too, but does not add behavior to status, show-link or help. There is no separate dry-run or manual rollback subcommand.

## Interactive and automated use

```bash
bash install.sh install \
  --domain proxy.example.com --ip 203.0.113.10 \
  --email admin@example.com --yes
```

In automation, supply all three deployment inputs and `--yes`. Without a terminal, required confirmation fails instead of waiting for input. Interactive uninstall asks separately about secrets/site before final confirmation; the default answer is no.

## Re-runs and special cases

A managed installation re-run must use matching domain/IP/email and pass validation. It does not perform a version update. Supplying `--site-dir`, `--upstream-ref`, `--remove-obsolete` or `--adopt` to that managed no-op path is refused.

Adoption preserves the installed revision and site; do not combine it with site/version/obsolete-container overrides. See [Updates & Recovery](Updates-and-Recovery).

`--remove-obsolete` is limited to the historical pairs `tg-ws-proxy` with `valnesfjord/tg-ws-proxy-rs:2.5.2`, and `tgwebproxy` with `tgwebproxy:local`. An unexpected image is preserved and stops cleanup. Removal is not rolled back if later installation fails.

Status's success code reflects health/readiness, HTTPS and firewall checks. Read the displayed service states as well. An unavailable latest-version lookup does not invalidate successful local checks. A reported newer SHA is not yet proof that the compatibility gate will accept it.

For deletion details, read [Uninstall & Cleanup](Uninstall-and-Cleanup). For credential handling, read [Security](Security).
