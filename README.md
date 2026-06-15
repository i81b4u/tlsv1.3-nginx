# tlsv1.3-nginx

This is a new version of the scripts I use to compile nginx with either boringssl or openssl.
Because a lot of the logic used in my previous scripts was the same, I decided to do a rewrite
to merge most logic and add some features. Another big advantage is that root rights are not
needed anymore, except for installing and testing the build.<br/><br/>
To clone the repository, just type:
```
git clone https://github.com/i81b4u/tlsv1.3-nginx.git
```
<br/>
After that, enter the directory and execute either

```
./nginxcompile-boringssl.sh --help
```
or
```
./nginxcompile-openssl.sh --help
```

to see what the options are.<br/><br/>
To further facilitate testing, "pre-cloning" used repositories is supported to skip having
to download them every time. This is done by entering the same directory the scripts
live in and typing something like:

```
git clone https://github.com/nginx/nginx.git
git clone https://github.com/google/boringssl.git
git clone --recurse-submodules https://github.com/google/ngx_brotli.git
git clone https://github.com/openssl/openssl.git
```
The scripts select source versions by Git ref names in the wrapper scripts. These refs can
be tags, branches, or commit hashes. When local pre-cloned repositories are used, make sure
they have the selected tags or branches fetched before building.
<br/>
When building the first time the standard configtest can be omitted by issuing a command like:

```
./nginxcompile-openssl.sh --release --no-config-test
```
<br/><br/>
By building like this, you can enable PQC-related features provided by boringssl or openssl.
Examples on how to configure are listed below:

**Snippet of nginx config for openssl**


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


**Snippet of nginx config for boringssl**


	# QUIC
	http3 on;
	quic_retry on;

	# SSL
	ssl_prefer_server_ciphers on;
	ssl_protocols TLSv1.2 TLSv1.3;
	ssl_ciphers [ECDHE-ECDSA-AES256-GCM-SHA384|ECDHE-RSA-AES256-GCM-SHA384]:[ECDHE-ECDSA-AES128-GCM-SHA256|ECDHE-RSA-AES128-GCM-SHA256];
	ssl_dyn_rec_enable on;
	ssl_ecdh_curve MLKEM1024:X25519MLKEM768:X25519:P-384:P-256;
<br/>

**This repository was developed with assistance from OpenAI Codex for scripting, review, and troubleshooting.**
