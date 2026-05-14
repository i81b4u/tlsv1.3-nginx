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

###############################################################################
# Metadata
###############################################################################

PROGNAME="$(basename "$0")"
VERSION="2.0.1"

###############################################################################
# Configuration
###############################################################################

# Versions
NGINX_COMMIT="release-1.31.0"
BORINGSSL_COMMIT="0.20260508.0"
NGX_BROTLI_COMMIT="master"

PREFIX="/opt/nginx"
BUILD_ROOT="/usr/src/nginx-build"

JOBS="$(nproc)"

###############################################################################
# Utility functions
###############################################################################

log() {
  printf '[%s] %s\n' "$PROGNAME" "$*"
}

die() {
  printf '[%s] ERROR: %s\n' "$PROGNAME" "$*" >&2
  exit 1
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "Must be run as root"
}

require_cmds() {
  local missing=()
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
  done
  [[ ${#missing[@]} -eq 0 ]] || die "Missing dependencies: ${missing[*]}"
}

cleanup() {
  log "Cleaning up build directory"
  rm -rf "$BUILD_ROOT"
}

trap cleanup EXIT

###############################################################################
# Preparation
###############################################################################

require_root
require_cmds git cmake ninja make patch sed wget

log "Using build root: $BUILD_ROOT"
mkdir -p "$BUILD_ROOT"

cd "$BUILD_ROOT"

###############################################################################
# Fetch sources
###############################################################################

log "Cloning nginx"
git clone https://github.com/nginx/nginx.git
cd nginx
git checkout "$NGINX_COMMIT"
cd ..

log "Cloning BoringSSL"
git clone https://github.com/google/boringssl.git
cd boringssl
git checkout "$BORINGSSL_COMMIT"
cd ..

log "Cloning ngx_brotli"
git clone --recurse-submodules https://github.com/google/ngx_brotli.git
cd ngx_brotli
git checkout "$NGX_BROTLI_COMMIT"
cd ..

###############################################################################
# Build Brotli
###############################################################################

log "Building Brotli"
cd ngx_brotli/deps/brotli
mkdir -p out
cd out

cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_INSTALL_PREFIX="$BUILD_ROOT/brotli-install" \
  ..

cmake --build . --target brotlienc -- -j"$JOBS"

###############################################################################
# Patch & build BoringSSL
###############################################################################

log "Patching BoringSSL (disable SHA-1 signing)"
cd "$BUILD_ROOT/boringssl"

# Example: external patch file (recommended)
# patch -p1 < ../patches/boringssl-disable-sha1.patch

sed -i \
  's/SSL_SIGN_RSA_PKCS1_SHA1,/\/\/ SSL_SIGN_RSA_PKCS1_SHA1,/' \
  ssl/extensions.cc

sed -i \
  's/SSL_SIGN_ECDSA_SHA1,/\/\/ SSL_SIGN_ECDSA_SHA1,/' \
  ssl/extensions.cc

mkdir -p build
cd build

cmake -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -B "$BUILD_ROOT/boringssl/build" \
  -S "$BUILD_ROOT/boringssl"

ninja -C "$BUILD_ROOT/boringssl/build" -j"$JOBS"

###############################################################################
# Patch nginx
###############################################################################

log "Patching nginx (dynamic TLS records)"
cd "$BUILD_ROOT/nginx"

wget -q \
  https://raw.githubusercontent.com/nginx-modules/ngx_http_tls_dyn_size/master/nginx__dynamic_tls_records_1.29.2%2B.patch

patch -p1 < nginx__dynamic_tls_records_1.29.2+.patch

###############################################################################
# Configure nginx
###############################################################################

log "Configuring nginx"

./auto/configure \
  --prefix="$PREFIX" \
  --conf-path="$PREFIX/etc/nginx.conf" \
  --sbin-path="$PREFIX/sbin/nginx" \
  --modules-path="$PREFIX/lib/modules" \
  --http-client-body-temp-path=/var/cache/nginx/client_temp \
  --lock-path=/var/run/nginx.lock \
  --pid-path=/var/run/nginx.pid \
  --http-log-path=/var/log/nginx/access.log \
  --error-log-path=/var/log/nginx/error.log \
  --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
  --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
  --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
  --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
  --user=www-data \
  --group=www-data \
  --with-cc=gcc \
  --with-compat \
  --with-debug \
  --add-module="$BUILD_ROOT/ngx_brotli" \
  --with-file-aio \
  --with-threads \
  --with-http_addition_module \
  --with-http_auth_request_module \
  --with-http_dav_module \
  --with-http_flv_module \
  --with-http_gunzip_module \
  --with-http_gzip_static_module \
  --with-http_mp4_module \
  --with-http_random_index_module \
  --with-http_realip_module \
  --with-http_secure_link_module \
  --with-http_slice_module \
  --with-http_ssl_module \
  --with-http_stub_status_module \
  --with-http_sub_module \
  --with-http_v2_module \
  --with-http_v3_module \
  --with-mail \
  --with-mail_ssl_module \
  --with-stream \
  --with-stream_realip_module \
  --with-stream_ssl_module \
  --with-stream_ssl_preread_module \
  --with-cc-opt="-g -O3 -flto=auto -ffat-lto-objects -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=3 -fPIC -I$BUILD_ROOT/boringssl/include -x c" \
  --with-ld-opt="-Wl,-Bsymbolic-functions -flto=auto -ffat-lto-objects -flto=auto -Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie -L$BUILD_ROOT/boringssl/build -lstdc++"

###############################################################################
# Branding tweaks (optional)
###############################################################################

log "Customizing server headers"

sed -i -e "s/static const u_char nginx\[5\] = { 0x84, 0xaa, 0x63, 0x55, 0xe7 };/static const u_char nginx\[6\] = { 0x85, 0x33, 0xc1, 0x8d, 0xab, 0x7f };/g" \
  src/http/v2/ngx_http_v2_filter_module.c

sed -i 's/Server: nginx/Server: i81b4u/' \
  src/http/ngx_http_header_filter_module.c

sed -i 's/"nginx"/"i81b4u"/g' \
  src/http/v3/ngx_http_v3_filter_module.c

sed -i 's/<center>nginx/<center>i81b4u/' \
  src/http/ngx_http_special_response.c

###############################################################################
# Build & install
###############################################################################

log "Building nginx"
make -j"$JOBS"

log "Installing nginx"
make install

log "Build completed successfully"
