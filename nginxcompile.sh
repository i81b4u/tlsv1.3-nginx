#!/bin/bash
# ---------------------------------------------------------------------------
# nginxcompile.sh - Compile nginx 1.15.9 with openssl 1.1.1b, brotli and dynamic tls records support.

# By i81b4u

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License at <http://www.gnu.org/licenses/> for
# more details.

# Usage: nginxcompile.sh [-h|--help]

# Revision history:
# 2019-02-01 Created by new_script.sh ver. 3.3
# ---------------------------------------------------------------------------

PROGNAME=${0##*/}
VERSION="0.9"
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

help_message() {
  cat <<- _EOF_
  $PROGNAME ver. $VERSION
  Compile nginx 1.15.9 with openssl 1.1.1b, brotli and dynamic tls records support.

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

# Create empty build environment
echo "Cleaning up previous build..."
if [ -d "$NGINXBUILDPATH" ]
then
        if [ -d "$NGINXBUILDPATH/nginx" ]
        then
                rm -rf $NGINXBUILDPATH/nginx || error_exit "Failed to delete directory $NGINXBUILDPATH/nginx"
        fi
        if [ -d "$NGINXBUILDPATH/openssl" ]
        then
                rm -rf $NGINXBUILDPATH/openssl || error_exit "Failed to delete directory $NGINXBUILDPATH/openssl"
        fi
        if [ -d "$NGINXBUILDPATH/ngx_brotli" ]
        then
                rm -rf $NGINXBUILDPATH/ngx_brotli || error_exit "Failed to delete directory $NGINXBUILDPATH/ngx_brotli"
        fi
else
        mkdir $NGINXBUILDPATH || error_exit "Failed to create directory $NGINXBUILDPATH."
fi

# Get nginx, openssl and brotli
echo "Cloning repositories..."
git clone https://github.com/nginx/nginx.git $NGINXBUILDPATH/nginx || error_exit "Failed to clone nginx."
git clone https://github.com/openssl/openssl.git $NGINXBUILDPATH/openssl || error_exit "Failed to clone openssl."
git clone https://github.com/nginx-modules/ngx_brotli.git $NGINXBUILDPATH/ngx_brotli || error_exit "Failed to clone brotli."

if [ -d "$NGINXBUILDPATH/ngx_brotli" ]
then
        cd $NGINXBUILDPATH/ngx_brotli || error_exit "Failed to make $NGINXBUILDPATH/ngx_brotly current directory."
        git submodule update --init || error_exit "Failed to initialize ngx_brotli submodule."
else
        error_exit "Directory $NGINXBUILDPATH/nginx_brotli does not exist."
fi

if [ -d "$NGINXBUILDPATH/nginx" ]
then
        cd $NGINXBUILDPATH/nginx || error_exit "Failed to make $NGINXBUILDPATH/nginx current directory."
        git checkout release-1.15.9 || error_exit "Failed to checkout nginx release."
else
        error_exit "Directory $NGINXBUILDPATH/nginx does not exist."
fi

if [ -d "$NGINXBUILDPATH/openssl" ]
then
        cd $NGINXBUILDPATH/openssl || error_exit "Failed to make $NGINXBUILDPATH/openssl current directory."
        git checkout OpenSSL_1_1_1b || error_exit "Failed to checkout openssl release."
else
        error_exit "Directory $NGINXBUILDPATH/openssl does not exist."
fi

# Apply http_tls_dyn_size patch for nginx >= 1.15.5
echo "Patching nginx..."
if [ -d "$NGINXBUILDPATH/nginx" ]
then
        cd $NGINXBUILDPATH/nginx || error_exit "Failed to make $NGINXBUILDPATH/nginx current directory."
        wget https://raw.githubusercontent.com/nginx-modules/ngx_http_tls_dyn_size/master/nginx__dynamic_tls_records_1.15.5%2B.patch || error_exit "Failed to retrieve dynamic tls records patch."
        patch -p1 < nginx__dynamic_tls_records_1.15.5+.patch || error_exit "Could not apply dynamic tls records patch."
else
        error_exit "Directory $NGINXBUILDPATH/nginx does not exist."
fi

# Configure-options like ubuntu
echo "Configure build options..."
if [ -d "$NGINXBUILDPATH/nginx" ]
then
        cd $NGINXBUILDPATH/nginx || error_exit "Failed to make $NGINXBUILDPATH/nginx current directory."
        ./auto/configure --with-cc-opt="-g0 -O2 -fstack-protector-strong -Wformat -Werror=format-security -fPIC -Wdate-time -march=native -pipe -flto -funsafe-math-optimizations --param=ssp-buffer-size=4 -D_FORTIFY_SOURCE=2" --with-ld-opt="-Wl,-Bsymbolic-functions -Wl,-z,relro -Wl,-z,now -fPIC" --prefix=/opt/nginx --conf-path=/opt/nginx/etc/nginx.conf --sbin-path=/opt/nginx/sbin/nginx --http-client-body-temp-path=/var/lib/nginx/body --pid-path=/var/run/nginx.pid --lock-path=/var/lock/nginx.lock --pid-path=/run/nginx.pid --http-log-path=/var/log/nginx/access.log --error-log-path=/var/log/nginx/error.log --modules-path=/opt/nginx/lib/modules --http-fastcgi-temp-path=/var/lib/nginx/fastcgi --http-proxy-temp-path=/var/lib/nginx/proxy --http-scgi-temp-path=/var/lib/nginx/scgi --http-uwsgi-temp-path=/var/lib/nginx/uwsgi --user=www-data --group=www-data --with-openssl=$NGINXBUILDPATH/openssl --with-openssl-opt="enable-tls1_3 enable-ec_nistp_64_gcc_128" --add-module=$NGINXBUILDPATH/ngx_brotli --with-pcre-jit --with-http_ssl_module --with-http_stub_status_module --with-http_realip_module --with-http_auth_request_module --with-http_v2_module --with-http_dav_module --with-http_slice_module --with-threads --with-http_addition_module --with-http_geoip_module=dynamic --with-http_gunzip_module --with-http_gzip_static_module --with-http_image_filter_module=dynamic --with-http_sub_module --with-http_xslt_module=dynamic --with-stream=dynamic --with-stream_ssl_module --with-mail=dynamic --with-mail_ssl_module || error_exit "Failed to configure nginx for compilation."
else
        error_exit "Directory $NGINXBUILDPATH/nginx does not exist."
fi

# Make and install
echo "Make and install nginx..."
if [ -d "$NGINXBUILDPATH/nginx" ]
then
        cd $NGINXBUILDPATH/nginx || error_exit "Failed to make $NGINXBUILDPATH/nginx current directory."
        make -j $(nproc) || error_exit "Error compiling nginx."
        make install || error_exit "Error installing nginx."
else
        error_exit "Directory $NGINXBUILDPATH/nginx does not exist."
fi

echo "All done!"

graceful_exit