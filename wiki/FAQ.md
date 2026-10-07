# FAQ

### What is TProxyKit?
A deployment and lifecycle helper for the official Telegram WEB Proxy stack on a dedicated Debian 13 server. See [Home](Home).

### Is it an official Telegram project?
No. It is independent and not affiliated with or endorsed by Telegram.

### Does it use official components?
Yes: official `telegramdesktop/tproxy-server` and `TelegramMessenger/MTProxy`, with Caddy and the reference host integrations. Component terms remain separate from the wrapper license.

### Is this a classic MTProto proxy?
The public client interface is Telegram WEB Proxy. Official MTProxy is the local backend. A WebSocket transport alone does not establish WEB Proxy compatibility. See [How It Works](How-It-Works).

### Why does it need a domain and TCP 80/443?
Caddy needs a correctly routed hostname for HTTPS/certificate handling. Clients connect through HTTPS on 443; the reference deployment also requires public port 80 for its HTTP/certificate flow.

### Why only Debian 13 x86_64?
The installer explicitly enforces that supported host and requires booted systemd. Other distributions and architectures are not supported by this wrapper; this is not a claim that the protocol inherently requires Debian.

### Is Quick Install ready?
Not at this snapshot: bootstrap identity is unconfigured and a latest stable installer release is unavailable. Use the inspected source route in [Getting Started](Getting-Started).

### Does update rotate my secret or replace my site?
No. Ordinary relay updates preserve the secret, token key, base path and public site. They do not upgrade the whole backend stack or TProxyKit itself. See [Updates & Recovery](Updates-and-Recovery).

### Can I automate installation?
Yes. Supply `--domain`, `--ip`, `--email` and `--yes`. Missing required values fail instead of prompting. See [Commands](Commands).

### How do I get the proxy link?
Run `bash install.sh show-link` as root on the installed host. Treat both printed links as credentials.

### Why can an update reject newer upstream?
The selected source must still match the reviewed deployment contract. A changed interface needs a reviewed wrapper update; the tool does not silently fall back to an older revision.

### Why can uninstall refuse a resource?
A changed hash, missing file, unexpected override or altered backend table breaks the evidence used to authorize removal. Review the difference instead of forcing deletion. See [Uninstall & Cleanup](Uninstall-and-Cleanup).

### What is install --adopt?
It imports a validated reference deployment into public-wrapper management while preserving operator state. It requires legacy provenance and may refuse customized or ambiguous installations. See [adoption](Updates-and-Recovery).

### Can I put Cloudflare or another CDN proxy in front?
The current project recommends DNS-only operation without a CDN proxy. This Wiki does not provide a supported CDN configuration.

### What if inbound and outbound IPv4 differ?
That can be normal provider NAT. TProxyKit distinguishes inbound DNS, local route source and measured egress. It refuses an unverified DNS-as-egress fallback; unusual routing still needs actual Telegram testing.

### Does purge erase every credential copy?
No. Backups and other retained host data may contain credentials. Purge is not secure erasure; see [Security](Security).
