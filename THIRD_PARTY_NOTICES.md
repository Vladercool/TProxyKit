# Third-party boundaries

Checked 2026-10-07 against the official repositories. This repository contains original wrapper code, tests and documentation, not vendored upstream implementations, binaries or assets.

| Component | Relationship and licensing evidence |
|---|---|
| [telegramdesktop/tproxy-server](https://github.com/telegramdesktop/tproxy-server/tree/c8adb8b7c6b7fc46c12ae3acb68be9070c26a8e8) | Fetched at runtime. The reviewed tree has no repository-level LICENSE file. Public availability is not an inferred permissive redistribution license. Its deployment-file hashes and small interface/encoding test vectors are used for compatibility. |
| [TelegramMessenger/MTProxy](https://github.com/TelegramMessenger/MTProxy) | Fetched/built by the official deployment. Its repository includes [GPLv2](https://github.com/TelegramMessenger/MTProxy/blob/master/GPLv2); consult file-level notices and dependencies before redistribution. |
| [Caddy](https://github.com/caddyserver/caddy/blob/master/LICENSE) | Downloaded by upstream's checksum-pinned deployment. Not included here; consult the distributed component's license and notices. |
| Go toolchain, Bats, ShellCheck, shfmt and GitHub Actions | Build/test tools, not shipped in the project archive. Their own terms apply. |

The MIT license covers this project's original material only. It does not relicense fetched components or grant Telegram trademark rights. Telegram and related names belong to their respective owners. This project is independent and not endorsed by Telegram.
