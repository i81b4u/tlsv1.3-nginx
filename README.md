# tlsv1.3-nginx

To compile the latest version of nginx, openssl (with TLSv1.3 support) and brotli, execute the commands in compile.
This creates a "light" version of nginx in /opt/nginx.

When in need of a drop-in replacement for nginx (with all common nginx features enabled), please use the configure-options in configure-ubuntu. It's called configure-ubuntu because all configuration options (except debug) are like the options used to create the ubuntu-package.

Please make sure all dependencies (like -dev packages) are installed.
