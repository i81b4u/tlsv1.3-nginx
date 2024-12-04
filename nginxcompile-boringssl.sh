#!/bin/bash
# ---------------------------------------------------------------------------
# nginxcompile-boringssl.sh - Compile nginx with boringssl.

# By i81b4u.
  
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License at <http://www.gnu.org/licenses/> for
# more details.

# Usage: nginxcompile-boringssl.sh [-h|--help]

# Revision history:
# 2020-10-01 Initial release.
# 2023-03-19 Updated so recent versions of boringssl can be used
# ---------------------------------------------------------------------------

PROGNAME=${0##*/}
VERSION="1.0.3"
NGINXBUILDPATH="/usr/src"

clean_up() { # Perform pre-exit housekeeping
  return
}

error_exit() {
  echo -e "${PROGNAME}: ${1:-"Unknown Error"}" >&2
  clean_up
  exit 1
}

graceful_exit() {
  clean_up
  exit
}

signal_exit() { # Handle trapped signals
  case $1 in
    INT)
      error_exit "Program interrupted by user" ;;
    TERM)
      echo -e "\n$PROGNAME: Program terminated" >&2
      graceful_exit ;;
    *)
      error_exit "$PROGNAME: Terminating on unknown signal" ;;
  esac
}

usage() {
  echo -e "Usage: $PROGNAME [-h|--help]"
}

checkdeps_warn() {
  printf >&2 "$PROGNAME: $*\n"
}

checkdeps_iscmd() {
  command -v >&- "$@"
}

checkdeps() {
  local -i not_found
  for cmd; do
  checkdeps_iscmd "$cmd" || {
    checkdeps_warn $"$cmd not found"
    let not_found++
  }
  done
  (( not_found == 0 )) || return 1
}

help_message() {
  cat <<- _EOF_
  $PROGNAME ver. $VERSION
  Compile nginx with boringssl.

  $(usage)

  Options:
  -h, --help  Display this help message and exit.

  NOTE: You must be the superuser to run this script.

  Modify variable NGINXBUILDPATH in this script to specify different build path.

_EOF_
  return
}

# Trap signals
trap "signal_exit TERM" TERM HUP
trap "signal_exit INT"  INT

# Check for root UID
if [[ $(id -u) != 0 ]]; then
  error_exit "You must be the superuser to run this script."
fi

# Parse command-line
while [[ -n $1 ]]; do
  case $1 in
    -h | --help)
      help_message; graceful_exit ;;
    -* | --*)
      usage
      error_exit "Unknown option $1" ;;
    *)
      echo "Argument $1 to process..." ;;
  esac
  shift
done

# Main logic

# Check dependencies (https://stackoverflow.com/questions/20815433/how-can-i-check-in-a-bash-script-if-some-software-is-installed-or-not)
echo "$PROGNAME: Checking dependencies..."
checkdeps go git ninja wget patch sed make || error_exit "Install dependencies before using $PROGNAME"

# Create empty build environment
echo "$PROGNAME: Cleaning up previous build..."
if [ -d "$NGINXBUILDPATH" ]
then
	if [ -d "$NGINXBUILDPATH/nginx" ]
	then
		rm -rf $NGINXBUILDPATH/nginx || error_exit "Failed to delete directory $NGINXBUILDPATH/nginx"
	fi
	if [ -d "$NGINXBUILDPATH/boringssl" ]
	then
		rm -rf $NGINXBUILDPATH/boringssl || error_exit "Failed to delete directory $NGINXBUILDPATH/boringssl"
	fi
	if [ -d "$NGINXBUILDPATH/ngx_brotli" ]
	then
		rm -rf $NGINXBUILDPATH/ngx_brotli || error_exit "Failed to delete directory $NGINXBUILDPATH/ngx_brotli"
	fi
else
	mkdir $NGINXBUILDPATH || error_exit "Failed to create directory $NGINXBUILDPATH."
fi

# Get nginx, boringssl and brotli
echo "$PROGNAME: Cloning repositories..."
git clone https://github.com/nginx/nginx.git $NGINXBUILDPATH/nginx || error_exit "Failed to clone nginx."
git clone https://boringssl.googlesource.com/boringssl $NGINXBUILDPATH/boringssl || error_exit "Failed to clone boringssl."
git clone --recurse-submodules -j8 https://github.com/google/ngx_brotli $NGINXBUILDPATH/ngx_brotli || error_exit "Failed to clone brotli."

if [ -d "$NGINXBUILDPATH/ngx_brotli" ]
then
  cd $NGINXBUILDPATH/ngx_brotli/deps/brotli || error_exit "Failed to make $NGINXBUILDPATH/ngx_brotly/deps/brotli current directory."
  mkdir out || error_exit "Failed to create directory out in $NGINXBUILDPATH/ngx_brotly/deps/brotli."
  cd $NGINXBUILDPATH/ngx_brotli/deps/brotli/out || error_exit "Failed to make $NGINXBUILDPATH/ngx_brotly/deps/brotli/out current directory."
  cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_C_FLAGS="-Ofast -m64 -march=native -mtune=native -flto -funroll-loops -ffunction-sections -fdata-sections -Wl,--gc-sections" -DCMAKE_CXX_FLAGS="-Ofast -m64 -march=native -mtune=native -flto -funroll-loops -ffunction-sections -fdata-sections -Wl,--gc-sections" -DCMAKE_INSTALL_PREFIX=./installed .. || error_exit "Failed to make ngx_brotli modules."
  cmake --build . --config Release --target brotlienc || error_exit "Failed to build ngx_brotli modules."
else
  error_exit "Directory $NGINXBUILDPATH/nginx_brotli does not exist."
fi

if [ -d "$NGINXBUILDPATH/nginx" ]
then
  cd $NGINXBUILDPATH/nginx || error_exit "Failed to make $NGINXBUILDPATH/nginx current directory."
  git checkout release-1.27.3 || error_exit "Failed to checkout nginx release."
else
  error_exit "Directory $NGINXBUILDPATH/nginx does not exist."
fi

# Build boringssl
echo "$PROGNAME: Building boringssl..."
mkdir -p $NGINXBUILDPATH/boringssl/build || error_exit "Failed to create directory $NGINXBUILDPATH/boringssl/build."
cd $NGINXBUILDPATH/boringssl/build || error_exit "Failed to make $NGINXBUILDPATH/boringssl/build current directory."
cmake -GNinja .. || error_exit "Failed to cmake boringssl."
ninja || error_exit "Faied to compile boringssl."

# Apply http_tls_dyn_size patch for nginx >= 1.25.1
echo "$PROGNAME: Patching nginx..."
if [ -d "$NGINXBUILDPATH/nginx" ]
then
  cd $NGINXBUILDPATH/nginx || error_exit "Failed to make $NGINXBUILDPATH/nginx current directory."
  wget https://raw.githubusercontent.com/nginx-modules/ngx_http_tls_dyn_size/master/nginx__dynamic_tls_records_1.27.2%2B.patch || error_exit "Failed to retrieve dynamic tls records patch."
  patch -p1 < nginx__dynamic_tls_records_1.27.2+.patch || error_exit "Could not apply dynamic tls records patch."
else
  error_exit "Directory $NGINXBUILDPATH/nginx does not exist."
fi

# Configure-options
echo "$PROGNAME: Configure build options..."
if [ -d "$NGINXBUILDPATH/nginx" ]
then
	cd $NGINXBUILDPATH/nginx || error_exit "Failed to make $NGINXBUILDPATH/nginx current directory."
	./auto/configure --prefix=/opt/nginx --conf-path=/opt/nginx/etc/nginx.conf --sbin-path=/opt/nginx/sbin/nginx --http-client-body-temp-path=/var/cache/nginx/client_temp --lock-path=/var/run/nginx.lock --pid-path=/var/run/nginx.pid --http-log-path=/var/log/nginx/access.log --error-log-path=/var/log/nginx/error.log --modules-path=/opt/nginx/lib/modules --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp --http-proxy-temp-path=/var/cache/nginx/proxy_temp --http-scgi-temp-path=/var/cache/nginx/scgi_temp --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp --user=www-data --group=www-data --with-cc=c++ --with-compat --with-debug --add-module=$NGINXBUILDPATH/ngx_brotli --with-file-aio --with-threads --with-http_addition_module --with-http_auth_request_module --with-http_dav_module --with-http_flv_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_mp4_module --with-http_random_index_module --with-http_realip_module --with-http_secure_link_module --with-http_slice_module --with-http_ssl_module --with-http_stub_status_module --with-http_sub_module --with-http_v2_module --with-http_v3_module --with-mail --with-mail_ssl_module --with-stream --with-stream_realip_module --with-stream_ssl_module --with-stream_ssl_preread_module --with-cc-opt="-g -O2 -flto=auto -ffat-lto-objects -flto=auto -ffat-lto-objects -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC -I$NGINXBUILDPATH/boringssl/include -x c" --with-ld-opt="-Wl,-Bsymbolic-functions -flto=auto -ffat-lto-objects -flto=auto -Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie -L$NGINXBUILDPATH/boringssl/build/ssl -L$NGINXBUILDPATH/boringssl/build/crypto"
else
        error_exit "Directory $NGINXBUILDPATH/nginx does not exist."
fi

# Modify nginx http server string (nginx -> i81b4u)
echo "$PROGNAME: Modify nginx http server string..."
sed -i -e "s/static u_char ngx_http_server_string\[\] = \"Server: nginx\" CRLF\;/static u_char ngx_http_server_string\[\] = \"Server: i81b4u\" CRLF\;/g" $NGINXBUILDPATH/nginx/src/http/ngx_http_header_filter_module.c || error_exit "Failed to modify http nginx server string."
# Modify nginx http/2 server string (https://scotthelme.co.uk/customising-server-header-over-http-2-in-nginx/)
sed -i -e "s/static const u_char nginx\[5\] \= \"\\\x84\\\xaa\\\x63\\\x55\\\xe7\"\;/static const u_char nginx\[6\] \= \"\\\x85\\\x33\\\xc1\\\x8d\\\xab\\\x7f\"\;/g" $NGINXBUILDPATH/nginx/src/http/v2/ngx_http_v2_filter_module.c || error_exit "Failed to modify http/2 nginx server string."
# Modify nginx http/3 server string
sed -i -e "s/\"nginx\"/\"i81b4u\"/g" $NGINXBUILDPATH/nginx/src/http/v3/ngx_http_v3_filter_module.c || error_exit "Failed to modify http/3 nginx server string."

# Make and install
echo "$PROGNAME: Make and install nginx..."
if [ -d "$NGINXBUILDPATH/nginx" ]
then
        cd $NGINXBUILDPATH/nginx || error_exit "Failed to make $NGINXBUILDPATH/nginx current directory."
	make -j $(nproc) || error_exit "Error compiling nginx."
	make install || error_exit "Error installing nginx."
else
        error_exit "Directory $NGINXBUILDPATH/nginx does not exist."
fi

echo "$PROGNAME: All done!"

graceful_exit
