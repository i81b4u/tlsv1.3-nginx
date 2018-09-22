# tlsv1.3-nginx

cd /usr/src && git clone https://github.com/nginx/nginx.git && git clone https://github.com/openssl/openssl.git && git clone https://github.com/nginx-modules/ngx_brotli.git && cd /usr/src/ngx_brotli && git submodule update --init

cd /usr/src/nginx && wget https://raw.githubusercontent.com/nginx-modules/ngx_http_tls_dyn_size/master/nginx__dynamic_tls_records_1.13.0%2B.patch && patch -p1 < nginx__dynamic_tls_records_1.13.0+.patch

or when using nginx master after sep 21, 2018

cd /usr/src/nginx && wget https://raw.githubusercontent.com/i81b4u/tlsv1.3-nginx/master/nginx__dynamic_tls_records_1.15.3%2B.patch && patch -p1 < nginx__dynamic_tls_records_1.15.3+.patch

cd /usr/src/nginx && ./auto/configure --with-openssl=/usr/src/openssl --with-openssl-opt='enable-tls1_3 enable-ec_nistp_64_gcc_128' --prefix=/opt/nginx --conf-path=/opt/nginx/etc/nginx.conf --sbin-path=/opt/nginx/sbin/nginx --http-client-body-temp-path=/var/tmp/client_body_temp --pid-path=/var/run/nginx.pid --add-module=/usr/src/ngx_brotli --error-log-path=/var/log/nginx/error.log --user=www-data --group=www-data --modules-path=/opt/nginx/libexec --http-log-path=/var/log/nginx/access.log --with-http_ssl_module --with-file-aio --with-http_gzip_static_module --with-pcre --with-http_v2_module --with-threads --without-http-cache --without-http_autoindex_module --without-http_browser_module --without-http_fastcgi_module --without-http_geo_module --without-http_gzip_module --without-http_limit_conn_module --without-http_map_module --without-http_memcached_module --without-poll_module --without-http_proxy_module --without-http_referer_module --without-http_scgi_module --without-select_module --without-http_split_clients_module --without-http_ssi_module --without-http_upstream_ip_hash_module --without-http_upstream_least_conn_module --without-http_upstream_keepalive_module --without-http_userid_module --without-http_uwsgi_module --without-mail_imap_module --without-mail_pop3_module --without-mail_smtp_module --with-cc-opt='-O2 -march=native -pipe -flto -funsafe-math-optimizations -fstack-protector-strong --param=ssp-buffer-size=4 -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2'

cd /usr/src/nginx && make -j $(nproc) && make install
