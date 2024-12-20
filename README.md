# tlsv1.3-nginx

nginxcompile-openssl.sh is a script that compiles nginx 1.27.3 with openssl 3.2.1, brotli and dynamic tls records support. Updated to support http/3.

snippet of nginx config for openssl:


	# SSL
	ssl_dyn_rec_enable on;
	ssl_ecdh_curve X25519:secp521r1:secp384r1:prime256v1;

	# QUIC
	http3 on;
	quic_retry on;

	# modern configuration
	ssl_prefer_server_ciphers on;
	ssl_protocols TLSv1.2 TLSv1.3;
	ssl_ciphers ECDHE+AESGCM;
	ssl_conf_command Options PrioritizeChaCha;
	ssl_conf_command Options KTLS;

	# OCSP Stapling
	ssl_stapling on;
	ssl_stapling_verify on;
	resolver 127.0.0.1 [::1] valid=60s;
	resolver_timeout 2s;



nginxcompile-boringssl.sh is a script that compiles nginx 1.27.3 with the latest version of boringssl, brotli and dynamic tls records support. This adds support for http/3 and X25519MLKEM768.

snippet of nginx config for boringssl:


	# SSL
	ssl_dyn_rec_enable on;
	ssl_ecdh_curve X25519MLKEM768:X25519:P-521:P-384:P-256;

	# QUIC
	http3 on;
	quic_retry on;

	# modern configuration
	ssl_prefer_server_ciphers on;
	ssl_protocols TLSv1.2 TLSv1.3;
	ssl_ciphers [ECDHE-ECDSA-AES256-GCM-SHA384|ECDHE-RSA-AES256-GCM-SHA384]:[ECDHE-ECDSA-AES128-GCM-SHA256|ECDHE-RSA-AES128-GCM-SHA256];

