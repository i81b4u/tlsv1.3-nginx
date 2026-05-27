# tlsv1.3-nginx

snippet of nginx config for openssl:


	# QUIC
	http3 on;
	quic_retry on;
    quic_gso on;

	# SSL
	ssl_prefer_server_ciphers on;
	ssl_protocols TLSv1.2 TLSv1.3;
	ssl_ciphers ECDHE+AESGCM;
	ssl_conf_command Options PrioritizeChaCha;
	ssl_conf_command Options KTLS;
	ssl_session_timeout 1d;
	ssl_session_cache shared:SSL:10m;
	ssl_session_tickets off;
	ssl_dyn_rec_enable on;
	ssl_certificate_compression on;
	ssl_ecdh_curve MLKEM1024:SecP256r1MLKEM768:X25519MLKEM768:SecP384r1MLKEM1024:curveSM2MLKEM768:X25519:P-384:P-256;
	ssl_conf_command SignatureAlgorithms ecdsa_secp384r1_sha384:ecdsa_secp256r1_sha256:ed25519:ed448:rsa_pss_rsae_sha384:rsa_pss_rsae_sha256:rsa_pss_pss_sha384:rsa_pss_pss_sha256:rsa_pkcs1_sha384:rsa_pkcs1_sha256:mldsa65:mldsa87;
	ssl_buffer_size 4k;


snippet of nginx config for boringssl:


	# QUIC
	http3 on;
	quic_retry on;

	# SSL
	ssl_prefer_server_ciphers on;
	ssl_protocols TLSv1.2 TLSv1.3;
	ssl_ciphers [ECDHE-ECDSA-AES256-GCM-SHA384|ECDHE-RSA-AES256-GCM-SHA384]:[ECDHE-ECDSA-AES128-GCM-SHA256|ECDHE-RSA-AES128-GCM-SHA256];
	ssl_dyn_rec_enable on;
	ssl_ecdh_curve MLKEM1024:X25519MLKEM768:X25519:P-384:P-256;

