#!/usr/bin/env bash
# shellcheck disable=SC2016 # Case bodies expand in the child shell.
# Offline regression checks; no downloads, installation, or sudo.
set -Eeuo pipefail
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/nginx-script-tests.XXXXXXXX)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
export REPO TEST_ROOT

run_case() {
  local name="$1"
  shift
  bash -Eeuo pipefail -c '
    SCRIPT_DIR="$REPO"
    TLS_BACKEND=test NGINX_REF=test NGX_BROTLI_REF=test
    source "$REPO/nginx-build-common.sh"
    SOURCE_ROOT="$TEST_ROOT/sources"
    BUILD_ROOT="$TEST_ROOT/builds"
    LOG_DIR="$TEST_ROOT/logs"
    PREFIX="$TEST_ROOT/install"
    RUNTIME_ROOT="$TEST_ROOT/runtime"
    eval "$1"
  ' _ "$*"
  printf 'PASS: %s\n' "$name"
}

run_case 'cleanup preserves existing files and other builds' '
  mkdir -p "$BUILD_ROOT/previous"
  touch "$BUILD_ROOT/previous/keep"
  parent="$BUILD_ROOT"
  validate_options
  prepare_build_root
  own="$BUILD_ROOT"
  touch "$own/artifact"
  cleanup
  trap - EXIT
  [[ ! -e "$own" && -f "$parent/previous/keep" ]]
'
run_case 'failed builds remain available' '
  validate_options
  prepare_build_root
  own="$BUILD_ROOT"
  (trap cleanup EXIT; exit 7) && exit 1
  [[ -d "$own" ]]
  trap - EXIT
'
run_case 'build-only pipeline retains and verifies its binary' '
  require_tls_cmds() { :; }
  fetch_sources() { :; }
  fetch_tls_source() { :; }
  build_brotli() { :; }
  build_tls() { :; }
  patch_nginx() { :; }
  configure_nginx() { :; }
  build_nginx() {
    mkdir -p "$BUILD_ROOT/nginx/objs"
    printf "#!/bin/sh\necho verified-build\n" > "$BUILD_ROOT/nginx/objs/nginx"
    chmod +x "$BUILD_ROOT/nginx/objs/nginx"
  }
  as_root() { echo "Unexpected privileged operation" >&2; exit 1; }
  main --no-install
  cleanup
  trap - EXIT
  [[ -x "$BUILD_ROOT/nginx/objs/nginx" ]]
  grep -q verified-build "$LOG_DIR/nginx-version.log"
'
run_case 'relative paths resolve before changing directories' '
  cd "$TEST_ROOT"
  PREFIX=install SOURCE_ROOT=sources BUILD_ROOT=builds LOG_DIR=logs RUNTIME_ROOT=runtime
  validate_options
  [[ "$PREFIX" == "$TEST_ROOT/install" && "$LOG_DIR" == "$TEST_ROOT/logs" ]]
'
run_case 'unsafe and overlapping paths fail without deleting data' '
  touch "$TEST_ROOT/keep"
  (PREFIX=/; validate_options) && exit 1
  (PREFIX="/tmp/with space"; validate_options) && exit 1
  (BUILD_ROOT="$REPO"; prepare_build_root) && exit 1
  (LOG_DIR="$BUILD_ROOT/logs"; prepare_build_root) && exit 1
  [[ -f "$TEST_ROOT/keep" ]]
'
run_case 'new configure features are enabled for both backends' '
  set_runtime_paths
  base_configure_args
  for expected in --with-control-api --with-http_json_module --with-pcre-jit; do
    found=0
    for arg in "${CONFIGURE_ARGS[@]}"; do
      if [[ "$arg" == "$expected" ]]; then found=1; fi
    done
    [[ "$found" == 1 ]]
  done
'
