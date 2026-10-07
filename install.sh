#!/usr/bin/env bash
# Reviewed reference deployment; secrets are never command-line arguments here.
set +x

VERSION=1.0.0
UPSTREAM_REPO=telegramdesktop/tproxy-server
UPSTREAM_COMMIT=
DOMAIN=
INBOUND_IP=
ACME_EMAIL=
CONFIG=/etc/tproxy-server/config.json
PROFILES=/etc/tproxy-server/profiles.json
STATE=/var/lib/tproxy-installer
SECRET=
LOCAL_IP=
EGRESS_IP=
WORK=
ROLLBACK=
UPSTREAM_REF=
UPSTREAM_LABEL=
RELEASE_TAG=
COMMAND=install
YES=0
ADOPT=0
PURGE=0
REMOVE_SITE=0
REMOVE_OLD=0
SITE=
BINARY_ROLLBACK=
STATE_ROLLBACK=
RELAY=/usr/local/bin/tproxy-server
META=
SITE_OWNED=false

die() {
  printf 'ERROR: %s\n' "$*" >&2
  return 1
}
info() { printf '==> %s\n' "$*"; }
safe_cwd() { cd /; }

valid_secret() { [[ "$1" =~ ^([0-9a-f]{32}|dd[0-9a-f]{32})$ ]]; }
valid_base_path() {
  [[ ${#1} -le 128 ]] && { [[ -z "$1" ]] || [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*(/[A-Za-z0-9][A-Za-z0-9_-]*)*$ ]]; }
}
valid_ipv4() {
  local octet
  local -a parts
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  IFS=. read -r -a parts <<<"$1"
  for octet in "${parts[@]}"; do
    [[ ${#octet} -le 3 ]] && ((10#$octet <= 255)) || return 1
  done
}

select_secret() {
  local profiles=$1 pending=$2
  if [[ -e "$profiles" ]]; then
    SECRET=$(jq -er 'if (.profiles | length) == 1 then .profiles[0].secret else error("expected one profile") end' "$profiles") || return 1
  elif [[ -e "$pending" ]]; then
    SECRET=$(cat "$pending") || return 1
  else
    SECRET=$(openssl rand -hex 16) || return 1
  fi
  valid_secret "$SECRET" || die 'Invalid existing secret; refusing to rotate it.'
}

share_links() {
  local host=$1 path=$2 client_secret=$SECRET address=$1 escapes
  valid_secret "$SECRET" && valid_base_path "$path" || return 1
  if [[ -n "$path" ]]; then
    # Reproduce upstream byte encoding without ever storing binary NULs in Bash.
    escapes=$(printf '%s' "$SECRET" | sed 's/../\\x&/g')
    client_secret=$({
      printf '\x70'
      printf '%b' "$escapes"
    } | base64 | tr '+/' '-_' | tr -d '=\n') || return 1
    address="$host/$path"
  fi
  printf 'https://t.me/webproxy?server=%s&secret=%s\n' "${address//\//%2F}" "$client_secret"
  printf 'tg://webproxy?server=%s&secret=%s\n' "${address//\//%2F}" "$client_secret"
}

wait_endpoint() {
  local url=$1 expected=$2 attempts=${3:-30} attempt body
  for ((attempt = 0; attempt < attempts; attempt++)); do
    if body=$(curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 "$url" 2>/dev/null) && [[ "$body" == "$expected" ]]; then
      return 0
    fi
    if ((attempt + 1 < attempts)); then sleep 1; fi
  done
  die "Endpoint did not become $expected within $attempts bounded attempts: $url"
}

check_dns() {
  local records
  records=$(getent ahostsv4 "$1" | awk '$2 == "STREAM" {print $1}' | sort -u) || return 1
  [[ "$records" == "$2" ]] || die 'DNS IPv4 does not resolve exclusively to the expected inbound address; no cleanup performed.'
}

check_ports() {
  local mode=$1 listeners line pid=
  listeners=$(ss -H -lntp '( sport = :80 or sport = :443 )') || return 1
  [[ -z "$listeners" ]] && return 0
  if [[ "$mode" == existing ]]; then
    pid=$(systemctl show --property=MainPID --value caddy.service) || return 1
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    while IFS= read -r line; do
      [[ "$line" == *'"caddy",pid='"$pid"','* ]] || die 'Public port is occupied by a process outside the existing Caddy service.' || return 1
    done <<<"$listeners"
  else
    die 'Port 80 or 443 is occupied. Resolve the collision before installation.'
  fi
}

obsolete_identity() {
  [[ "$1:$2" == 'tg-ws-proxy:valnesfjord/tg-ws-proxy-rs:2.5.2' || "$1:$2" == 'tgwebproxy:tgwebproxy:local' ]]
}

remove_obsolete() {
  local name image id
  command -v docker >/dev/null || return 0
  docker info >/dev/null 2>&1 || die 'Docker is installed but unavailable; refusing ambiguous cleanup.' || return 1
  for name in tg-ws-proxy tgwebproxy; do
    id=$(docker container ls -aq --filter "name=^/${name}$") || return 1
    [[ -n "$id" ]] || continue
    image=$(docker inspect --format '{{.Config.Image}}' "$id") || return 1
    obsolete_identity "$name" "$image" || die "Container $name has an unexpected image; preserved." || return 1
    docker rm -f "$id" >/dev/null || return 1
  done
  # Old source directories and Docker images are deliberately retained.
}

discover_nat() {
  local probe candidate
  LOCAL_IP=$(ip -4 route get 149.154.175.50 | sed -n 's/.*[[:space:]]src[[:space:]]\+\([0-9.]\+\).*/\1/p' | head -n 1) || return 1
  valid_ipv4 "$LOCAL_IP" || die 'Cannot determine the local MTProxy source IPv4.' || return 1
  EGRESS_IP=
  for probe in https://api.ipify.org https://ifconfig.co/ip https://icanhazip.com; do
    candidate=$(curl --noproxy '*' -4fsS --connect-timeout 5 --max-time 10 --proto '=https' --proto-redir '=https' "$probe" 2>/dev/null | tr -d '[:space:]') || continue
    if valid_ipv4 "$candidate"; then
      EGRESS_IP=$candidate
      break
    fi
  done
  [[ -n "$EGRESS_IP" ]] || die 'No verified egress IPv4; DNS inbound is not a safe NAT fallback.'
}

root_path() {
  local path=$1 current=/ part mode
  local -a parts
  [[ "$path" == /* ]] || return 1
  IFS=/ read -r -a parts <<<"${path#/}"
  for part in "${parts[@]}"; do
    current="${current%/}/$part"
    [[ ! -L "$current" ]] || die "Symlink refused: $current" || return 1
    [[ -e "$current" ]] || continue
    [[ "$(stat -c %u "$current")" == 0 ]] || die "Path must be root-owned: $current" || return 1
    mode=$(stat -c %a "$current") || return 1
    (((8#$mode & 0022) == 0)) || die "Writable operator path refused: $current" || return 1
  done
}

check_token_key() {
  local path=${1:-/etc/tproxy-server/token.key}
  [[ ! -L "$path" ]] || die 'Token key may not be a symlink.' || return 1
  if [[ -e "$path" ]]; then
    [[ -f "$path" && "$(stat -c %s "$path")" == 32 ]] || die 'Invalid token key; it will not be replaced.' || return 1
    local mode
    mode=$(stat -c %a "$path") || return 1
    (((8#$mode & 0077) == 0)) || die 'Token key has group/other permissions; repair permissions explicitly.' || return 1
  fi
}

secret_file_mode() {
  local path=$1 allowed=$2 mode
  [[ ! -L "$path" ]] || die "Secret symlink refused: $path" || return 1
  [[ -e "$path" ]] || return 0
  [[ -f "$path" ]] || die "Secret must be a regular file: $path" || return 1
  mode=$(stat -c %a "$path") || return 1
  (((8#$mode & 0077 & ~8#$allowed) == 0)) || die "Unsafe secret permissions on $path; see README." || return 1
  if [[ "$allowed" == 0040 ]] && (((8#$mode & 0040) != 0)); then
    [[ $(stat -c %G "$path") == mtproxy ]] || die "Secret file group must be mtproxy: $path" || return 1
  fi
}

firewall_dropin() {
  printf '[Unit]\nReloadPropagatedFrom=nftables.service\n'
}

firewall_is_protected() {
  jq -e '
    any(.nftables[]; .chain? | .family == "inet" and .table == "tproxy_backend" and .name == "local_backend" and .type == "filter" and .hook == "input" and .prio == -10) and
    ([.nftables[] | .rule? | select(.) | .expr] == [[
      {"match":{"op":"!=","left":{"meta":{"key":"iifname"}},"right":"lo"}},
      {"match":{"op":"==","left":{"payload":{"protocol":"tcp","field":"dport"}},"right":{"set":[2398,8888]}}},
      {"drop":null}
    ]])' >/dev/null
}

patch_installer() {
  local file=$1
  [[ $(grep -Fc '"backend":"127.0.0.1:2398"' "$file") == 1 ]] || return 1
  # shellcheck disable=SC2016 # Match literal upstream Bash source, not an expansion.
  [[ $(grep -Fc 'public_address="$(getent' "$file") == 1 ]] || return 1
  [[ $(grep -Fc '# The client-facing proxy secret.' "$file") == 1 ]] || return 1
  awk '
    /^# The client-facing proxy secret[.]/ {exit}
    /public_address="\$\(getent/ {
      print "\techo \"No measured egress IPv4; refusing DNS NAT fallback\" >&2"
      print "\texit 1"
      next
    }
    /^cat > \/etc\/mtproxy\/mtproxy.env/ {
      print "[[ \"$local_address\" == \"$TPROXY_VERIFIED_LOCAL\" && \"$public_address\" == \"$TPROXY_VERIFIED_EGRESS\" ]] || { echo \"NAT observation changed; refusing activation\" >&2; exit 1; }"
    }
    /if curl --fail --silent --output \/dev\/null/ {
      sub(/--fail --silent/, "--fail --silent --connect-timeout 1 --max-time 2")
    }
    {sub(/"backend":"127.0.0.1:2398"/, "\"backend\":\"127.0.0.1:2398\",\"carrier_mode\":\"websocket\""); print}
  ' "$file" >"$file.reviewed" || return 1
  bash -n "$file.reviewed" || return 1
  mv "$file.reviewed" "$file"
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  set +e
  if [[ -n "$BINARY_ROLLBACK" ]]; then
    if restore_binary "$BINARY_ROLLBACK"; then
      [[ -z "$STATE_ROLLBACK" ]] || cp -p "$STATE_ROLLBACK" "$STATE/deployment.json"
      printf 'Previous relay binary restored.\n' >&2
    else
      printf 'ERROR: binary rollback failed; backup retained at %s\n' "$BINARY_ROLLBACK" >&2
    fi
  fi
  if [[ -n "$ROLLBACK" ]]; then
    if install -o root -g tproxy -m 0400 "$ROLLBACK" "$PROFILES.rollback" &&
      mv -f "$PROFILES.rollback" "$PROFILES" &&
      systemctl restart tproxy-server.service &&
      wait_endpoint http://127.0.0.1:8081/healthz ok 20 &&
      wait_endpoint http://127.0.0.1:8081/readyz ready 20; then
      printf 'Previous profiles restored and ready; backup: %s\n' "$ROLLBACK" >&2
    else
      printf 'ERROR: rollback failed; preserve backup and inspect services: %s\n' "$ROLLBACK" >&2
    fi
  fi
  safe_cwd
  if [[ "$WORK" == /run/tproxy-installer.* && -d "$WORK" && ! -L "$WORK" ]]; then rm -rf -- "$WORK"; fi
  unset SECRET
  exit "$status"
}

validate_existing() {
  local backend_secret nat expected path
  for path in "$CONFIG" "$PROFILES" /etc/mtproxy/mtproxy.env /etc/caddy/Caddyfile /etc/systemd/system/tproxy-server.service /etc/systemd/system/mtproxy.service /etc/systemd/system/tproxy-firewall.service; do
    [[ -f "$path" ]] || die "Incomplete deployment ($path missing); preserved. See README recovery." || return 1
    root_path "$path" || return 1
  done
  [[ -x /usr/local/bin/tproxy-server && -x /usr/local/bin/caddy && -x /opt/MTProxy/objs/bin/mtproto-proxy ]] || die 'Partial deployment: a binary is missing. No reinstall attempted.' || return 1
  jq -e --arg host "$DOMAIN" '.public_hostname == $host and .listen == "127.0.0.1:8080" and .admin_listen == "127.0.0.1:8081" and .profiles_file == "/run/credentials/tproxy-server.service/profiles.json" and ((.token_key_file // "/etc/tproxy-server/token.key") == "/etc/tproxy-server/token.key")' "$CONFIG" >/dev/null || die 'Existing config differs from supported reference topology; preserved.' || return 1
  jq -e '.profiles | length == 1 and .[0].backend == "127.0.0.1:2398"' "$PROFILES" >/dev/null || return 1
  if ((ADOPT == 0)); then
    jq -e '.profiles[0].carrier_mode == "websocket"' "$PROFILES" >/dev/null || die 'Managed profile must use websocket carrier mode.' || return 1
  fi
  valid_base_path "$(jq -er '.base_path // ""' "$CONFIG")" || return 1
  [[ -f /etc/tproxy-server/token.key ]] || die 'Legacy installation without token.key: use reviewed upstream update-relay.sh migration first.' || return 1
  backend_secret=$(sed -n 's/^MTPROXY_SECRET=//p' /etc/mtproxy/mtproxy.env)
  expected=$SECRET
  [[ ${#expected} == 34 ]] && expected=${expected:2}
  [[ "$backend_secret" == "$expected" ]] || die 'Relay and MTProxy secrets disagree; neither is changed.' || return 1
  nat=$(sed -n 's/^MTPROXY_NAT_ARGS=//p' /etc/mtproxy/mtproxy.env)
  expected=
  [[ "$LOCAL_IP" == "$EGRESS_IP" ]] || expected="--nat-info $LOCAL_IP:$EGRESS_IP"
  [[ "$nat" == "$expected" ]] || die 'Existing NAT mapping differs from current measurement. Review MTPROXY_NAT_ARGS explicitly.' || return 1
  /usr/local/bin/tproxy-server -config "$CONFIG" -profiles-file "$PROFILES" -check
}

verify_stack() {
  local service listeners
  for service in caddy tproxy-firewall mtproxy tproxy-server; do
    systemctl is-active --quiet "$service" || die "Service is inactive: $service" || return 1
  done
  wait_endpoint http://127.0.0.1:8081/healthz ok || return 1
  wait_endpoint http://127.0.0.1:8081/readyz ready || return 1
  # Validate the actual expression, not merely the existence of an empty table.
  nft -j list chain inet tproxy_backend local_backend | firewall_is_protected || die 'Expected backend protection rule is absent or ambiguous.' || return 1
  listeners=$(ss -H -lnt '( sport = :8080 or sport = :8081 )') || return 1
  [[ -n "$listeners" ]] || return 1
  while read -r _ _ _ address _; do
    [[ "$address" == 127.0.0.1:8080 || "$address" == 127.0.0.1:8081 ]] || die 'Relay/admin listener is not loopback-only.' || return 1
  done <<<"$listeners"
  local attempt
  for ((attempt = 0; attempt < 30; attempt++)); do
    if curl --noproxy '*' -4fsS --connect-timeout 2 --max-time 5 --proto '=https' "https://$DOMAIN/" >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  die 'Public HTTPS failed. Check DNS, provider firewall, Caddy and ACME.'
}

# Reviewed deployment contract; runtime source changes are not pinned.
compatibility_manifest() {
  cat <<'MANIFEST'
6a9b1fe3d31819c6dd949dbf246089576cbe1967a331bd3ed72d685a751dd479  BASE_PATH.md
7f6e9e418f31dd631f9c59d765cb942412464375b4bc5e9b46146dbcf93813e0  deploy/Caddyfile
7a4f51af98b69006dea6833fb12845e7a193f72cb3f87fb6bfc285449f0f49e7  deploy/caddy.service
2f9c884947f4937de85037ddeaf0571d73cb8ce5993a80f0834098c6b662f885  deploy/ensure-token-key.sh
a454baa6cbde8f79678797429d9f3a8f806f08c2f900abadf6babcc317018977  deploy/firewall.nft
17585e16b3df8db44daf32a8201255cad7a52b0234754ba334f8b7a2479eb32d  deploy/install-mtproxy.sh
0b13b115daa463f6a8913e6ee96a82388b8583ca6a09d2ee42ea53120fc929ba  deploy/install.sh
df6512538c97ac85a2576384d80245e675d6fdc1d6adbc259dcd32fef4733206  deploy/mtproxy.service
e89c63f542242fc14f59d6380cd0c5ca6e43a9939a2bcc718666edeaa185fbfa  deploy/refresh-mtproxy-config.service
0bc82fcece743422c7eefa3e1fbe5661a6c2ccba74abb0075864d62841b77320  deploy/refresh-mtproxy-config.sh
a3902b82e0a0c6e28552322cbb6dbed6b8df490866efcaba472912fab7ade0e6  deploy/refresh-mtproxy-config.timer
a8d92fa19bff6f007a148e81bcf175ae5cc10081f879acb8280174df9c174fa7  deploy/tproxy-firewall.service
640ffcd99f74bd5330933d3955a19084564a5a5b338b54af713498c4cdacde14  deploy/tproxy-server.service
ebc3bca135d02d238c0a26470c53f758879a79329ce5a132ea990dc46348c853  deploy/update-relay.sh
MANIFEST
}

usage() {
  cat <<'USAGE'
Telegram WEB Proxy Deploy
Usage: bash install.sh <command> [options]
Commands: install, update, status, uninstall, show-link, help
Install: --domain HOST --ip IPV4 --email EMAIL [--site-dir DIR] [--adopt]
         [--remove-obsolete] [--upstream-ref SHA|TAG] [--yes]
Update:  [--upstream-ref SHA|TAG] [--yes]
Uninstall: [--purge] [--remove-site] [--yes]
No required install values: prompt on a terminal; automation must supply them.
Default uninstall keeps private configuration, token key, public site and backups.
USAGE
}

valid_domain() {
  local label
  local -a labels
  [[ ${#1} -le 253 && "$1" == *.* && "$1" != *. && "$1" != *..* ]] || return 1
  [[ ! "$1" =~ ^[0-9.]+$ ]] || return 1
  IFS=. read -r -a labels <<<"$1"
  for label in "${labels[@]}"; do
    [[ ${#label} -le 63 && "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || return 1
  done
}
valid_email() { [[ "$1" =~ ^[A-Za-z0-9._+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; }
is_interactive() { [[ -t 0 ]]; }
confirm() {
  local reply
  ((YES)) && return 0
  is_interactive || die 'Confirmation required: use --yes for non-interactive execution.' || return 1
  read -r -p "$1 [y/N] " reply || return 1
  [[ "$reply" == y || "$reply" == Y ]] || die 'Cancelled.'
}
ask_optional() {
  local reply
  is_interactive || return 1
  read -r -p "$1 [y/N] " reply || return 1
  [[ "$reply" == y || "$reply" == Y ]]
}
parse_cli() {
  COMMAND=${1:-install}
  (($# == 0)) || shift
  DOMAIN='' INBOUND_IP='' ACME_EMAIL='' SITE='' UPSTREAM_REF=''
  YES=0 ADOPT=0 PURGE=0 REMOVE_SITE=0 REMOVE_OLD=0
  case "$COMMAND" in install | update | status | uninstall | show-link | help) ;; *)
    die 'Unknown command. Use help.'
    return 1
    ;;
  esac
  while (($#)); do
    case "$1" in
      --domain | --ip | --email | --site-dir | --upstream-ref)
        [[ $# -ge 2 && "$2" != --* && -n "$2" ]] || die "Value required for $1" || return 1
        case "$1" in
          --domain) DOMAIN=$2 ;;
          --ip) INBOUND_IP=$2 ;;
          --email) ACME_EMAIL=$2 ;;
          --site-dir) SITE=$2 ;;
          --upstream-ref) UPSTREAM_REF=$2 ;;
        esac
        shift 2
        ;;
      --yes)
        YES=1
        shift
        ;;
      --adopt)
        ADOPT=1
        shift
        ;;
      --purge)
        PURGE=1
        shift
        ;;
      --remove-site)
        REMOVE_SITE=1
        shift
        ;;
      --remove-obsolete)
        REMOVE_OLD=1
        shift
        ;;
      *)
        die "Unknown option: $1"
        return 1
        ;;
    esac
  done
  if [[ "$COMMAND" != install && -n "$DOMAIN$INBOUND_IP$ACME_EMAIL$SITE" ]] || { [[ "$COMMAND" != install ]] && ((ADOPT || REMOVE_OLD)); }; then
    die 'Deployment options are install-only.'
    return 1
  fi
  if [[ "$COMMAND" != install && "$COMMAND" != update && -n "$UPSTREAM_REF" ]]; then
    die '--upstream-ref is install/update-only.'
    return 1
  fi
  if [[ "$COMMAND" != uninstall ]] && ((PURGE || REMOVE_SITE)); then
    die 'Purge flags are uninstall-only.'
    return 1
  fi
}
collect_inputs() {
  if [[ -z "$DOMAIN" || -z "$INBOUND_IP" || -z "$ACME_EMAIL" ]]; then
    if ((YES)) || ! is_interactive; then
      die '--domain, --ip and --email are required in non-interactive mode.'
      return 1
    fi
    [[ -n "$DOMAIN" ]] || read -r -p 'Domain: ' DOMAIN || return 1
    [[ -n "$INBOUND_IP" ]] || read -r -p 'Public IPv4: ' INBOUND_IP || return 1
    [[ -n "$ACME_EMAIL" ]] || read -r -p 'ACME email: ' ACME_EMAIL || return 1
  fi
  valid_domain "$DOMAIN" || die 'Invalid domain: use a lowercase ASCII DNS hostname.' || return 1
  valid_ipv4 "$INBOUND_IP" || die 'Invalid public IPv4.' || return 1
  valid_email "$ACME_EMAIL" || die 'Invalid ACME email.' || return 1
  printf 'Configuration\n  Domain: %s\n  Inbound IPv4: %s\n  ACME email: %s\n' "$DOMAIN" "$INBOUND_IP" "$ACME_EMAIL"
  confirm 'Continue with installation/adoption?'
}

github_latest() {
  local json code file
  file=$(mktemp) || return 1
  if ! code=$(curl --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 30 -o "$file" -w '%{http_code}' "https://api.github.com/repos/$UPSTREAM_REPO/releases/latest"); then
    rm -f "$file"
    return 1
  fi
  json=$(cat "$file")
  rm -f "$file"
  [[ "$code" != 404 ]] || return 3
  [[ "$code" == 200 ]] || die "GitHub release API returned HTTP $code" || return 1
  RELEASE_TAG=$(jq -er 'select(.draft == false and .prerelease == false) | .tag_name' <<<"$json") || return 1
  [[ "$RELEASE_TAG" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || return 1
  git check-ref-format "refs/tags/$RELEASE_TAG" || return 1
}
resolve_git_ref() {
  local output sha
  output=$(timeout 60 git -c http.sslVerify=true ls-remote "https://github.com/$UPSTREAM_REPO.git" "$1" "$1^{}") || return 1
  sha=$(awk '$2 ~ /\^\{\}$/ {print $1; found=1} END {if (!found) exit 1}' <<<"$output") || sha=$(awk 'NR==1 {print $1}' <<<"$output")
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die 'Cannot resolve an exact official commit.' || return 1
  printf '%s\n' "$sha"
}
resolve_upstream() {
  local status=0
  if [[ -n "$UPSTREAM_REF" ]]; then
    if [[ "$UPSTREAM_REF" =~ ^[0-9a-f]{40}$ ]]; then
      UPSTREAM_COMMIT=$UPSTREAM_REF
    else
      [[ "$UPSTREAM_REF" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || die 'Unsafe upstream ref.' || return 1
      git check-ref-format "refs/tags/$UPSTREAM_REF" || return 1
      UPSTREAM_COMMIT=$(resolve_git_ref "refs/tags/$UPSTREAM_REF") || return 1
    fi
    UPSTREAM_LABEL=$UPSTREAM_REF
    return 0
  fi
  github_latest || status=$?
  case "$status" in
    0)
      UPSTREAM_LABEL=$RELEASE_TAG
      UPSTREAM_COMMIT=$(resolve_git_ref "refs/tags/$RELEASE_TAG") || return 1
      ;;
    3)
      UPSTREAM_LABEL=default-branch
      UPSTREAM_COMMIT=$(resolve_git_ref HEAD) || return 1
      ;;
    *)
      die 'Unable to select upstream; network/API failure is not a no-release signal.'
      return 1
      ;;
  esac
}
fetch_source() {
  local destination=$1 sha=$2
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || return 1
  git init -q "$destination" || return 1
  git -C "$destination" remote add origin "https://github.com/$UPSTREAM_REPO.git" || return 1
  timeout 180 git -C "$destination" -c http.sslVerify=true fetch --depth=1 origin "$sha" || return 1
  git -C "$destination" checkout -q --detach FETCH_HEAD || return 1
  [[ $(git -C "$destination" rev-parse HEAD) == "$sha" ]] || return 1
  check_compatibility "$destination"
}
check_compatibility() {
  local directory=$1 file
  (cd "$directory" && compatibility_manifest | sha256sum --check --status) || die 'Upstream deployment contract changed; no activation. A reviewed wrapper update is required.' || return 1
  for file in "$directory"/deploy/*.sh; do bash -n "$file" || return 1; done
}
update_needed() { [[ "$1" != "$2" ]]; }

managed_path() {
  [[ "$1" == /* && "$1" != *'/../'* && "$1" != *'/./'* && "$1" != *'//'* ]] 2>/dev/null || return 1
  case "$1" in
    /usr/local/bin/tproxy-server | /usr/local/bin/caddy | /usr/local/sbin/refresh-mtproxy-config | /etc/caddy/Caddyfile | /etc/caddy/Caddyfile.tproxy | /etc/systemd/system/caddy.service.d/tproxy.conf | /etc/systemd/system/tproxy-firewall.service.d/webproxy-reload.conf | /etc/tproxy-server/config.json | /etc/tproxy-server/profiles.json | /etc/tproxy-server/token.key | /etc/tproxy-server/firewall.nft | /etc/mtproxy/mtproxy.env | /etc/mtproxy/proxy-secret | /etc/mtproxy/proxy-multi.conf) return 0 ;;
    /etc/systemd/system/caddy.service | /etc/systemd/system/tproxy-server.service | /etc/systemd/system/mtproxy.service | /etc/systemd/system/tproxy-firewall.service | /etc/systemd/system/refresh-mtproxy-config.service | /etc/systemd/system/refresh-mtproxy-config.timer) return 0 ;;
    /opt/MTProxy/objs/bin/mtproto-proxy) return 0 ;;
    *) return 1 ;;
  esac
}
resource_paths() {
  printf '%s\n' /usr/local/bin/tproxy-server /usr/local/bin/caddy /usr/local/sbin/refresh-mtproxy-config /etc/caddy/Caddyfile /etc/caddy/Caddyfile.tproxy /etc/systemd/system/caddy.service.d/tproxy.conf /etc/systemd/system/tproxy-firewall.service.d/webproxy-reload.conf
  local unit
  for unit in caddy.service tproxy-server.service mtproxy.service tproxy-firewall.service refresh-mtproxy-config.service refresh-mtproxy-config.timer; do printf '/etc/systemd/system/%s\n' "$unit"; done
  printf '%s\n' /etc/tproxy-server/config.json /etc/tproxy-server/profiles.json /etc/tproxy-server/token.key /etc/tproxy-server/firewall.nft /etc/mtproxy/mtproxy.env /etc/mtproxy/proxy-secret /etc/mtproxy/proxy-multi.conf
  printf '%s\n' /opt/MTProxy/objs/bin/mtproto-proxy
}
capture_resources() {
  local path class hash paths
  paths=$(resource_paths) || return 1
  while IFS= read -r path; do
    managed_path "$path" || return 1
    [[ -f "$path" && ! -L "$path" ]] || die "Missing managed file: $path" || return 1
    root_path "$path" || return 1
    class=runtime
    case "$path" in /etc/tproxy-server/* | /etc/mtproxy/*) class=config ;; esac
    hash=$(sha256sum "$path")
    hash=${hash%% *}
    jq -n --arg path "$path" --arg class "$class" --arg hash "$hash" '{path:$path,class:$class,sha256:$hash}'
  done <<<"$paths"
}
save_state() {
  local phase=$1 site_owned=$2 resources=$3
  local next
  next=$(mktemp "$STATE/deployment.XXXXXX") || return 1
  jq -n --arg version "$VERSION" --arg domain "$DOMAIN" --arg ip "$INBOUND_IP" --arg email "$ACME_EMAIL" --arg sha "$UPSTREAM_COMMIT" --arg label "$UPSTREAM_LABEL" --arg phase "$phase" --argjson site "$site_owned" --slurpfile resources "$resources" \
    '{schema:1,project_version:$version,domain:$domain,inbound_ipv4:$ip,acme_email:$email,upstream_commit:$sha,upstream_label:$label,phase:$phase,site_owned:$site,resources:$resources[0]}' >"$next" || {
    rm -f "$next"
    return 1
  }
  chmod 0600 "$next" && mv -f "$next" "$STATE/deployment.json"
}
load_state() {
  root_path "$STATE/deployment.json" || return 1
  secret_file_mode "$STATE/deployment.json" 0000 || return 1
  META=$(cat "$STATE/deployment.json") || die 'No public deployment metadata. Use install --adopt for a validated reference deployment.' || return 1
  jq -e '.schema == 1 and (.resources | type == "array") and (.site_owned | type == "boolean")' <<<"$META" >/dev/null || return 1
  DOMAIN=$(jq -er .domain <<<"$META") || return 1
  INBOUND_IP=$(jq -er .inbound_ipv4 <<<"$META") || return 1
  ACME_EMAIL=$(jq -er .acme_email <<<"$META") || return 1
  SITE_OWNED=$(jq -r .site_owned <<<"$META")
  valid_domain "$DOMAIN" && valid_ipv4 "$INBOUND_IP" && valid_email "$ACME_EMAIL" || return 1
  [[ $(jq -r .upstream_commit <<<"$META") =~ ^[0-9a-f]{40}$ ]] || return 1
}
selected_resources() {
  jq -c --argjson purge "$PURGE" '.[] | select(.path != "/etc/mtproxy/proxy-multi.conf") | select(.class == "runtime" or ($purge == 1 and .class == "config"))' "$1"
}
validate_ownership() {
  local resources=$1 entry path expected actual selected
  jq -e 'type == "array" and length > 0 and all(.[]; (.class == "runtime" or .class == "config") and (.path | type == "string") and (.sha256 | test("^[0-9a-f]{64}$")))' "$resources" >/dev/null || return 1
  selected=$(selected_resources "$resources") || return 1
  while IFS= read -r entry; do
    path=$(jq -er .path <<<"$entry") || return 1
    managed_path "$path" || die 'Manifest contains an unmanaged path; refusing removal.' || return 1
    expected=$(jq -er .sha256 <<<"$entry") || return 1
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
    root_path "$path" || return 1
    [[ ! -L "$path" && -f "$path" ]] || die "Managed resource is missing or replaced: $path" || return 1
    # This official downloaded DC list changes daily. Preserve it even with --purge.
    actual=$(sha256sum "$path")
    actual=${actual%% *}
    [[ "$actual" == "$expected" ]] || die "Managed resource changed: $path. Review ownership manually; nothing removed." || return 1
  done <<<"$selected"
}
validate_units() {
  local source=$1 unit extra expected
  for unit in caddy.service tproxy-server.service mtproxy.service tproxy-firewall.service refresh-mtproxy-config.service refresh-mtproxy-config.timer; do
    cmp -s "$source/deploy/$unit" "/etc/systemd/system/$unit" || die "Non-reference unit: $unit" || return 1
    [[ $(systemctl show --property=FragmentPath --value "$unit") == "/etc/systemd/system/$unit" ]] || return 1
    extra=$(systemctl show --property=DropInPaths --value "$unit") || return 1
    case "$unit" in
      caddy.service) expected=/etc/systemd/system/caddy.service.d/tproxy.conf ;;
      tproxy-firewall.service) expected=/etc/systemd/system/tproxy-firewall.service.d/webproxy-reload.conf ;;
      *) expected= ;;
    esac
    [[ "$extra" == "$expected" || ("$unit" == tproxy-firewall.service && -z "$extra") ]] || die "Unexpected service override: $unit" || return 1
  done
  cmp -s "$source/deploy/firewall.nft" /etc/tproxy-server/firewall.nft || die 'Persisted backend firewall differs from reviewed source.' || return 1
  cmp -s "$source/deploy/Caddyfile" /etc/caddy/Caddyfile || die 'Caddyfile is customized; automatic ownership adoption refused.' || return 1
  printf '[Service]\nEnvironment=TPROXY_HOSTNAME=%s\nEnvironment=TPROXY_SITE_ROOT=/srv/tproxy-site\nEnvironment=ACME_EMAIL=%s\n' "$DOMAIN" "$ACME_EMAIL" >"$WORK/caddy-expected"
  cmp -s "$WORK/caddy-expected" /etc/systemd/system/caddy.service.d/tproxy.conf || die 'Caddy environment differs from supplied deployment inputs.' || return 1
}
ensure_firewall_dropin() {
  local path=/etc/systemd/system/tproxy-firewall.service.d/webproxy-reload.conf
  root_path "$path" || return 1
  if [[ -e "$path" ]]; then
    cmp -s "$path" <(firewall_dropin) || return 1
    return 0
  fi
  install -d -m 0755 "${path%/*}" || return 1
  firewall_dropin >"$WORK/firewall.conf"
  install -m 0644 "$WORK/firewall.conf" "$path" || return 1
  systemctl daemon-reload
}
protect_paths() {
  local path
  for path in "$STATE" "$STATE/deployment.json" /etc/tproxy-server /etc/mtproxy /opt/MTProxy /usr/local/bin /usr/local/sbin /etc/systemd/system; do root_path "$path" || return 1; done
  for path in "$CONFIG" "$PROFILES" /etc/tproxy-server/token.key /etc/tproxy-server/firewall.nft /etc/mtproxy/proxy-secret /etc/mtproxy/proxy-multi.conf /etc/mtproxy/mtproxy.env /etc/caddy/Caddyfile /etc/caddy/Caddyfile.tproxy /etc/systemd/system/caddy.service.d/tproxy.conf /etc/systemd/system/tproxy-firewall.service.d/webproxy-reload.conf /usr/local/bin/caddy "$RELAY" /usr/local/sbin/refresh-mtproxy-config; do root_path "$path" || return 1; done
  check_token_key || return 1
  secret_file_mode "$PROFILES" 0000 || return 1
  secret_file_mode /etc/mtproxy/mtproxy.env 0040 || return 1
}
prepare_host() {
  [[ $EUID == 0 ]] || die 'Run as root.' || return 1
  [[ $(uname -m) == x86_64 ]] || return 1
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ ${ID:-} == debian && ${VERSION_ID:-} == 13 ]] || die 'Debian 13 x86_64 is required.' || return 1
  [[ -d /run/systemd/system ]] || die 'A booted systemd host is required.' || return 1
  local cmd missing=0
  for cmd in git jq curl openssl ip ss flock nft; do command -v "$cmd" >/dev/null || missing=1; done
  if ((missing)); then
    [[ "$COMMAND" == install ]] || die 'Install prerequisites: git jq curl openssl iproute2 util-linux nftables.' || return 1
    export DEBIAN_FRONTEND=noninteractive
    apt-get update || return 1
    apt-get install -y --no-install-recommends ca-certificates git jq curl openssl iproute2 util-linux nftables || return 1
  fi
  protect_paths || return 1
  for cmd in /run/lock/tproxy-installer.lock /run/lock/tproxy-server-update.lock; do
    [[ ! -L "$cmd" && (! -e "$cmd" || (-f "$cmd" && $(stat -c %u "$cmd") == 0)) ]] || die 'Unsafe lock file.' || return 1
  done
  exec 9>/run/lock/tproxy-installer.lock
  flock -n 9 || die 'Another installer is running.' || return 1
  exec 8>/run/lock/tproxy-server-update.lock
  flock -n 8 || die 'Another relay update is running.' || return 1
  WORK=$(mktemp -d /run/tproxy-installer.XXXXXX) || return 1
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

fresh_integrations_clear() {
  local unit tables
  for unit in caddy.service tproxy-server.service mtproxy.service tproxy-firewall.service refresh-mtproxy-config.service refresh-mtproxy-config.timer; do
    [[ ! -e "/etc/systemd/system/$unit.d" && ! -L "/etc/systemd/system/$unit.d" ]] || die "Existing service overrides: $unit; preserved." || return 1
    [[ $(systemctl show --property=LoadState --value "$unit") == not-found ]] || die "Existing loaded or vendor unit: $unit; preserved." || return 1
    [[ -z $(systemctl show --property=DropInPaths --value "$unit") ]] || return 1
  done
  tables=$(nft -j list tables) || die 'Cannot establish existing firewall ownership.' || return 1
  jq -e '[.nftables[] | .table? | select(.family == "inet" and .name == "tproxy_backend")] | length == 0' <<<"$tables" >/dev/null || die 'Existing tproxy_backend table is unowned; preserved.'
}

install_command() {
  local path source=$WORK/source known_sha backup
  collect_inputs || return 1
  check_dns "$DOMAIN" "$INBOUND_IP" || return 1
  discover_nat || return 1
  if [[ -f "$STATE/deployment.json" ]]; then
    local requested_domain=$DOMAIN requested_ip=$INBOUND_IP requested_email=$ACME_EMAIL
    [[ -z "$SITE$UPSTREAM_REF" && "$REMOVE_OLD" == 0 && "$ADOPT" == 0 ]] || die 'Already managed: use update for version changes; install options would be ignored.' || return 1
    load_state || return 1
    [[ $(jq -r .phase <<<"$META") == ready ]] || die 'Incomplete or removed deployment; review recovery instructions.' || return 1
    [[ "$requested_domain" == "$DOMAIN" && "$requested_ip" == "$INBOUND_IP" && "$requested_email" == "$ACME_EMAIL" ]] || die 'Inputs differ from managed deployment.' || return 1
    select_secret "$PROFILES" /nonexistent || return 1
    validate_existing || return 1
    verify_stack || return 1
    info 'Already installed; preserved. Use update to change the relay version.'
    return
  fi
  if [[ -e "$CONFIG" || -e "$PROFILES" ]]; then
    [[ -z "$SITE$UPSTREAM_REF" && "$REMOVE_OLD" == 0 ]] || die 'Adoption preserves the existing site and installed revision; omit install-only overrides.' || return 1
    ((ADOPT)) || die 'Existing reference deployment found. Use install --adopt with its current domain/IP/email.' || return 1
    [[ -f "$STATE/upstream.commit" ]] || die 'Adoption needs the private wrapper upstream.commit provenance file.' || return 1
    root_path "$STATE/upstream.commit" || return 1
    known_sha=$(cat "$STATE/upstream.commit")
    [[ "$known_sha" =~ ^[0-9a-f]{40}$ ]] || die 'Invalid legacy revision.' || return 1
    fetch_source "$source" "$known_sha" || return 1
    select_secret "$PROFILES" /nonexistent || return 1
    validate_existing || return 1
    validate_units "$source" || return 1
    ensure_firewall_dropin || return 1
    if ! jq -e '.profiles[0].carrier_mode == "websocket"' "$PROFILES" >/dev/null; then
      backup=$(mktemp -d /root/tproxy-backup.XXXXXX)
      cp -a "$PROFILES" "$backup/profiles.json"
      jq '.profiles[0].carrier_mode = "websocket"' "$PROFILES" >"$WORK/profiles.json"
      chmod 0400 "$WORK/profiles.json"
      "$RELAY" -config "$CONFIG" -profiles-file "$WORK/profiles.json" -check
      ROLLBACK=$backup/profiles.json
      install -o root -g tproxy -m 0400 "$WORK/profiles.json" "$PROFILES.next"
      mv -f "$PROFILES.next" "$PROFILES"
      systemctl restart tproxy-server.service
    fi
    verify_stack || return 1
    capture_resources | jq -s . >"$WORK/resources.json"
    UPSTREAM_COMMIT=$known_sha UPSTREAM_LABEL=adopted-reference
    save_state ready false "$WORK/resources.json" || return 1
    ROLLBACK=
    info 'Reference deployment adopted without replacing secrets, token key, base path or website.'
    return
  fi
  ((ADOPT == 0)) || die 'Nothing to adopt.' || return 1
  resolve_upstream || return 1
  fetch_source "$source" "$UPSTREAM_COMMIT" || return 1
  # A fresh full installer may own these locations only when they were absent.
  while IFS= read -r path; do
    [[ ! -e "$path" && ! -L "$path" ]] || die "Pre-existing resource: $path; full install refused." || return 1
  done < <(
    printf '%s\n' /etc/caddy /etc/mtproxy /etc/tproxy-server /opt/MTProxy /usr/local/bin/caddy "$RELAY" /usr/local/sbin/refresh-mtproxy-config
    for path in caddy.service tproxy-server.service mtproxy.service tproxy-firewall.service refresh-mtproxy-config.service refresh-mtproxy-config.timer; do printf '/etc/systemd/system/%s\n' "$path"; done
  )
  fresh_integrations_clear || return 1
  root_path /srv/tproxy-site || return 1
  [[ ! -L /srv/tproxy-site/index.html ]] || die 'Site index symlink refused.' || return 1
  if [[ -e /srv/tproxy-site && ! -f /srv/tproxy-site/index.html ]]; then
    [[ -d /srv/tproxy-site && -z $(find /srv/tproxy-site -mindepth 1 -maxdepth 1 -print -quit) ]] || die 'Existing public site is incomplete; preserved.' || return 1
  fi
  SITE_OWNED=false
  if [[ ! -e /srv/tproxy-site ]]; then SITE_OWNED=true; fi
  if [[ -n "$SITE" ]]; then
    [[ "$SITE" == /* ]] || die 'Use an absolute --site-dir.' || return 1
    root_path "$SITE" || return 1
    [[ -f "$SITE/index.html" && ! -L "$SITE/index.html" ]] || die 'Site needs a regular index.html.' || return 1
  elif [[ ! -f /srv/tproxy-site/index.html ]]; then
    [[ ! -e /srv/tproxy-site ]] || die 'Existing public site is incomplete; preserved.' || return 1
    SITE=$WORK/site
    mkdir "$SITE"
    printf '<!doctype html><html lang="en"><meta charset="utf-8"><title>%s</title><h1>%s</h1><p>Welcome.</p></html>\n' "$DOMAIN" "$DOMAIN" >"$SITE/index.html"
    printf '<!doctype html><html lang="en"><meta charset="utf-8"><title>Not found</title><h1>Not found</h1><a href="/">Home</a></html>\n' >"$SITE/404.html"
    chmod 0755 "$SITE"
    chmod 0644 "$SITE/"*.html
  fi
  if ((REMOVE_OLD)); then remove_obsolete; fi
  check_ports fresh || return 1
  install -d -m 0700 "$STATE"
  printf '[]\n' >"$WORK/resources.json"
  save_state installing "$SITE_OWNED" "$WORK/resources.json" || return 1
  # The canonical profiles file is the recovery source; metadata has no secret copy.
  install -d -m 0700 /etc/tproxy-server
  SECRET=$(openssl rand -hex 16)
  valid_secret "$SECRET"
  printf '%s\n' "$SECRET" | jq -Rn '{profiles:[{name:"default",secret:input,backend:"127.0.0.1:2398",carrier_mode:"websocket"}]}' >"$PROFILES"
  chmod 0400 "$PROFILES"
  patch_installer "$source/deploy/install.sh"
  local -a args=(--hostname "$DOMAIN" --email "$ACME_EMAIL")
  [[ -z "$SITE" ]] || args+=(--site-dir "$SITE")
  printf '%s\n' "$SECRET" | TPROXY_VERIFIED_LOCAL="$LOCAL_IP" TPROXY_VERIFIED_EGRESS="$EGRESS_IP" bash "$source/deploy/install.sh" "${args[@]}"
  ensure_firewall_dropin || return 1
  verify_stack || return 1
  capture_resources | jq -s . >"$WORK/resources.json"
  save_state ready "$SITE_OWNED" "$WORK/resources.json" || return 1
  info 'Installed. Use show-link to display private WEB links.'
}

preservation_snapshot() {
  sha256sum "$CONFIG" "$PROFILES" /etc/tproxy-server/token.key /etc/mtproxy/mtproxy.env /etc/caddy/Caddyfile
  local site
  site=$(jq -r '.public_dir // empty' "$CONFIG")
  if [[ -n "$site" ]]; then
    [[ "$site" == /srv/tproxy-site ]] || die 'Custom site path requires manual update review.' || return 1
    find "$site" -xdev -type f -print0 | sort -z | xargs -0 -r sha256sum
  fi
}
restore_binary() {
  install -o root -g root -m 0755 "$1" "$RELAY.rollback" &&
    mv -f "$RELAY.rollback" "$RELAY" &&
    systemctl restart tproxy-server.service &&
    wait_endpoint http://127.0.0.1:8081/healthz ok &&
    wait_endpoint http://127.0.0.1:8081/readyz ready
}
run_upstream_update() {
  local source=$1
  # The parent holds both locks; remove only the child's redundant lock block.
  awk '
    /^exec 9>\/run\/lock\/tproxy-server-update.lock$/ {skip=1; next}
    skip && /^fi$/ {skip=0; next}
    skip {next}
    {gsub(/curl --fail --silent --output \/dev\/null/, "curl --fail --silent --connect-timeout 1 --max-time 2 --output /dev/null"); print}
  ' "$source/deploy/update-relay.sh" >"$source/deploy/update-reviewed.sh" || return 1
  bash -n "$source/deploy/update-reviewed.sh" || return 1
  bash "$source/deploy/update-reviewed.sh"
}
activate_update() {
  local source=$1 backup=$2 path
  for path in "$RELAY.next" "$RELAY.previous" "$RELAY.rollback"; do root_path "$path" || return 1; done
  cp -a "$RELAY" "$backup/relay" || return 1
  cp -a "$STATE/deployment.json" "$backup/deployment.json" || return 1
  preservation_snapshot >"$WORK/preserve.before" || return 1
  BINARY_ROLLBACK=$backup/relay
  STATE_ROLLBACK=$backup/deployment.json
  run_upstream_update "$source" || return 1
  verify_stack || return 1
  preservation_snapshot >"$WORK/preserve.after" || return 1
  cmp -s "$WORK/preserve.before" "$WORK/preserve.after" || die 'Preserved operator state changed during update; refusing metadata commit.' || return 1
  # Retain ownership records; only the relay binary was intentionally replaced.
  local hash
  hash=$(sha256sum "$RELAY")
  hash=${hash%% *}
  jq --arg hash "$hash" '.resources | map(if .path == "/usr/local/bin/tproxy-server" then .sha256=$hash else . end)' "$backup/deployment.json" >"$WORK/resources.json" || return 1
  save_state ready "$SITE_OWNED" "$WORK/resources.json" || return 1
  BINARY_ROLLBACK='' STATE_ROLLBACK=''
}
update_command() {
  load_state || return 1
  [[ $(jq -r .phase <<<"$META") == ready ]] || die 'Deployment is not ready for updates.' || return 1
  select_secret "$PROFILES" /nonexistent || return 1
  discover_nat || return 1
  validate_existing || return 1
  verify_stack || return 1
  resolve_upstream || return 1
  if ! update_needed "$(jq -r .upstream_commit <<<"$META")" "$UPSTREAM_COMMIT"; then
    info 'Already up to date.'
    return
  fi
  fetch_source "$WORK/source" "$UPSTREAM_COMMIT" || return 1
  validate_units "$WORK/source" || return 1
  confirm "Update relay to $UPSTREAM_COMMIT?" || return 1
  install -d -m 0700 "$STATE/backups"
  local backup
  backup=$(mktemp -d "$STATE/backups/update.XXXXXX")
  activate_update "$WORK/source" "$backup" || return 1
  info "Updated relay to $UPSTREAM_COMMIT; rollback binary retained in $backup."
}

status_command() {
  local service state latest=unknown health=unavailable ready=unavailable tls=failed firewall=failed installed=unknown
  if [[ -f "$STATE/deployment.json" ]]; then
    load_state
    installed=$(jq -r .upstream_commit <<<"$META")
    printf 'Project: %s; state: %s\n' "$(jq -r .project_version <<<"$META")" "$(jq -r .phase <<<"$META")"
  else
    DOMAIN=$(jq -er .public_hostname "$CONFIG") || return 1
    valid_domain "$DOMAIN" || return 1
    printf 'Unmanaged reference deployment; adoption required for update/uninstall.\n'
  fi
  printf 'Domain: %s\nInstalled upstream: %s\n' "$DOMAIN" "$installed"
  printf 'Carrier: %s\n' "$(jq -r 'if .profiles[0].carrier_mode == "websocket" then "websocket" else "non-websocket" end' "$PROFILES")"
  for service in caddy mtproxy tproxy-server tproxy-firewall; do
    state=$(systemctl is-active "$service" 2>/dev/null) || true
    case "$state" in active | inactive | failed | activating | deactivating) ;; *) state=unknown ;; esac
    printf '%-18s %s\n' "$service" "$state"
  done
  [[ $(curl --noproxy '*' -fsS --max-time 2 http://127.0.0.1:8081/healthz 2>/dev/null) != ok ]] || health=ok
  [[ $(curl --noproxy '*' -fsS --max-time 2 http://127.0.0.1:8081/readyz 2>/dev/null) != ready ]] || ready=ready
  if curl --noproxy '*' -4fsS --max-time 5 "https://$DOMAIN/" >/dev/null 2>&1; then tls=ok; fi
  if nft -j list chain inet tproxy_backend local_backend 2>/dev/null | firewall_is_protected; then firewall=ok; fi
  printf 'Health: %s; readiness: %s; HTTPS: %s; firewall: %s\n' "$health" "$ready" "$tls" "$firewall"
  if discover_nat 2>/dev/null; then printf 'Source IPv4: %s; measured egress: %s\n' "$LOCAL_IP" "$EGRESS_IP"; else printf 'NAT measurement: unavailable\n'; fi
  if resolve_upstream 2>/dev/null; then
    latest=$UPSTREAM_COMMIT
    printf 'Latest upstream: %s (%s)\n' "$latest" "$UPSTREAM_LABEL"
    if update_needed "$installed" "$latest"; then printf 'Update available; compatibility is checked by update.\n'; else printf 'Already up to date.\n'; fi
  else printf 'Latest upstream: unavailable (local status remains valid).\n'; fi
  [[ "$health" == ok && "$ready" == ready && "$tls" == ok && "$firewall" == ok ]]
}

uninstall_command() {
  load_state || return 1
  [[ $(jq -r .phase <<<"$META") == ready ]] || die 'Ownership metadata is not in ready state; review manually.' || return 1
  jq '.resources' <<<"$META" >"$WORK/resources.json"
  printf 'Removal plan: owned relay, MTProxy, backend firewall and dedicated Caddy integration.\nConfiguration, secrets and website are kept unless selected below.\n'
  if ! ((YES)); then
    if ((PURGE == 0)); then
      if ask_optional 'Also purge private configuration and secrets?'; then PURGE=1; fi
    fi
    if ((REMOVE_SITE == 0)) && [[ "$SITE_OWNED" == true ]]; then
      if ask_optional 'Also remove the public website?'; then REMOVE_SITE=1; fi
    fi
  fi
  if ((REMOVE_SITE)) && [[ "$SITE_OWNED" != true ]]; then
    die 'Site ownership is not established; public site preserved.'
    return 1
  fi
  printf 'Removal plan: owned runtime files and service integrations.\nPrivate config purge: %s; website removal: %s; backups/packages/users retained.\n' "$PURGE" "$REMOVE_SITE"
  confirm 'Proceed with this removal plan?' || return 1
  validate_ownership "$WORK/resources.json" || return 1
  # Reject added service drop-ins and alternate fragment paths before stopping anything.
  local unit extras allowed path entry
  for unit in caddy.service tproxy-server.service mtproxy.service tproxy-firewall.service refresh-mtproxy-config.service refresh-mtproxy-config.timer; do
    [[ $(systemctl show --property=FragmentPath --value "$unit") == "/etc/systemd/system/$unit" ]] || die "Ambiguous service: $unit" || return 1
    extras=$(systemctl show --property=DropInPaths --value "$unit")
    allowed=
    case "$unit" in caddy.service) allowed=/etc/systemd/system/caddy.service.d/tproxy.conf ;; tproxy-firewall.service) allowed=/etc/systemd/system/tproxy-firewall.service.d/webproxy-reload.conf ;; esac
    [[ "$extras" == "$allowed" ]] || die "Unowned service override: $unit" || return 1
  done
  nft -j list table inet tproxy_backend >"$WORK/firewall.json" || return 1
  firewall_is_protected <"$WORK/firewall.json" || die 'Backend table changed; refusing table removal.' || return 1
  [[ $(jq '[.nftables[] | .chain? | select(.)] | length' "$WORK/firewall.json") == 1 ]] || die 'Backend table has additional chains; preserved.' || return 1
  [[ $(jq '[.nftables[] | select((keys - ["metainfo", "table", "chain", "rule"]) | length > 0)] | length' "$WORK/firewall.json") == 0 ]] || die 'Backend table has additional objects; preserved.' || return 1
  if ((REMOVE_SITE)); then
    root_path /srv/tproxy-site || return 1
    [[ -d /srv/tproxy-site && ! -L /srv/tproxy-site ]] || die 'Unexpected site path.' || return 1
    [[ $(find /srv/tproxy-site -xdev -type l -print -quit) == '' ]] || die 'Website has symlinks; manual removal required.' || return 1
  fi
  # Re-check just before mutations; no package, user, Docker or global firewall cleanup.
  validate_ownership "$WORK/resources.json" || return 1
  systemctl disable --now refresh-mtproxy-config.timer || return 1
  systemctl stop refresh-mtproxy-config.service || return 1
  systemctl disable --now tproxy-server.service mtproxy.service caddy.service || return 1
  systemctl disable --now tproxy-firewall.service || return 1
  while IFS= read -r entry; do
    path=$(jq -er .path <<<"$entry")
    rm -f -- "$path" || return 1
  done < <(selected_resources "$WORK/resources.json")
  if ((REMOVE_SITE)); then
    find /srv/tproxy-site -xdev -depth -type f -delete
    find /srv/tproxy-site -xdev -depth -type d -empty -delete
  fi
  systemctl daemon-reload || return 1
  UPSTREAM_COMMIT=$(jq -r .upstream_commit <<<"$META")
  UPSTREAM_LABEL=$(jq -r .upstream_label <<<"$META")
  save_state removed "$SITE_OWNED" "$WORK/resources.json" || return 1
  info 'Managed runtime removed. Backups, packages, system users and ACME account/certificate storage retained.'
}

main() {
  set -Eeuo pipefail
  umask 077
  export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  unset BASH_ENV ENV
  parse_cli "$@"
  if [[ "$COMMAND" == help ]]; then
    usage
    return
  fi
  safe_cwd
  prepare_host
  case "$COMMAND" in
    install) install_command ;;
    update) update_command ;;
    status) status_command ;;
    uninstall) uninstall_command ;;
    show-link)
      [[ -f "$CONFIG" && -f "$PROFILES" ]] || die 'No installed configuration.'
      DOMAIN=$(jq -er .public_hostname "$CONFIG")
      valid_domain "$DOMAIN"
      select_secret "$PROFILES" /nonexistent
      share_links "$DOMAIN" "$(jq -er '.base_path // ""' "$CONFIG")"
      ;;
  esac
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
