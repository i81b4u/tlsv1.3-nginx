#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Build nginx with QUIC + OpenSSL
# -----------------------------------------------------------------------------
#
# NOTE:
# For QUIC + OpenSSL:
# - Use --with-openssl so nginx builds against the requested OpenSSL tree
# - OpenSSL QUIC support requires a sufficiently new OpenSSL release
# See: https://nginx.org/en/docs/quic.html

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

TLS_BACKEND="openssl"

# Version pins:
# - These are immutable commit hashes so repeated builds use the same sources.
# - The comments describe the human-readable version or branch intent.
# - To update a pin, checkout the intended tag or branch in the local repo,
#   verify the build, then record the exact commit with:
#
#     git -C nginx rev-parse HEAD
#     git -C openssl rev-parse HEAD
#     git -C ngx_brotli rev-parse HEAD
#
# - Update both the comment and the hash together.

# nginx 1.31.1 mainline snapshot
NGINX_COMMIT="d44205284fa41662da803b796d6056fc1e59b1f3"

# OpenSSL 4.1.0-dev snapshot from the OpenSSL development branch
OPENSSL_COMMIT="a31d5fe8f718c6f5ac22567d58273a21993d5345"

# ngx_brotli snapshot compatible with this nginx build
NGX_BROTLI_COMMIT="a71f9312c2deb28875acc7bacfdd5695a111aa53"

require_tls_cmds() {
  :
}

fetch_tls_source() {
  clone_source openssl https://github.com/openssl/openssl.git "$OPENSSL_COMMIT" 0
}

build_tls() {
  :
}

add_tls_configure_args() {
  CONFIGURE_ARGS+=(
    --with-openssl="$BUILD_ROOT/openssl"
    --with-openssl-opt="no-tests enable-ktls enable-tls1_3 enable-ec_nistp_64_gcc_128 enable-zlib"
    --with-cc-opt="-g -O2 -flto=auto -ffat-lto-objects -fstack-protector-strong -Wformat -Werror=format-security -fPIC"
    --with-ld-opt="-Wl,-Bsymbolic-functions -flto=auto -ffat-lto-objects -Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie"
  )
}

source "$SCRIPT_DIR/nginx-build-common.sh"

main "$@"
