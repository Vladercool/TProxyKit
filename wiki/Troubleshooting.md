# Troubleshooting

Start with `bash install.sh status` on an installed host. Record the failing check and exact error before changing configuration. A successful health response alone does not prove backend readiness or public reachability.

> [!WARNING]
> Diagnostics can contain secrets, process arguments or private deployment information. Inspect locally and redact before sharing. Do not publish `show-link` output or config/profile/token files.

| Symptom | Likely area | What to check |
|---|---|---|
| DNS validation fails | DNS/local resolver | `getent ahostsv4 proxy.example.com`; every resolved IPv4 must match the intended inbound address |
| Domain points to another IPv4 | DNS target or wrong `--ip` | Correct DNS or the deployment input; do not substitute measured egress for inbound |
| TCP 80/443 occupied | Existing service/container | Inspect listening processes with `ss -lntp`; resolve ownership rather than killing arbitrary services |
| HTTPS/ACME failure | DNS, AAAA, forwarding, Caddy | Public 80/443, provider firewall, certificate errors and incorrect IPv6 records |
| Health endpoint fails | Relay startup/listener/config | Check `tproxy-server.service`, its journal and local 8081 listener |
| Health OK, readiness fails | Backend connectivity | Check MTProxy, secret consistency, NAT mapping and Telegram DC access |
| NAT mismatch | Changed route or provider egress | Compare status measurements with the intended provider mapping; review backend settings privately |
| Upstream compatibility refusal | Changed deployment contract | Use a reviewed wrapper update; do not remove checksum/anchor checks |
| Update rolled back | Candidate or post-update verification | Read the original failure and reported rollback result; retain the named backup |
| Rollback itself fails | Previous binary cannot restart/become ready | Preserve backups and configuration; follow [Updates & Recovery](Updates-and-Recovery) |
| Uninstall ownership refusal | Changed/missing file or integration | Review the exact path, unit drop-ins and backend table; do not force manifest hashes |
| Bootstrap cannot find release | Incomplete publication or network | Check [installer releases](https://github.com/Vladercool/TProxyKit/releases); current snapshot has no latest stable release and an unset bootstrap identity |
| Checksum failure | Corruption or inconsistent assets | Stop; inspect the release and obtain trusted assets. Never execute the failed download |
| show-link unavailable | Unsupported host or missing/invalid installed config/profile | Confirm root/supported host and completed installation; use recovery guidance for partial state |
| Status reports firewall failure | Missing or altered backend protection | Inspect `tproxy-firewall.service` and the dedicated nftables chain; verify provider protection separately |
| Already installed but extra options refused | Managed no-op semantics | Use `update` for relay versions; installation is not a site replacement command |

## Local diagnostic commands

Run only what corresponds to the failure:

```bash
systemctl is-active caddy mtproxy tproxy-server tproxy-firewall
ss -lntp
curl --noproxy '*' -fsS --max-time 2 http://127.0.0.1:8081/healthz
curl --noproxy '*' -fsS --max-time 2 http://127.0.0.1:8081/readyz
nft -j list chain inet tproxy_backend local_backend
```

Expected endpoint bodies are `ok` and `ready`. Check public HTTPS with your own domain:

```bash
curl --noproxy '*' -4fsS --max-time 5 https://proxy.example.com/ -o /dev/null
```

For local log inspection:

```bash
journalctl -u tproxy-server -u mtproxy -u caddy -u tproxy-firewall -n 100 --no-pager
```

These are diagnostics, not repair commands. Do not flush the global ruleset, delete lifecycle state or rerun the full installer over a partial deployment. Use [Updates & Recovery](Updates-and-Recovery) or [Uninstall & Cleanup](Uninstall-and-Cleanup) for the relevant lifecycle boundary.
