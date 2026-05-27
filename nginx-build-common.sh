#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

: "${SCRIPT_DIR:?SCRIPT_DIR must be set before sourcing nginx-build-common.sh}"
: "${TLS_BACKEND:?TLS_BACKEND must be set before sourcing nginx-build-common.sh}"
: "${NGINX_COMMIT:?NGINX_COMMIT must be set before sourcing nginx-build-common.sh}"
: "${NGX_BROTLI_COMMIT:?NGX_BROTLI_COMMIT must be set before sourcing nginx-build-common.sh}"

PROGNAME="$(basename "$0")"
VERSION="3.0.0"

PREFIX="${PREFIX:-/opt/nginx}"
SOURCE_ROOT="${SOURCE_ROOT:-$SCRIPT_DIR}"
BUILD_ROOT="${BUILD_ROOT:-${TMPDIR:-/tmp}/nginx-build-$TLS_BACKEND}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs/$TLS_BACKEND-$(date +%Y%m%d-%H%M%S)}"
JOBS="${JOBS:-$(nproc)}"
RUNTIME_ROOT="${RUNTIME_ROOT:-}"

KEEP_BUILD=0
INSTALL_NGINX=1
APPLY_BRANDING=1
DEBUG_BUILD=1
CONFIG_TEST=1

PATCH_DIR="$SCRIPT_DIR/patches"
DYNAMIC_TLS_PATCH="$PATCH_DIR/nginx-dynamic-tls-records-1.29.2-plus.patch"
BRANDING_PATCH="$PATCH_DIR/nginx-brand-i81b4u.patch"

log() {
  printf '[%s] %s\n' "$PROGNAME" "$*"
}

die() {
  printf '[%s] ERROR: %s\n' "$PROGNAME" "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
$PROGNAME $VERSION

Usage: $PROGNAME [options]

Options:
  --prefix DIR       Install prefix. Default: $PREFIX
  --source-root DIR  Source mirror root. Default: $SOURCE_ROOT
  --build-root DIR   Temporary build root. Default: $BUILD_ROOT
  --log-dir DIR      Build log directory. Default: timestamped directory under ./logs
  --runtime-root DIR Put pid, lock, log, and cache paths under DIR. Default: /var paths
  --jobs N           Parallel build jobs. Default: $JOBS
  --keep-build       Keep the build directory after a successful build
  --no-install       Build only; do not run make install
  --no-branding      Do not apply the i81b4u server-header patch
  --no-config-test   Skip nginx -t after install
  --debug            Include --with-debug. Default
  --release          Omit --with-debug
  -h, --help         Show this help text
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --prefix)
        PREFIX="${2:?Missing value for --prefix}"
        shift 2
        ;;
      --prefix=*)
        PREFIX="${1#*=}"
        shift
        ;;
      --source-root)
        SOURCE_ROOT="${2:?Missing value for --source-root}"
        shift 2
        ;;
      --source-root=*)
        SOURCE_ROOT="${1#*=}"
        shift
        ;;
      --build-root)
        BUILD_ROOT="${2:?Missing value for --build-root}"
        shift 2
        ;;
      --build-root=*)
        BUILD_ROOT="${1#*=}"
        shift
        ;;
      --log-dir)
        LOG_DIR="${2:?Missing value for --log-dir}"
        shift 2
        ;;
      --log-dir=*)
        LOG_DIR="${1#*=}"
        shift
        ;;
      --runtime-root)
        RUNTIME_ROOT="${2:?Missing value for --runtime-root}"
        shift 2
        ;;
      --runtime-root=*)
        RUNTIME_ROOT="${1#*=}"
        shift
        ;;
      --jobs)
        JOBS="${2:?Missing value for --jobs}"
        shift 2
        ;;
      --jobs=*)
        JOBS="${1#*=}"
        shift
        ;;
      --keep-build)
        KEEP_BUILD=1
        shift
        ;;
      --no-install)
        INSTALL_NGINX=0
        shift
        ;;
      --no-branding)
        APPLY_BRANDING=0
        shift
        ;;
      --no-config-test)
        CONFIG_TEST=0
        shift
        ;;
      --debug)
        DEBUG_BUILD=1
        shift
        ;;
      --release)
        DEBUG_BUILD=0
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done
}

require_cmds() {
  local missing=()
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
  done
  [[ ${#missing[@]} -eq 0 ]] || die "Missing dependencies: ${missing[*]}"
}

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null; then
    sudo "$@"
  else
    die "Root privileges are required for: $*"
  fi
}

run_logged() {
  local name="$1"
  shift

  mkdir -p "$LOG_DIR"
  log "Running $name"
  "$@" 2>&1 | tee "$LOG_DIR/$name.log"
}

cleanup() {
  local status=$?

  if [[ "$KEEP_BUILD" -eq 1 || "$status" -ne 0 ]]; then
    log "Keeping build directory: $BUILD_ROOT"
    log "Logs are in: $LOG_DIR"
    return
  fi

  log "Cleaning up build directory"
  rm -rf "$BUILD_ROOT"
  log "Logs are in: $LOG_DIR"
}

clone_source() {
  local name="$1"
  local url="$2"
  local commit="$3"
  local update_submodules="${4:-0}"
  local local_source="$SOURCE_ROOT/$name"

  log "Cloning $name"

  if [[ -d "$local_source/.git" ]]; then
    git clone "$local_source" "$BUILD_ROOT/$name"
  else
    git clone --recurse-submodules "$url" "$BUILD_ROOT/$name"
  fi

  cd "$BUILD_ROOT/$name"
  git checkout "$commit"

  if [[ -e "$local_source/deps/brotli/.git" ]]; then
    git submodule set-url deps/brotli "$local_source/deps/brotli"
  fi

  if [[ "$update_submodules" -eq 1 ]]; then
    git -c protocol.file.allow=always submodule update --init --recursive
  fi

  cd "$BUILD_ROOT"
}

apply_patch_file() {
  local label="$1"
  local patch_file="$2"

  [[ -f "$patch_file" ]] || die "Missing patch file: $patch_file"

  log "Applying $label"
  patch -p1 < "$patch_file"
}

prepare_build_root() {
  [[ "$BUILD_ROOT" == / ]] && die "Refusing to use / as build root"

  rm -rf "$BUILD_ROOT"
  mkdir -p "$BUILD_ROOT" "$LOG_DIR"
  cd "$BUILD_ROOT"
}

set_runtime_paths() {
  if [[ -n "$RUNTIME_ROOT" ]]; then
    LOCK_PATH="$RUNTIME_ROOT/run/nginx.lock"
    PID_PATH="$RUNTIME_ROOT/run/nginx.pid"
    HTTP_LOG_PATH="$RUNTIME_ROOT/log/nginx/access.log"
    ERROR_LOG_PATH="$RUNTIME_ROOT/log/nginx/error.log"
    CLIENT_BODY_TEMP_PATH="$RUNTIME_ROOT/cache/nginx/client_temp"
    FASTCGI_TEMP_PATH="$RUNTIME_ROOT/cache/nginx/fastcgi_temp"
    PROXY_TEMP_PATH="$RUNTIME_ROOT/cache/nginx/proxy_temp"
    SCGI_TEMP_PATH="$RUNTIME_ROOT/cache/nginx/scgi_temp"
    UWSGI_TEMP_PATH="$RUNTIME_ROOT/cache/nginx/uwsgi_temp"
  else
    LOCK_PATH=/var/run/nginx.lock
    PID_PATH=/var/run/nginx.pid
    HTTP_LOG_PATH=/var/log/nginx/access.log
    ERROR_LOG_PATH=/var/log/nginx/error.log
    CLIENT_BODY_TEMP_PATH=/var/cache/nginx/client_temp
    FASTCGI_TEMP_PATH=/var/cache/nginx/fastcgi_temp
    PROXY_TEMP_PATH=/var/cache/nginx/proxy_temp
    SCGI_TEMP_PATH=/var/cache/nginx/scgi_temp
    UWSGI_TEMP_PATH=/var/cache/nginx/uwsgi_temp
  fi
}

fetch_sources() {
  clone_source nginx https://github.com/nginx/nginx.git "$NGINX_COMMIT" 0
  clone_source ngx_brotli https://github.com/google/ngx_brotli.git "$NGX_BROTLI_COMMIT" 1
}

build_brotli() {
  log "Building Brotli"
  cd "$BUILD_ROOT/ngx_brotli/deps/brotli"
  mkdir -p out
  cd out

  run_logged brotli-cmake \
    cmake \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      -DCMAKE_INSTALL_PREFIX="$BUILD_ROOT/brotli-install" \
      ..

  run_logged brotli-build \
    cmake --build . --target brotlienc -- -j"$JOBS"
}

patch_nginx() {
  cd "$BUILD_ROOT/nginx"
  apply_patch_file "nginx dynamic TLS records patch" "$DYNAMIC_TLS_PATCH"

  if [[ "$APPLY_BRANDING" -eq 1 ]]; then
    apply_patch_file "nginx branding patch" "$BRANDING_PATCH"
  fi
}

base_configure_args() {
  CONFIGURE_ARGS=(
    --prefix="$PREFIX"
    --conf-path="$PREFIX/etc/nginx.conf"
    --sbin-path="$PREFIX/sbin/nginx"
    --modules-path="$PREFIX/lib/modules"
    --http-client-body-temp-path="$CLIENT_BODY_TEMP_PATH"
    --lock-path="$LOCK_PATH"
    --pid-path="$PID_PATH"
    --http-log-path="$HTTP_LOG_PATH"
    --error-log-path="$ERROR_LOG_PATH"
    --http-fastcgi-temp-path="$FASTCGI_TEMP_PATH"
    --http-proxy-temp-path="$PROXY_TEMP_PATH"
    --http-scgi-temp-path="$SCGI_TEMP_PATH"
    --http-uwsgi-temp-path="$UWSGI_TEMP_PATH"
    --user=www-data
    --group=www-data
    --with-compat
    --add-module="$BUILD_ROOT/ngx_brotli"
    --with-file-aio
    --with-threads
    --with-http_addition_module
    --with-http_auth_request_module
    --with-http_dav_module
    --with-http_flv_module
    --with-http_gunzip_module
    --with-http_gzip_static_module
    --with-http_mp4_module
    --with-http_random_index_module
    --with-http_realip_module
    --with-http_secure_link_module
    --with-http_slice_module
    --with-http_ssl_module
    --with-http_stub_status_module
    --with-http_sub_module
    --with-http_v2_module
    --with-http_v3_module
    --with-mail
    --with-mail_ssl_module
    --with-stream
    --with-stream_realip_module
    --with-stream_ssl_module
    --with-stream_ssl_preread_module
  )

  if [[ "$DEBUG_BUILD" -eq 1 ]]; then
    CONFIGURE_ARGS+=(--with-debug)
  fi
}

configure_nginx() {
  cd "$BUILD_ROOT/nginx"
  base_configure_args
  add_tls_configure_args

  run_logged nginx-configure ./auto/configure "${CONFIGURE_ARGS[@]}"
}

build_nginx() {
  cd "$BUILD_ROOT/nginx"
  run_logged nginx-build make -j"$JOBS"
}

install_nginx() {
  [[ "$INSTALL_NGINX" -eq 1 ]] || return

  cd "$BUILD_ROOT/nginx"

  if [[ -w "$(dirname "$PREFIX")" ]]; then
    run_logged nginx-install make install
  else
    run_logged nginx-install as_root make install
  fi
}

ensure_runtime_dirs() {
  [[ "$INSTALL_NGINX" -eq 1 ]] || return

  local dirs=(
    "$(dirname "$LOCK_PATH")"
    "$(dirname "$PID_PATH")"
    "$(dirname "$HTTP_LOG_PATH")"
    "$(dirname "$ERROR_LOG_PATH")"
    "$CLIENT_BODY_TEMP_PATH"
    "$FASTCGI_TEMP_PATH"
    "$PROXY_TEMP_PATH"
    "$SCGI_TEMP_PATH"
    "$UWSGI_TEMP_PATH"
  )

  if [[ -n "$RUNTIME_ROOT" && -w "$(dirname "$RUNTIME_ROOT")" ]]; then
    mkdir -p "${dirs[@]}"
    return
  fi

  for dir in "${dirs[@]}"; do
    if [[ -w "$(dirname "$dir")" ]]; then
      mkdir -p "$dir"
    else
      as_root mkdir -p "$dir"
    fi
  done
}

verify_nginx() {
  [[ "$INSTALL_NGINX" -eq 1 ]] || return

  run_logged nginx-version "$PREFIX/sbin/nginx" -V

  if [[ "$CONFIG_TEST" -eq 1 ]]; then
    run_logged nginx-config-test "$PREFIX/sbin/nginx" -t
  fi
}

main() {
  parse_args "$@"
  trap cleanup EXIT
  set_runtime_paths

  require_cmds git cmake make patch tee
  require_tls_cmds

  log "Using source root: $SOURCE_ROOT"
  log "Using build root: $BUILD_ROOT"
  log "Using log directory: $LOG_DIR"
  [[ -n "$RUNTIME_ROOT" ]] && log "Using runtime root: $RUNTIME_ROOT"

  prepare_build_root
  fetch_sources
  fetch_tls_source
  build_brotli
  build_tls
  patch_nginx
  configure_nginx
  build_nginx
  install_nginx
  ensure_runtime_dirs
  verify_nginx

  log "Build completed successfully"
}
