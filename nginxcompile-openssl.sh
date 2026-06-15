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

# Source refs:
# - These can be tag names, branch names, or commit hashes.
# - Tags and commit hashes are stable. Branch names follow the branch state
#   available from the cloned remote or local source mirror.

# nginx 1.31.1 release
NGINX_REF="release-1.31.1"

# OpenSSL 4.0.1 release
OPENSSL_REF="openssl-4.0.1"

# ngx_brotli branch compatible with this nginx build
NGX_BROTLI_REF="master"

# OpenSSL is built by nginx itself through --with-openssl, so there are no
# extra backend tools to require beyond the common build dependencies.
require_tls_cmds() {
  :
}

# Fetch the OpenSSL source tree that nginx will compile as part of its own
# build.
fetch_tls_source() {
  clone_source openssl https://github.com/openssl/openssl.git "$OPENSSL_REF" 0
}

# No separate OpenSSL build step is needed here; nginx drives it during make.
build_tls() {
  :
}

# Add the nginx configure options that select the OpenSSL tree and enable
# the OpenSSL features expected by this build.
add_tls_configure_args() {
  CONFIGURE_ARGS+=(
    --with-openssl="$BUILD_ROOT/openssl"
    --with-openssl-opt="no-tests enable-ktls enable-tls1_3 enable-ec_nistp_64_gcc_128 enable-zlib"
    --with-cc-opt="-g -O2 -flto=auto -ffat-lto-objects -fstack-protector-strong -Wformat -Werror=format-security -fPIC"
    --with-ld-opt="-Wl,-Bsymbolic-functions -flto=auto -ffat-lto-objects -Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie"
  )
}

# The common script provides argument parsing, source setup, nginx configure,
# build, install, verification, and final permissions handling.
source "$SCRIPT_DIR/nginx-build-common.sh"

main "$@"
