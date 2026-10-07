# Getting Started

## Prepare the server

| Requirement | Before installation |
|---|---|
| Operating system | Dedicated Debian 13 x86_64 host with booted systemd |
| Privileges | Root Bash shell; `curl` available for downloading the installer |
| Domain | Lowercase ASCII hostname, for example `proxy.example.com` |
| IPv4 and DNS | All resolved IPv4 addresses must match the expected public inbound IPv4 |
| Public ingress | TCP 80 and 443 available for Caddy and forwarded to this host |
| Provider firewall | Permit required web/admin access; deny external 2398, 8888, 8080 and 8081 |
| Outbound access | GitHub, dependency/package downloads, ACME, IPv4 echo services and Telegram DCs |
| Existing software | No conflicting Caddy deployment, matching services or unowned backend firewall table |

Use DNS-only operation, without a CDN proxy in front. An incorrect AAAA record can break HTTPS even if IPv4 validation passes. Verify IPv6 routing or remove that incorrect record. See [NAT and network flow](How-It-Works).

## Quick Install: publication currently incomplete

The intended TProxyKit command is:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Vladercool/TProxyKit/main/bootstrap.sh)
```

> [!WARNING]
> Do not treat this as a working installation route yet. On 2026-10-07, the checked bootstrap still rejects its unset repository identity, and GitHub's latest stable release endpoint returns 404. Changing the URL in this command alone does not fix bootstrap configuration.

The maintainer must configure the repository identity and publish a stable installer release containing `install.sh` and `SHA256SUMS`. Until then, use an inspected source file as described below. After publication, bootstrap will verify the installer checksum before execution and forward command arguments. See [Security](Security) for the limits of this check.

## Obtain the current inspected source

The following downloads the exact repository revision used for this Wiki, without executing it:

```bash
curl --proto '=https' --proto-redir '=https' -fLSs \
  https://raw.githubusercontent.com/Vladercool/TProxyKit/8a902721f02a88924b8fb52fe3a85134d7c70607/install.sh \
  -o install.sh
```

Inspect the downloaded script before running it. This route pins the wrapper source; it does not provide a published release checksum or independent authentication. The relay's upstream version is selected separately during installation.

## Interactive installation

From the directory containing the inspected file, in a root shell:

```bash
bash install.sh install
```

| Prompt | Enter |
|---|---|
| Domain | The public hostname, such as `proxy.example.com` |
| Public IPv4 | The address clients reach through DNS, such as `203.0.113.10`; not necessarily the outbound address |
| ACME email | Your certificate contact address, such as `admin@example.com` |

The installer validates input, displays the configuration and asks for confirmation. Missing values prompt only when stdin is a terminal. A fresh install generates its own secret; do not supply one manually.

## Non-interactive installation

Replace these synthetic values with your deployment inputs:

```bash
bash install.sh install \
  --domain proxy.example.com \
  --ip 203.0.113.10 \
  --email admin@example.com \
  --yes
```

Missing required values fail. `--yes` approves the selected operation; it does not imply old-container removal, secret purge or website deletion.

## Public website

For a fresh deployment, optionally add `--site-dir /absolute/path/to/site`. Use trusted, root-owned static content with a regular `index.html`. A complete existing `/srv/tproxy-site` is preserved. Without supplied or existing content, a fresh install creates a neutral domain welcome page. See [Commands](Commands) for restrictions on re-runs and adoption.

## After installation

```bash
bash install.sh status
bash install.sh show-link
```

Status displays operational checks without the secret. `show-link` explicitly prints both private WEB Proxy links. Open the appropriate link in a client supporting Telegram WEB Proxy; do not share it in public issues.

Complete the project's [real VPS acceptance checks](https://github.com/Vladercool/TProxyKit/blob/main/docs/VALIDATION.md) before relying on the deployment. If installation stops midway, use [Updates & Recovery](Updates-and-Recovery), not a blind reinstall.
