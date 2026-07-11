#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Shared nginx build workflow
# -----------------------------------------------------------------------------
#
# This file is sourced by nginxcompile-openssl.sh and
# nginxcompile-boringssl.sh. The wrapper script sets the TLS backend, version
# refs, and backend-specific functions; this file handles the common nginx,
# Brotli, install, verification, and permissions workflow.

set -Eeuo pipefail
IFS=$'\n\t'

# The wrapper must define these values before sourcing this file.
: "${SCRIPT_DIR:?SCRIPT_DIR must be set before sourcing nginx-build-common.sh}"
: "${TLS_BACKEND:?TLS_BACKEND must be set before sourcing nginx-build-common.sh}"
: "${NGINX_REF:?NGINX_REF must be set before sourcing nginx-build-common.sh}"
: "${NGX_BROTLI_REF:?NGX_BROTLI_REF must be set before sourcing nginx-build-common.sh}"

PROGNAME="$(basename "$0")"
VERSION="3.0.1"

# Default build locations. Every value can be overridden from the environment
# or, for the common paths, by command-line options.
PREFIX="${PREFIX:-/opt/nginx}"
SOURCE_ROOT="${SOURCE_ROOT:-$SCRIPT_DIR}"
BUILD_ROOT="${BUILD_ROOT:-${TMPDIR:-/tmp}/nginx-build-$TLS_BACKEND}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs/$TLS_BACKEND-$(date +%Y%m%d-%H%M%S)}"
JOBS="${JOBS:-$(nproc)}"
RUNTIME_ROOT="${RUNTIME_ROOT:-}"
NGINX_INSTALL_OWNER="${NGINX_INSTALL_OWNER:-www-data}"
NGINX_INSTALL_GROUP="${NGINX_INSTALL_GROUP:-root}"

# Runtime switches controlled by command-line options.
KEEP_BUILD=0
INSTALL_NGINX=1
APPLY_BRANDING=1
DEBUG_BUILD=1
CONFIG_TEST=1
FIX_PERMISSIONS=1

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

# Print the options supported by both TLS backend wrappers.
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
  --no-fix-permissions
                     Skip post-install nginx ownership and permissions setup
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
      --no-fix-permissions)
        FIX_PERMISSIONS=0
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

# Validate values that are accepted from command-line options or the
# environment before they are interpolated into build commands.
validate_options() {
  [[ -n "$PREFIX" ]] || die "Install prefix must not be empty"
  [[ -n "$SOURCE_ROOT" ]] || die "Source root must not be empty"
  [[ -n "$BUILD_ROOT" ]] || die "Build root must not be empty"
  [[ -n "$LOG_DIR" ]] || die "Log directory must not be empty"
  [[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "Jobs must be a positive integer: $JOBS"
}

# Fail early when a required external tool is missing.
require_cmds() {
  local missing=()
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
  done
  [[ ${#missing[@]} -eq 0 ]] || die "Missing dependencies: ${missing[*]}"
}

# Run a command as root. This lets normal users build while still installing
# into system-owned locations such as /opt and /var.
as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null; then
    sudo "$@"
  else
    die "Root privileges are required for: $*"
  fi
}

# Run a command while streaming output to the terminal and saving the same
# output to a named log file under LOG_DIR.
run_logged() {
  local name="$1"
  shift

  mkdir -p "$LOG_DIR"
  log "Running $name"
  "$@" 2>&1 | tee "$LOG_DIR/$name.log"
}

# Remove the temporary build tree after successful builds. Failed builds and
# --keep-build keep the tree in place for inspection.
cleanup() {
  local status=$?

  if [[ "$KEEP_BUILD" -eq 1 || "$status" -ne 0 ]]; then
    log "Keeping build directory: $BUILD_ROOT"
    log "Logs are in: $LOG_DIR"
    return
  fi

  log "Cleaning up build directory"
  rm -rf -- "$BUILD_ROOT"
  log "Logs are in: $LOG_DIR"
}

# Check out a Git ref. Tags and commit hashes are checked out directly. Branch
# names that only exist on origin are checked out as local branches.
checkout_ref() {
  local name="$1"
  local ref="$2"

  if git rev-parse --verify --quiet "$ref^{commit}" >/dev/null; then
    git checkout "$ref"
    return
  fi

  if git show-ref --verify --quiet "refs/remotes/origin/$ref"; then
    git checkout -B "$ref" "origin/$ref"
    return
  fi

  die "Unable to check out $name ref: $ref"
}

# Clone a selected source tree into the temporary build root. If a local mirror
# exists under SOURCE_ROOT, clone from that mirror to avoid unnecessary network
# traffic and to preserve the user's checked-out source cache.
clone_source() {
  local name="$1"
  local url="$2"
  local ref="$3"
  local update_submodules="${4:-0}"
  local local_source="$SOURCE_ROOT/$name"

  log "Cloning $name at $ref"

  if [[ -d "$local_source/.git" ]]; then
    git clone "$local_source" "$BUILD_ROOT/$name"
  else
    git clone "$url" "$BUILD_ROOT/$name"
  fi

  cd "$BUILD_ROOT/$name"
  checkout_ref "$name" "$ref"

  # If ngx_brotli was cloned locally with its Brotli dependency present, point
  # the submodule at that local copy too.
  if [[ -e "$local_source/deps/brotli/.git" ]]; then
    git submodule set-url deps/brotli "$local_source/deps/brotli"
  fi

  if [[ "$update_submodules" -eq 1 ]]; then
    git -c protocol.file.allow=always submodule update --init --recursive
  fi

  cd "$BUILD_ROOT"
}

# Apply a repository patch from the patches directory.
apply_patch_file() {
  local label="$1"
  local patch_file="$2"

  [[ -f "$patch_file" ]] || die "Missing patch file: $patch_file"

  log "Applying $label"
  patch -p1 < "$patch_file"
}

# Reject build roots whose removal could delete the repository, a broad system
# directory, or the invoking directory.  realpath -m also normalizes paths
# such as ".", "..", and paths that do not yet exist.
validate_build_root() {
  local build_root source_root script_dir home_dir

  [[ -n "$BUILD_ROOT" ]] || die "Build root must not be empty"

  build_root="$(realpath -m -- "$BUILD_ROOT")"
  source_root="$(realpath -m -- "$SOURCE_ROOT")"
  script_dir="$(realpath -m -- "$SCRIPT_DIR")"
  home_dir=""
  if [[ -n "${HOME:-}" ]]; then
    home_dir="$(realpath -m -- "$HOME")"
  fi

  case "$build_root" in
    /|/tmp|/var/tmp|"$source_root"|"$script_dir")
      die "Refusing unsafe build root: $build_root"
      ;;
  esac

  if [[ -n "$home_dir" && "$build_root" == "$home_dir" ]]; then
    die "Refusing unsafe build root: $build_root"
  fi

  if [[ "$build_root" == "$source_root/"* || "$build_root" == "$script_dir/"* \
    || "$source_root" == "$build_root/"* || "$script_dir" == "$build_root/"* ]]; then
    die "Refusing build root that overlaps source files: $build_root"
  fi

  BUILD_ROOT="$build_root"
}

# Start every build from a clean temporary directory.
prepare_build_root() {
  validate_build_root

  rm -rf -- "$BUILD_ROOT"
  mkdir -p -- "$BUILD_ROOT" "$LOG_DIR"
  cd "$BUILD_ROOT"
}

# Resolve nginx runtime paths. By default the installed nginx uses the usual
# /var paths. --runtime-root moves those paths under one alternate directory,
# which is useful for test installs or non-system deployments.
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

# Fetch the source trees that are common to both OpenSSL and BoringSSL builds.
fetch_sources() {
  clone_source nginx https://github.com/nginx/nginx.git "$NGINX_REF" 0
  clone_source ngx_brotli https://github.com/google/ngx_brotli.git "$NGX_BROTLI_REF" 1
}

# Build the Brotli encoder library used by ngx_brotli. The nginx configure step
# later adds ngx_brotli as a static module.
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

# Apply local nginx patches before configure. Branding is optional so users can
# keep the stock nginx server header if desired.
patch_nginx() {
  cd "$BUILD_ROOT/nginx"
  apply_patch_file "nginx dynamic TLS records patch" "$DYNAMIC_TLS_PATCH"

  if [[ "$APPLY_BRANDING" -eq 1 ]]; then
    apply_patch_file "nginx branding patch" "$BRANDING_PATCH"
  fi
}

# Configure arguments shared by both TLS backends. Backend-specific scripts add
# their TLS compiler/linker flags through add_tls_configure_args().
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

# Generate nginx makefiles with the shared options plus the selected TLS backend
# options supplied by the wrapper script.
configure_nginx() {
  cd "$BUILD_ROOT/nginx"
  base_configure_args
  add_tls_configure_args

  run_logged nginx-configure ./auto/configure "${CONFIGURE_ARGS[@]}"
}

# Compile nginx using the configured parallel job count.
build_nginx() {
  cd "$BUILD_ROOT/nginx"
  run_logged nginx-build make -j"$JOBS"
}

# Install nginx. System prefixes usually need sudo; user-writable prefixes do
# not.
install_nginx() {
  [[ "$INSTALL_NGINX" -eq 1 ]] || return 0

  cd "$BUILD_ROOT/nginx"

  if [[ -w "$(dirname "$PREFIX")" ]]; then
    run_logged nginx-install make install
  else
    run_logged nginx-install as_root make install
  fi
}

# Create directories referenced by the nginx configure arguments before running
# nginx -t. This prevents config verification from failing on missing log,
# pid, lock, or cache directories.
ensure_runtime_dirs() {
  [[ "$INSTALL_NGINX" -eq 1 ]] || return 0

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

# Apply the local ownership and permission policy after nginx has been verified.
# This intentionally runs after nginx -V and nginx -t because strict 750/640
# permissions can prevent the invoking user from executing the installed binary.
fix_nginx_permissions() {
  [[ "$INSTALL_NGINX" -eq 1 && "$FIX_PERMISSIONS" -eq 1 ]] || return 0

  local install_owner_group="$NGINX_INSTALL_OWNER:$NGINX_INSTALL_GROUP"
  local runtime_owner_group="www-data:www-data"
  local log_dirs=()
  local log_dir
  local cache_roots=()
  local cache_root

  as_root test -d "$PREFIX" || die "Install prefix not found: $PREFIX"
  as_root test -f "$PREFIX/sbin/nginx" || die "nginx executable not found: $PREFIX/sbin/nginx"

  log "Creating nginx configuration and SSL directories"
  as_root mkdir -p \
    "$PREFIX/etc/ssl/certs" \
    "$PREFIX/etc/ssl/keys" \
    "$PREFIX/etc/include/sites" \
    "$PREFIX/etc/include/conf"

  log "Setting ownership and permissions under $PREFIX"
  as_root find "$PREFIX" -type d -exec chmod 750 {} +
  as_root find "$PREFIX" -type d -exec chown "$install_owner_group" {} +
  as_root find "$PREFIX" -type f -exec chmod 640 {} +
  as_root find "$PREFIX" -type f -exec chown "$install_owner_group" {} +

  log "Making nginx binary executable"
  as_root chmod 750 "$PREFIX/sbin/nginx"

  log "Restricting nginx private key permissions"
  as_root find "$PREFIX/etc/ssl/keys" -name '*.key' -type f -exec chmod 440 {} +

  # Access and error logs often live in the same directory; only process each
  # directory once to avoid duplicate log messages and duplicate find runs.
  for log_dir in "$(dirname "$HTTP_LOG_PATH")" "$(dirname "$ERROR_LOG_PATH")"; do
    [[ " ${log_dirs[*]} " == *" $log_dir "* ]] || log_dirs+=("$log_dir")
  done

  for log_dir in "${log_dirs[@]}"; do
    as_root test -d "$log_dir" || die "nginx log directory not found: $log_dir"

    log "Setting ownership and permissions under $log_dir"
    as_root chmod 750 "$log_dir"
    as_root chown "$install_owner_group" "$log_dir"
    as_root find "$log_dir" -type f -exec chmod 640 {} +
    as_root find "$log_dir" -type f -exec chown "$install_owner_group" {} +
  done

  # nginx workers run as www-data. Keep the cache hierarchy private to that
  # account so request bodies and upstream temporary files can be created
  # without exposing their contents to other local users.
  for cache_root in \
    "$(dirname "$CLIENT_BODY_TEMP_PATH")" \
    "$(dirname "$FASTCGI_TEMP_PATH")" \
    "$(dirname "$PROXY_TEMP_PATH")" \
    "$(dirname "$SCGI_TEMP_PATH")" \
    "$(dirname "$UWSGI_TEMP_PATH")"; do
    [[ " ${cache_roots[*]} " == *" $cache_root "* ]] || cache_roots+=("$cache_root")
  done

  as_root mkdir -p \
    "$CLIENT_BODY_TEMP_PATH" \
    "$FASTCGI_TEMP_PATH" \
    "$PROXY_TEMP_PATH" \
    "$SCGI_TEMP_PATH" \
    "$UWSGI_TEMP_PATH"

  for cache_root in "${cache_roots[@]}"; do
    log "Setting ownership and permissions under $cache_root"
    as_root find "$cache_root" -type d -exec chmod 700 {} +
    as_root find "$cache_root" -type f -exec chmod 600 {} +
    as_root find "$cache_root" -type d -exec chown "$runtime_owner_group" {} +
    as_root find "$cache_root" -type f -exec chown "$runtime_owner_group" {} +
  done
}

# Run the installed nginx directly when possible, otherwise use sudo. This is
# needed when an existing strict /opt/nginx tree prevents the build user from
# traversing the install prefix.
run_installed_nginx_logged() {
  local name="$1"
  shift

  if [[ -x "$PREFIX/sbin/nginx" ]]; then
    run_logged "$name" "$PREFIX/sbin/nginx" "$@"
  else
    run_logged "$name" as_root "$PREFIX/sbin/nginx" "$@"
  fi
}

# Record nginx build information and test the installed configuration.
verify_nginx() {
  [[ "$INSTALL_NGINX" -eq 1 ]] || return 0

  run_installed_nginx_logged nginx-version -V

  if [[ "$CONFIG_TEST" -eq 1 ]]; then
    run_installed_nginx_logged nginx-config-test -t
  fi
}

# Main build pipeline. The TLS wrapper supplies require_tls_cmds,
# fetch_tls_source, build_tls, and add_tls_configure_args.
main() {
  parse_args "$@"
  validate_options
  trap cleanup EXIT
  set_runtime_paths

  require_cmds git cmake make patch tee realpath
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
  fix_nginx_permissions

  log "Build completed successfully"
}
