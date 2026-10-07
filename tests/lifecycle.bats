#!/usr/bin/env bats
setup() {
  source "$BATS_TEST_DIRNAME/../install.sh"
  TEST_ROOT="$BATS_TEST_TMPDIR/lifecycle"
  STATE="$TEST_ROOT/state"
  WORK="$TEST_ROOT/work"
  RELAY="$TEST_ROOT/relay"
  CONFIG="$TEST_ROOT/config"
  PROFILES="$TEST_ROOT/profiles"
  mkdir -p "$STATE" "$WORK" "$TEST_ROOT/backup"
  DOMAIN=proxy.example.com INBOUND_IP=203.0.113.10 ACME_EMAIL=admin@example.com
  UPSTREAM_COMMIT=1111111111111111111111111111111111111111
  UPSTREAM_LABEL=default-branch
  printf old-binary >"$RELAY"
  printf '{"public_hostname":"proxy.example.com","base_path":"random-path"}' >"$CONFIG"
  printf '{"profiles":[{"secret":"000102030405060708090a0b0c0d0e0f","carrier_mode":"websocket"}]}' >"$PROFILES"
  printf 'unchanged-token-bytes' >"$TEST_ROOT/token"
  printf 'operator website' >"$TEST_ROOT/site"
  printf '[{"path":"/usr/local/bin/tproxy-server","class":"runtime","sha256":"%s"}]' "$(sha256sum "$RELAY" | cut -d' ' -f1)" >"$WORK/resources.json"
  save_state ready false "$WORK/resources.json"
  chmod 0600 "$STATE/deployment.json"
  root_path() { :; } # All test resources live in a Bats-owned temporary directory.
  preservation_snapshot() { sha256sum "$CONFIG" "$PROFILES" "$TEST_ROOT/token" "$TEST_ROOT/site"; }
  verify_stack() { :; }
}
@test "first installation journal records incomplete phase without a secret copy" {
  save_state installing true "$WORK/resources.json"
  load_state
  [ "$(jq -r .phase <<<"$META")" = installing ]
  [ "$SITE_OWNED" = true ]
  [ "$(stat -c %a "$STATE/deployment.json")" = 600 ]
  ! grep -q 000102030405060708090a0b0c0d0e0f "$STATE/deployment.json"
}
@test "managed reinstall is a no-op preserving all operator bytes" {
  YES=1
  collect_inputs() { :; }
  check_dns() { :; }
  discover_nat() { :; }
  validate_existing() { :; }
  fetch_source() { return 99; }
  preservation_snapshot >"$TEST_ROOT/before"
  run install_command
  [ "$status" -eq 0 ]
  [[ "$output" == *'Already installed'* ]]
  preservation_snapshot >"$TEST_ROOT/after"
  cmp "$TEST_ROOT/before" "$TEST_ROOT/after"
}
@test "already-current update never runs updater" {
  discover_nat() { :; }
  validate_existing() { :; }
  resolve_upstream() { :; }
  activate_update() { return 99; }
  run update_command
  [ "$status" -eq 0 ]
  [[ "$output" == *'Already up to date.'* ]]
}
@test "successful update preserves secret token base path and site then commits exact SHA" {
  load_state
  UPSTREAM_COMMIT=2222222222222222222222222222222222222222
  run_upstream_update() { printf new-binary >"$RELAY"; }
  preservation_snapshot >"$TEST_ROOT/before"
  activate_update "$WORK/source" "$TEST_ROOT/backup"
  preservation_snapshot >"$TEST_ROOT/after"
  cmp "$TEST_ROOT/before" "$TEST_ROOT/after"
  [ "$(jq -r .upstream_commit "$STATE/deployment.json")" = "$UPSTREAM_COMMIT" ]
  [ -z "$BINARY_ROLLBACK" ]
  [ "$(cat "$TEST_ROOT/backup/relay")" = old-binary ]
}
@test "failed activation EXIT trap restores old relay and metadata" {
  load_state
  UPSTREAM_COMMIT=2222222222222222222222222222222222222222
  run_upstream_update() {
    printf broken >"$RELAY"
    return 1
  }
  restore_binary() { cp "$1" "$RELAY"; }
  run bash_failure
  [ "$status" -eq 1 ]
  [ "$(cat "$RELAY")" = old-binary ]
  [ "$(jq -r .upstream_commit "$STATE/deployment.json")" = 1111111111111111111111111111111111111111 ]
}
bash_failure() (
  set -e
  trap cleanup EXIT
  activate_update "$WORK/source" "$TEST_ROOT/backup"
)
@test "failed preservation check cannot commit new upstream SHA" {
  load_state
  UPSTREAM_COMMIT=2222222222222222222222222222222222222222
  run_upstream_update() { printf changed >"$TEST_ROOT/site"; }
  run activate_update "$WORK/source" "$TEST_ROOT/backup"
  [ "$status" -eq 1 ]
  [ "$(jq -r .upstream_commit "$STATE/deployment.json")" = 1111111111111111111111111111111111111111 ]
}
@test "ownership rejects foreign paths and modified managed files" {
  run validate_ownership "$WORK/resources.json"
  [ "$status" -eq 1 ]
  jq --arg path "$RELAY" '.[0].path=$path' "$WORK/resources.json" >"$WORK/scoped.json"
  managed_path() { [[ "$1" == "$RELAY" ]]; }
  validate_ownership "$WORK/scoped.json"
  printf tampered >>"$RELAY"
  run validate_ownership "$WORK/scoped.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *'changed'* ]]
}
@test "empty or malformed ownership metadata cannot authorize removal" {
  printf '[]' >"$WORK/empty.json"
  run validate_ownership "$WORK/empty.json"
  [ "$status" -eq 1 ]
  printf 'invalid' >"$WORK/empty.json"
  run validate_ownership "$WORK/empty.json"
  [ "$status" -eq 1 ]
}
@test "status reports health and upstream without secret or token bytes" {
  systemctl() { printf active; }
  curl() {
    case "${*: -1}" in */healthz) printf ok ;; */readyz) printf ready ;; *) return 0 ;; esac
  }
  nft() { printf '{}'; }
  firewall_is_protected() { cat >/dev/null; }
  discover_nat() { LOCAL_IP=192.0.2.10 EGRESS_IP=198.51.100.10; }
  resolve_upstream() { :; }
  run status_command
  [ "$status" -eq 0 ]
  [[ "$output" == *'Health: ok; readiness: ready'* ]]
  [[ "$output" != *000102030405060708090a0b0c0d0e0f* ]]
  [[ "$output" != *unchanged-token-bytes* ]]
}
prepare_uninstall() {
  YES=1
  jq --arg relay "$RELAY" --arg profiles "$PROFILES" --arg hash "$(sha256sum "$PROFILES" | cut -d' ' -f1)" '.[0].path=$relay | . + [{path:$profiles,class:"config",sha256:$hash}]' "$WORK/resources.json" >"$WORK/scoped.json"
  save_state ready false "$WORK/scoped.json"
  managed_path() { [[ "$1" == "$RELAY" || "$1" == "$PROFILES" ]]; }
  systemctl() {
    printf '%s\n' "$*" >>"$TEST_ROOT/service-actions"
    case "$*" in
      *FragmentPath*) printf '/etc/systemd/system/%s' "${*: -1}" ;;
      *DropInPaths*caddy.service) printf /etc/systemd/system/caddy.service.d/tproxy.conf ;;
      *DropInPaths*tproxy-firewall.service) printf /etc/systemd/system/tproxy-firewall.service.d/webproxy-reload.conf ;;
    esac
  }
  nft() { printf '{"nftables":[{"chain":{}}]}'; }
  firewall_is_protected() { cat >/dev/null; }
  docker() {
    printf forbidden >"$TEST_ROOT/docker-called"
    return 99
  }
}
@test "runtime uninstall keeps secrets website and Docker" {
  prepare_uninstall
  uninstall_command
  [ ! -e "$RELAY" ]
  [ -f "$PROFILES" ]
  [ "$(cat "$TEST_ROOT/site")" = 'operator website' ]
  [ ! -e "$TEST_ROOT/docker-called" ]
  [ "$(jq -r .phase "$STATE/deployment.json")" = removed ]
}
@test "explicit purge removes only owned configuration" {
  prepare_uninstall
  PURGE=1
  uninstall_command
  [ ! -e "$PROFILES" ]
  [ -e "$TEST_ROOT/token" ] # Not in this test's ownership manifest.
}
@test "unrelated Caddy override aborts before any stop or deletion" {
  prepare_uninstall
  systemctl() {
    case "$*" in *FragmentPath*) printf '/etc/systemd/system/%s' "${*: -1}" ;; *DropInPaths*) printf /etc/systemd/system/caddy.service.d/unrelated.conf ;; *) printf mutation >"$TEST_ROOT/mutated" ;; esac
  }
  run strict_uninstall
  [ "$status" -eq 1 ]
  [ -f "$RELAY" ]
  [ ! -e "$TEST_ROOT/mutated" ]
}
@test "extra nftables objects abort before removal" {
  prepare_uninstall
  nft() { printf '{"nftables":[{"chain":{}},{"quota":{}}]}'; }
  run strict_uninstall
  [ "$status" -eq 1 ]
  [ -f "$RELAY" ]
  ! grep -q 'disable\|stop' "$TEST_ROOT/service-actions"
}
strict_uninstall() (
  set -e
  uninstall_command
)
@test "interactive uninstall presents plan before confirmation and defaults to keeping secrets" {
  prepare_uninstall
  YES=0
  is_interactive() { return 0; }
  run strict_uninstall <<<$'n\ny'
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == 'Removal plan:'* ]]
  [ -e "$PROFILES" ]
}

@test "adoption preserves existing secret token base path and site" {
  rm "$STATE/deployment.json"
  printf '%s\n' "$UPSTREAM_COMMIT" >"$STATE/upstream.commit"
  ADOPT=1 YES=1
  collect_inputs() { :; }
  check_dns() { :; }
  discover_nat() { :; }
  validate_existing() { :; }
  validate_units() { :; }
  ensure_firewall_dropin() { :; }
  fetch_source() { [[ "$2" == 1111111111111111111111111111111111111111 ]]; }
  cp "$WORK/resources.json" "$TEST_ROOT/owned.json"
  capture_resources() { jq -c '.[]' "$TEST_ROOT/owned.json"; }
  preservation_snapshot >"$TEST_ROOT/before"
  install_command
  preservation_snapshot >"$TEST_ROOT/after"
  cmp "$TEST_ROOT/before" "$TEST_ROOT/after"
  [ "$(jq '.resources | length' "$STATE/deployment.json")" = 1 ]
  [ "$(jq -r .upstream_label "$STATE/deployment.json")" = adopted-reference ]
  [ "$(jq -r .site_owned "$STATE/deployment.json")" = false ]
}
@test "adoption refuses missing provenance before touching the stack" {
  rm "$STATE/deployment.json"
  ADOPT=1 YES=1
  collect_inputs() { :; }
  check_dns() { :; }
  discover_nat() { :; }
  fetch_source() { touch "$TEST_ROOT/fetched"; }
  run install_command
  [ "$status" -eq 1 ]
  [ ! -e "$TEST_ROOT/fetched" ]
}
@test "adoption refuses ambiguous service ownership before metadata commit" {
  rm "$STATE/deployment.json"
  printf '%s\n' "$UPSTREAM_COMMIT" >"$STATE/upstream.commit"
  ADOPT=1 YES=1
  collect_inputs() { :; }
  check_dns() { :; }
  discover_nat() { :; }
  fetch_source() { :; }
  validate_existing() { :; }
  validate_units() { return 1; }
  run install_command
  [ "$status" -eq 1 ]
  [ ! -e "$STATE/deployment.json" ]
}
