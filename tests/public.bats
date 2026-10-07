#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../install.sh"
  STATE="$BATS_TEST_TMPDIR/state"
  mkdir -p "$STATE"
}

@test "domain accepts canonical hostname and rejects injection, IP, empty labels" {
  valid_domain proxy.example.com
  for input in 'x;id.example.com' 'https://example.com' '203.0.113.10' 'x..com' '-x.com' 'x_.com'; do
    run valid_domain "$input"
    [ "$status" -eq 1 ]
  done
}

@test "email validation rejects shell metacharacters" {
  valid_email admin+proxy@example.com
  run valid_email 'a@example.com;id'
  [ "$status" -eq 1 ]
}

@test "CLI accepts complete noninteractive installation" {
  parse_cli install --domain proxy.example.com --ip 203.0.113.10 --email admin@example.com --yes
  collect_inputs
  [ "$DOMAIN" = proxy.example.com ]
  [ "$YES" = 1 ]
}

@test "noninteractive missing input fails without prompt" {
  parse_cli install --yes
  run collect_inputs
  [ "$status" -eq 1 ]
  [[ "$output" == *'required'* ]]
}

@test "interactive values go through the same validators" {
  is_interactive() { return 0; }
  parse_cli install
  collect_inputs <<<$'proxy.example.com\n203.0.113.10\nadmin@example.com\ny'
  [ "$DOMAIN" = proxy.example.com ]
  [ "$INBOUND_IP" = 203.0.113.10 ]
}

@test "interactive invalid input is refused before confirmation" {
  is_interactive() { return 0; }
  parse_cli install
  run collect_inputs <<<$'bad..domain\n203.0.113.10\nadmin@example.com\ny'
  [ "$status" -eq 1 ]
}

@test "purge and remove-site are uninstall-only explicit flags" {
  run parse_cli update --purge
  [ "$status" -eq 1 ]
  parse_cli uninstall --yes --purge --remove-site
  [ "$PURGE" = 1 ]
  [ "$REMOVE_SITE" = 1 ]
}

@test "unknown command, unknown flag and missing option argument fail" {
  run parse_cli explode
  [ "$status" -eq 1 ]
  run parse_cli install --wat
  [ "$status" -eq 1 ]
  run parse_cli install --domain
  [ "$status" -eq 1 ]
}

@test "latest upstream prefers stable release and resolves annotated tag" {
  github_latest() { RELEASE_TAG=v1.2.3; }
  resolve_git_ref() {
    [ "$1" = refs/tags/v1.2.3 ]
    printf '%040d\n' 2
  }
  resolve_upstream
  [ "$UPSTREAM_COMMIT" = 0000000000000000000000000000000000000002 ]
  [ "$UPSTREAM_LABEL" = v1.2.3 ]
}

@test "no releases falls back to official default HEAD" {
  github_latest() { return 3; }
  resolve_git_ref() {
    [ "$1" = HEAD ]
    printf '%040d\n' 3
  }
  resolve_upstream
  [ "$UPSTREAM_LABEL" = default-branch ]
}

@test "API failure is not silently treated as no releases" {
  github_latest() { return 1; }
  run resolve_upstream
  [ "$status" -eq 1 ]
}

@test "explicit SHA override is recorded exactly" {
  UPSTREAM_REF=0123456789012345678901234567890123456789
  resolve_upstream
  [ "$UPSTREAM_COMMIT" = "$UPSTREAM_REF" ]
}

@test "unsafe Git ref is rejected" {
  UPSTREAM_REF='--upload-pack=evil'
  run resolve_upstream
  [ "$status" -eq 1 ]
}

@test "compatibility gate accepts audited source and rejects modified installer" {
  [ -n "${UPSTREAM_SOURCE:-}" ] || skip 'UPSTREAM_SOURCE required'
  cp -a "$UPSTREAM_SOURCE" "$STATE/source"
  check_compatibility "$STATE/source"
  printf '\n# changed\n' >>"$STATE/source/deploy/install.sh"
  run check_compatibility "$STATE/source"
  [ "$status" -eq 1 ]
}

@test "state contains exact SHA and no proxy secret" {
  DOMAIN=proxy.example.com INBOUND_IP=203.0.113.10 ACME_EMAIL=admin@example.com
  UPSTREAM_COMMIT=0123456789012345678901234567890123456789
  UPSTREAM_LABEL=default-branch
  SECRET=0123456789abcdef0123456789abcdef
  printf '[]' >"$STATE/resources.json"
  save_state ready false "$STATE/resources.json"
  [ "$(jq -r .upstream_commit "$STATE/deployment.json")" = "$UPSTREAM_COMMIT" ]
  ! grep -Fq "$SECRET" "$STATE/deployment.json"
}

@test "update decision distinguishes same SHA" {
  update_needed a b
  run update_needed a a
  [ "$status" -eq 1 ]
}

@test "ownership validator only permits explicit managed paths" {
  managed_path /usr/local/bin/tproxy-server
  managed_path /opt/MTProxy/objs/bin/mtproto-proxy
  for path in /etc/passwd /etc/caddy/unrelated.conf /opt/MTProxy/../../etc/passwd /srv/another-site/index.html; do
    run managed_path "$path"
    [ "$status" -eq 1 ]
  done
}

@test "uninstall defaults keep config and website" {
  parse_cli uninstall --yes
  [ "$PURGE" = 0 ]
  [ "$REMOVE_SITE" = 0 ]
}

@test "uninstall plan excludes preserved classes" {
  printf '[{"path":"/usr/local/bin/tproxy-server","class":"runtime","sha256":"x"},{"path":"/etc/tproxy-server/profiles.json","class":"config","sha256":"y"}]' >"$STATE/resources.json"
  PURGE=0
  run selected_resources "$STATE/resources.json"
  [ "$status" -eq 0 ]
  [[ "$output" != *profiles.json* ]]
}

@test "help is available without root or dependencies" {
  run bash "$BATS_TEST_DIRNAME/../install.sh" help
  [ "$status" -eq 0 ]
  [[ "$output" == *'uninstall'* ]]
  [[ "$output" == *'show-link'* ]]
}

@test "fresh install refuses existing vendor services before activation" {
  systemctl() { printf loaded; }
  run fresh_integrations_clear
  [ "$status" -eq 1 ]
}
@test "fresh install refuses an unowned backend nftables table" {
  systemctl() {
    [[ "$*" != *LoadState* ]] || printf not-found
    return 0
  }
  nft() { printf '{"nftables":[{"table":{"family":"inet","name":"tproxy_backend"}}]}'; }
  run fresh_integrations_clear
  [ "$status" -eq 1 ]
  [[ "$output" == *'unowned'* ]]
}
@test "narrowed firewall rule cannot masquerade as backend protection" {
  local chain='{"chain":{"family":"inet","table":"tproxy_backend","name":"local_backend","type":"filter","hook":"input","prio":-10}}'
  local rule='{"rule":{"expr":[{"match":{"left":{"meta":{"key":"iifname"}},"op":"!=","right":"lo"}},{"match":{"left":{"payload":{"protocol":"tcp","field":"dport"}},"op":"==","right":{"set":[2398,8888]}}},{"match":{"left":{"payload":{"protocol":"ip","field":"saddr"}},"op":"==","right":"192.0.2.1"}},{"drop":null}]}}'
  run firewall_is_protected <<<"{\"nftables\":[$chain,$rule]}"
  [ "$status" -eq 1 ]
}
@test "purge preserves automatically refreshed upstream DC data" {
  printf '[{"path":"/etc/mtproxy/proxy-multi.conf","class":"config","sha256":"x"},{"path":"/etc/tproxy-server/profiles.json","class":"config","sha256":"y"}]' >"$STATE/resources.json"
  PURGE=1
  run selected_resources "$STATE/resources.json"
  [ "$status" -eq 0 ]
  [[ "$output" != *proxy-multi.conf* ]]
  [[ "$output" == *profiles.json* ]]
}

@test "publication tree contains no prohibited private deployment values or artifacts" {
  run python3 "$BATS_TEST_DIRNAME/hygiene.py"
  [ "$status" -eq 0 ]
}
