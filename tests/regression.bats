#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../install.sh"
  TEST_ROOT="$BATS_TEST_TMPDIR/state"
  mkdir -p "$TEST_ROOT"
}

@test "existing secret survives without calling randomness" {
  printf '%s\n' '{"profiles":[{"secret":"000102030405060708090a0b0c0d0e0f"}]}' >"$TEST_ROOT/profiles"
  openssl() { return 88; }
  select_secret "$TEST_ROOT/profiles" "$TEST_ROOT/pending"
  [ "$SECRET" = 000102030405060708090a0b0c0d0e0f ]
}

@test "invalid existing secret fails without replacement" {
  printf '%s\n' '{"profiles":[{"secret":"bad"}]}' >"$TEST_ROOT/profiles"
  run select_secret "$TEST_ROOT/profiles" "$TEST_ROOT/pending"
  [ "$status" -eq 1 ]
  [ ! -e "$TEST_ROOT/pending" ]
}

@test "missing secret generates exactly 16 random bytes" {
  select_secret "$TEST_ROOT/profiles" "$TEST_ROOT/pending"
  [[ "$SECRET" =~ ^[0-9a-f]{32}$ ]]
}

@test "pending installation preserves its secret" {
  printf '%s\n' 000102030405060708090a0b0c0d0e0f >"$TEST_ROOT/pending"
  select_secret "$TEST_ROOT/profiles" "$TEST_ROOT/pending"
  [ "$SECRET" = 000102030405060708090a0b0c0d0e0f ]
}

@test "ambiguous multiple profiles are not collapsed" {
  printf '%s\n' '{"profiles":[{"secret":"000102030405060708090a0b0c0d0e0f"},{"secret":"000102030405060708090a0b0c0d0e0f"}]}' >"$TEST_ROOT/profiles"
  run select_secret "$TEST_ROOT/profiles" "$TEST_ROOT/pending"
  [ "$status" -eq 1 ]
}

@test "base path secret matches official BASE_PATH example" {
  SECRET=8561944064fc730cbfa4473562d8ec59
  run share_links example.com phcf2vfe7zgbrslg
  [ "$status" -eq 0 ]
  [[ "$output" == *'server=example.com%2Fphcf2vfe7zgbrslg&secret=cIVhlEBk_HMMv6RHNWLY7Fk'* ]]
}

@test "binary secret retains NUL and all path slashes are encoded" {
  SECRET=000102030405060708090a0b0c0d0e0f
  run share_links example.com Ab/cD
  [[ "$output" == *'server=example.com%2FAb%2FcD&secret=cAABAgMEBQYHCAkKCwwNDg8'* ]]
}

@test "root link uses unmarked secret and no port" {
  SECRET=000102030405060708090a0b0c0d0e0f
  run share_links example.com ''
  [ "${lines[0]}" = 'https://t.me/webproxy?server=example.com&secret=000102030405060708090a0b0c0d0e0f' ]
}

@test "path traversal and double slashes fail" {
  run valid_base_path ../x
  [ "$status" -eq 1 ]
  run valid_base_path a//b
  [ "$status" -eq 1 ]
}

@test "readiness retries actual condition until exact body is ready" {
  printf 0 >"$TEST_ROOT/attempts"
  curl() {
    local count
    count=$(cat "$TEST_ROOT/attempts")
    printf '%s' "$((count + 1))" >"$TEST_ROOT/attempts"
    ((count >= 2)) || return 7
    printf ready
  }
  sleep() { :; }
  wait_endpoint http://127.0.0.1:8081/readyz ready 5
  [ "$(cat "$TEST_ROOT/attempts")" = 3 ]
}

@test "readiness timeout is bounded and wrong success body is rejected" {
  curl() { printf wrong; }
  sleep() { :; }
  run wait_endpoint http://127.0.0.1:8081/readyz ready 3
  [ "$status" -eq 1 ]
}

@test "DNS mismatch and mixed A records fail" {
  getent() { printf '192.0.2.1 STREAM host\n'; }
  run check_dns proxy.example.com 203.0.113.10
  [ "$status" -eq 1 ]
  getent() { printf '203.0.113.10 STREAM host\n192.0.2.1 STREAM host\n'; }
  run check_dns proxy.example.com 203.0.113.10
  [ "$status" -eq 1 ]
}

@test "expected DNS A record passes" {
  getent() { printf '203.0.113.10 STREAM host\n203.0.113.10 DGRAM host\n'; }
  check_dns proxy.example.com 203.0.113.10
}

@test "port collision is rejected even when service is called caddy on fresh host" {
  ss() { printf 'LISTEN 0 4096 0.0.0.0:443 0.0.0.0:* users:(("caddy",pid=1,fd=1))\n'; }
  run check_ports fresh
  [ "$status" -eq 1 ]
}

@test "existing deployment permits only the Caddy main PID on public ports" {
  systemctl() { printf 17; }
  ss() { printf 'LISTEN 0 4096 0.0.0.0:443 0.0.0.0:* users:(("caddy",pid=17,fd=1))\n'; }
  check_ports existing
  ss() { printf 'LISTEN 0 4096 0.0.0.0:443 0.0.0.0:* users:(("nginx",pid=18,fd=1))\n'; }
  run check_ports existing
  [ "$status" -eq 1 ]
}

@test "only explicitly named obsolete image and container pairs qualify" {
  obsolete_identity tg-ws-proxy valnesfjord/tg-ws-proxy-rs:2.5.2
  obsolete_identity tgwebproxy tgwebproxy:local
  run obsolete_identity database valnesfjord/tg-ws-proxy-rs:2.5.2
  [ "$status" -eq 1 ]
  run obsolete_identity tgwebproxy postgres:16
  [ "$status" -eq 1 ]
}

@test "safe cwd survives removal of invocation directory and subsequent Git" {
  mkdir "$TEST_ROOT/obsolete"
  cd "$TEST_ROOT/obsolete"
  safe_cwd
  rm -r "$TEST_ROOT/obsolete"
  git init -q "$TEST_ROOT/new-repository"
  [ -d "$TEST_ROOT/new-repository/.git" ]
}

@test "NAT discovery uses egress not DNS inbound" {
  ip() { printf '149.154.175.50 via 10.0.0.1 dev eth0 src 10.0.0.2 uid 0\n'; }
  curl() { printf 198.51.100.10; }
  discover_nat
  [ "$LOCAL_IP" = 10.0.0.2 ]
  [ "$EGRESS_IP" = 198.51.100.10 ]
}

@test "failed egress probes never fall back to inbound DNS" {
  ip() { printf '149.154.175.50 dev eth0 src 10.0.0.2\n'; }
  curl() { return 7; }
  run discover_nat
  [ "$status" -eq 1 ]
}

@test "invalid IPv4 octets are rejected" {
  run valid_ipv4 999.1.1.1
  [ "$status" -eq 1 ]
}

@test "upstream transformations keep umask, remove secret summary and force websocket" {
  [ -n "${UPSTREAM_SOURCE:-}" ] || skip 'set UPSTREAM_SOURCE to the pinned checkout'
  cp -a "$UPSTREAM_SOURCE" "$TEST_ROOT/source"
  patch_installer "$TEST_ROOT/source/deploy/install.sh"
  grep -Fxq 'umask 077' "$TEST_ROOT/source/deploy/install.sh"
  grep -Fq '"carrier_mode":"websocket"' "$TEST_ROOT/source/deploy/install.sh"
  ! grep -Fq 'Internal mtproxy secret:' "$TEST_ROOT/source/deploy/install.sh"
  ! grep -Fq 'public_address="$(getent' "$TEST_ROOT/source/deploy/install.sh"
  bash -n "$TEST_ROOT/source/deploy/install.sh"
}

@test "firewall validator rejects unhooked chains and preceding accept rules" {
  local rule='{"rule":{"expr":[{"match":{"left":{"meta":{"key":"iifname"}},"op":"!=","right":"lo"}},{"match":{"left":{"payload":{"protocol":"tcp","field":"dport"}},"op":"==","right":{"set":[2398,8888]}}},{"drop":null}]}}'
  local chain='{"chain":{"family":"inet","table":"tproxy_backend","name":"local_backend","type":"filter","hook":"input","prio":-10,"policy":"accept"}}'
  run firewall_is_protected <<<"{\"nftables\":[$chain,$rule]}"
  [ "$status" -eq 0 ]
  run firewall_is_protected <<<"{\"nftables\":[$rule]}"
  [ "$status" -eq 1 ]
  run firewall_is_protected <<<"{\"nftables\":[$chain,{\"rule\":{\"expr\":[{\"accept\":null}]}},$rule]}"
  [ "$status" -eq 1 ]
}

@test "firewall reload drop-in propagates nftables reload without replacing its config" {
  run firewall_dropin
  [ "$status" -eq 0 ]
  [[ "$output" == *'ReloadPropagatedFrom=nftables.service'* ]]
  [[ "$output" != *'ExecStart='* ]]
}

@test "backend env refuses public secret permissions and accepts root-only" {
  printf 'MTPROXY_SECRET=example\n' >"$TEST_ROOT/env"
  chmod 0644 "$TEST_ROOT/env"
  run secret_file_mode "$TEST_ROOT/env" 0040
  [ "$status" -eq 1 ]
  chmod 0600 "$TEST_ROOT/env"
  secret_file_mode "$TEST_ROOT/env" 0040
}

@test "secret state symlink is refused even when dangling" {
  ln -s "$TEST_ROOT/missing" "$TEST_ROOT/secret"
  run secret_file_mode "$TEST_ROOT/secret" 0000
  [ "$status" -eq 1 ]
}

@test "redirect destination validation detects a dangling symlink" {
  ln -s "$TEST_ROOT/missing" "$TEST_ROOT/redirect"
  stat() {
    case "$2" in
      %u) printf 0 ;;
      %a) printf 755 ;;
      *) return 1 ;;
    esac
  }
  run root_path "$TEST_ROOT/redirect"
  [ "$status" -eq 1 ]
  [[ "$output" == *'Symlink refused:'* ]]
}

@test "token key validation preserves bytes and rejects invalid length" {
  head -c 32 /dev/urandom >"$TEST_ROOT/key"
  chmod 0400 "$TEST_ROOT/key"
  local before
  before=$(sha256sum "$TEST_ROOT/key")
  check_token_key "$TEST_ROOT/key"
  [ "$(sha256sum "$TEST_ROOT/key")" = "$before" ]
  chmod 0600 "$TEST_ROOT/key"
  printf x >"$TEST_ROOT/key"
  run check_token_key "$TEST_ROOT/key"
  [ "$status" -eq 1 ]
  [ "$(cat "$TEST_ROOT/key")" = x ]
}

@test "cleanup removes only allowlisted container IDs and never images" {
  docker() {
    case "$1" in
      info) return 0 ;;
      container)
        case "$*" in
          *tg-ws-proxy*) printf id-one ;;
          *tgwebproxy*) printf id-two ;;
          *) return 1 ;;
        esac
        ;;
      inspect)
        case "$4" in
          id-one) printf valnesfjord/tg-ws-proxy-rs:2.5.2 ;;
          id-two) printf tgwebproxy:local ;;
          *) return 1 ;;
        esac
        ;;
      rm) printf '%s\n' "$*" >>"$TEST_ROOT/removed" ;;
      *) return 1 ;;
    esac
  }
  remove_obsolete
  [ "$(cat "$TEST_ROOT/removed")" = $'rm -f id-one\nrm -f id-two' ]
}

@test "unsafe container identity aborts before removal" {
  docker() {
    case "$1" in
      info) return 0 ;;
      container) printf id-one ;;
      inspect) printf postgres:16 ;;
      rm) touch "$TEST_ROOT/removed" ;;
      *) return 1 ;;
    esac
  }
  run remove_obsolete
  [ "$status" -eq 1 ]
  [ ! -e "$TEST_ROOT/removed" ]
}

@test "failed rollback copy never claims restoration or restarts the service" {
  run bash -c '
    source "$1"
    ROLLBACK="$2/backup"
    PROFILES="$2/profiles"
    marker="$2/restarted"
    install() { return 1; }
    systemctl() { touch "$marker"; }
    false
    cleanup
  ' _ "$BATS_TEST_DIRNAME/../install.sh" "$TEST_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *'rollback failed'* ]]
  [[ "$output" != *'restored and ready'* ]]
  [ ! -e "$TEST_ROOT/restarted" ]
}
