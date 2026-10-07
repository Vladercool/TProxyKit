#!/usr/bin/env bash
# Replace OWNER/REPO once when publishing this project.
set +x
BOOT_REPO=OWNER/REPO
bootstrap_download() {
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --tlsv1.2 --connect-timeout 10 --max-time 120 --output "$2" "$1"
}
bootstrap_release() {
  local url tag
  url=$(curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --tlsv1.2 --connect-timeout 10 --max-time 30 --output /dev/null --write-out '%{url_effective}' \
    "https://github.com/$BOOT_REPO/releases/latest") || return 1
  [[ "$url" == "https://github.com/$BOOT_REPO/releases/tag/"* ]] || return 1
  tag=${url##*/}
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  printf '%s\n' "$tag"
}
bootstrap_verify() (
  cd "$1" || exit 1
  # Never pass untrusted manifest paths to sha256sum.
  local line count=0 selected=
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[0-9a-f]{64}\ \ (install\.sh|bootstrap\.sh)$ ]] || exit 1
    if [[ "$line" == *'  install.sh' ]]; then
      selected=$line
      count=$((count + 1))
    fi
  done <SHA256SUMS
  [[ "$count" == 1 ]] || exit 1
  printf '%s\n' "$selected" | sha256sum --check --status
)
bootstrap_main() (
  set -euo pipefail
  umask 077
  local work tag base
  [[ "$BOOT_REPO" != OWNER/REPO ]] || {
    printf 'Publication incomplete: replace OWNER/REPO in bootstrap.sh.\n' >&2
    exit 1
  }
  tag=${WEBPROXY_RELEASE:-}
  if [[ -z "$tag" ]]; then tag=$(bootstrap_release); fi
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    printf 'Invalid stable release tag.\n' >&2
    exit 1
  }
  work=$(mktemp -d /tmp/webproxy-bootstrap.XXXXXX)
  trap 'cd /; rm -rf -- "$work"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  base="https://github.com/$BOOT_REPO/releases/download/$tag"
  bootstrap_download "$base/install.sh" "$work/install.sh" || exit 1
  bootstrap_download "$base/SHA256SUMS" "$work/SHA256SUMS" || exit 1
  bootstrap_verify "$work" || {
    printf 'Release checksum verification failed; nothing executed.\n' >&2
    exit 1
  }
  bash "$work/install.sh" "$@"
)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then bootstrap_main "$@"; fi
