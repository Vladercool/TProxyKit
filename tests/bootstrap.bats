#!/usr/bin/env bats
setup() {
  source "$BATS_TEST_DIRNAME/../bootstrap.sh"
  BOOT_REPO=example/deploy
  TEST_ROOT="$BATS_TEST_TMPDIR/bootstrap"
  mkdir -p "$TEST_ROOT"
}
@test "bootstrap resolves a stable release redirect" {
  curl() { printf 'https://github.com/example/deploy/releases/tag/v1.2.3'; }
  run bootstrap_release
  [ "$status" -eq 0 ]
  [ "$output" = v1.2.3 ]
}
@test "bootstrap refuses release redirects to other origins" {
  curl() { printf 'https://evil.example/releases/tag/v1.2.3'; }
  run bootstrap_release
  [ "$status" -eq 1 ]
}
@test "bootstrap validates exactly the installer checksum" {
  printf 'exit 0\n' >"$TEST_ROOT/install.sh"
  (
    cd "$TEST_ROOT"
    sha256sum install.sh >SHA256SUMS
  )
  bootstrap_verify "$TEST_ROOT"
  printf '# tampered\n' >>"$TEST_ROOT/install.sh"
  run bootstrap_verify "$TEST_ROOT"
  [ "$status" -eq 1 ]
}
@test "checksum manifest cannot select arbitrary paths" {
  printf '%064d  ../evil\n' 0 >"$TEST_ROOT/SHA256SUMS"
  run bootstrap_verify "$TEST_ROOT"
  [ "$status" -eq 1 ]
}
@test "bootstrap forwards arguments and cleans its private directory" {
  export BOOT_TEST_RECORD="$TEST_ROOT/args"
  bootstrap_release() { printf v1.0.0; }
  bootstrap_download() {
    if [[ "$1" == */install.sh ]]; then
      printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$BOOT_TEST_RECORD"\n' >"$2"
    else
      (
        cd "${2%/*}"
        sha256sum install.sh >SHA256SUMS
      )
      printf '%s\n' "${2%/*}" >"$TEST_ROOT/workdir"
    fi
  }
  bootstrap_main status --yes
  [ "$(cat "$BOOT_TEST_RECORD")" = $'status\n--yes' ]
  [ ! -e "$(cat "$TEST_ROOT/workdir")" ]
}

@test "bootstrap mismatch never executes installer and still cleans workdir" {
  bootstrap_release() { printf v1.0.0; }
  bootstrap_download() {
    printf '%s\n' "${2%/*}" >"$TEST_ROOT/workdir"
    if [[ "$1" == */install.sh ]]; then
      printf '#!/usr/bin/env bash\ntouch "%s/executed"\n' "$TEST_ROOT" >"$2"
    else
      printf '%064d  install.sh\n' 0 >"$2"
    fi
  }
  run bootstrap_main install
  [ "$status" -eq 1 ]
  [ ! -e "$TEST_ROOT/executed" ]
  [ ! -e "$(cat "$TEST_ROOT/workdir")" ]
}
@test "bootstrap download failure does not execute partial content" {
  bootstrap_release() { printf v1.0.0; }
  bootstrap_download() {
    printf '%s\n' "${2%/*}" >"$TEST_ROOT/workdir"
    printf '#!/usr/bin/env bash\ntouch "%s/executed"\n' "$TEST_ROOT" >"$2"
    return 1
  }
  run bootstrap_main install
  [ "$status" -eq 1 ]
  [ ! -e "$TEST_ROOT/executed" ]
  [ ! -e "$(cat "$TEST_ROOT/workdir")" ]
}
