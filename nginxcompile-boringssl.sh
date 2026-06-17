#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Build nginx with QUIC + BoringSSL
# -----------------------------------------------------------------------------
#
# NOTE:
# For QUIC + BoringSSL:
# - DO NOT use --with-openssl
# - BoringSSL must be prebuilt and linked explicitly
# See: https://nginx.org/en/docs/quic.html

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

TLS_BACKEND="boringssl"

# Source refs:
# - These can be tag names, branch names, or commit hashes.
# - Tags and commit hashes are stable. Branch names follow the branch state
#   available from the cloned remote or local source mirror.

# nginx 1.31.2 release
NGINX_REF="release-1.31.2"

# BoringSSL 0.20260616.0 snapshot
BORINGSSL_REF="0.20260616.0"

# ngx_brotli branch compatible with this nginx build
NGX_BROTLI_REF="master"

BORINGSSL_SHA1_PATCH="$SCRIPT_DIR/patches/boringssl-disable-sha1-signatures.patch"

# BoringSSL is built separately with Ninja before nginx is configured.
require_tls_cmds() {
  require_cmds ninja
}

# Fetch the selected BoringSSL source tree used for this build.
fetch_tls_source() {
  clone_source boringssl https://github.com/google/boringssl.git "$BORINGSSL_REF" 0
}

# Build BoringSSL's crypto and ssl libraries, then nginx links against them
# explicitly through add_tls_configure_args().
build_tls() {
  log "Building BoringSSL"
  cd "$BUILD_ROOT/boringssl"

  apply_patch_file "BoringSSL SHA-1 signature policy patch" "$BORINGSSL_SHA1_PATCH"

  run_logged boringssl-cmake \
    cmake -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      -B "$BUILD_ROOT/boringssl/build" \
      -S "$BUILD_ROOT/boringssl"

  run_logged boringssl-build \
    ninja -C "$BUILD_ROOT/boringssl/build" crypto ssl -j"$JOBS"
}

# Add compiler and linker options that make nginx use the prebuilt BoringSSL
# headers and libraries. BoringSSL is not passed through --with-openssl.
add_tls_configure_args() {
  CONFIGURE_ARGS+=(
    --with-cc=gcc
    --with-cc-opt="-g -O3 -flto=auto -ffat-lto-objects -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=3 -fPIC -I$BUILD_ROOT/boringssl/include -x c"
    --with-ld-opt="-Wl,-Bsymbolic-functions -flto=auto -ffat-lto-objects -flto=auto -Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie -L$BUILD_ROOT/boringssl/build -lstdc++"
  )
}

# The common script provides argument parsing, source setup, nginx configure,
# build, install, verification, and final permissions handling.
source "$SCRIPT_DIR/nginx-build-common.sh"

main "$@"
