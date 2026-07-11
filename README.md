# tlsv1.3-nginx

This is a new version of the scripts I use to compile nginx with either boringssl or openssl.
Because a lot of the logic used in my previous scripts was the same, I decided to do a rewrite
to merge most logic and add some features. Another big advantage is that root rights are not
needed anymore, except for installing and testing the build.<br/><br/>

## Requirements

The scripts are intended for a GNU/Linux system with Bash, GNU coreutils (`nproc` and
`realpath`), Git, a GCC-compatible C/C++ toolchain, Make, CMake, Ninja, Perl, `patch`, and
`tee`. Nginx also needs PCRE2 and zlib development files; zlib is enabled for the OpenSSL
build.

On Debian or Ubuntu, the following is a suitable starting point:

```
sudo apt-get install build-essential cmake ninja-build git patch perl libpcre2-dev zlib1g-dev
```

The BoringSSL build defaults to `_FORTIFY_SOURCE=3`. Ubuntu 20.04's toolchain does not
support that level, so use `_FORTIFY_SOURCE=2` instead:

```
FORTIFY_SOURCE=2 ./nginxcompile-boringssl.sh --release
```

Use the equivalent development packages for other distributions. The scripts clone source
repositories over the network unless local source mirrors are supplied, so the first build
also needs network access and enough free disk space for multiple source and build trees.

By default, installation uses `/opt/nginx` and runtime files use `/var/run`, `/var/log`, and
`/var/cache`; these locations normally require `sudo`. The resulting nginx is configured to
run as the `www-data` user and group, which must exist on the system. For test or non-system
installs, use a writable `--prefix` together with `--runtime-root`.

## Post-install permission policy

Unless `--no-fix-permissions` is used, the script applies a deliberately restrictive local
permission policy after it has successfully run `nginx -V` and, unless disabled,
`nginx -t`. With the defaults, files are owned by `www-data:root` and the policy is:

- Directories under the install prefix: `0750`.
- Regular files under the install prefix: `0640`.
- The nginx executable: `0750`.
- Private keys matching `etc/ssl/keys/*.key`: `0440`.
- Access and error-log directories: `0750`; files within them: `0640`.
- The nginx cache root and its subdirectories: `0700`, owned by `www-data:www-data`.
- Regular files within the nginx cache hierarchy: `0600`, owned by `www-data:www-data`.

This prevents ordinary local users from traversing the install tree or reading its
configuration, certificates, keys, logs, and temporary/cache content, while allowing nginx to
access files as their owner. After this step, administrative nginx commands will normally
require `sudo`, which is why verification happens before the policy is applied.

The policy is recursive: every file and directory placed below the install prefix is adjusted
on the next installation. Keep unrelated files outside that tree, or use
`--no-fix-permissions` if this ownership and mode policy does not fit the deployment. The
post-install ownership defaults can be changed with `NGINX_INSTALL_OWNER` and
`NGINX_INSTALL_GROUP`; these variables do not change nginx's configured runtime user and
group, which remain `www-data`. Override them only when the `www-data` account will still
retain the required access.

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

`ngx_brotli` is intentionally built from its `master` branch because its available release
tag lacks fixes needed by this build. As a result, builds may change over time; for repeatable
builds, use a local clone checked out at a known-good commit.
<br/>
When building the first time the standard configtest can be omitted by issuing a command like:

```
./nginxcompile-openssl.sh --release --no-config-test
```
<br/><br/>
## Configuration examples

The examples below are starting points for a `server` block. Replace the hostname and
certificate paths, allow UDP port 443 through the firewall, and run `nginx -t` after each
change. The `listen ... quic` line is what enables HTTP/3 traffic; `http3 on` alone is not
enough.

`ssl_dyn_rec_enable` is provided by the local dynamic-TLS-records patch in this repository.
It affects TLS carried over TCP, not QUIC. Do not use it with an unpatched nginx build.
The PQC/hybrid group names and certificate-compression support are specific to the selected
TLS library version, so introduce those directives one at a time and retain only the values
accepted by your build.

### OpenSSL

```
server {
    listen 443 ssl;
    listen 443 quic reuseport;
    server_name example.com;

    ssl_certificate     /opt/nginx/etc/ssl/certs/example.com.pem;
    ssl_certificate_key /opt/nginx/etc/ssl/keys/example.com.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE+AESGCM;
    ssl_prefer_server_ciphers on;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    http3 on;
    quic_retry on;

    # Provided by patches/nginx-dynamic-tls-records-1.29.2-plus.patch.
    ssl_buffer_size 4k;
    ssl_dyn_rec_enable on;

    # Optional OpenSSL and platform-specific tuning. Verify each with nginx -t.
    ssl_conf_command Options PrioritizeChaCha;
    ssl_conf_command Options KTLS;
    ssl_certificate_compression on;

    # Optional PQC/hybrid groups; names depend on the bundled OpenSSL version.
    ssl_ecdh_curve MLKEM1024:SecP256r1MLKEM768:X25519MLKEM768:SecP384r1MLKEM1024:curveSM2MLKEM768:X25519:P-384:P-256;
    ssl_conf_command SignatureAlgorithms ecdsa_secp384r1_sha384:ecdsa_secp256r1_sha256:ed25519:ed448:rsa_pss_rsae_sha384:rsa_pss_rsae_sha256:rsa_pss_pss_sha384:rsa_pss_pss_sha256:rsa_pkcs1_sha384:rsa_pkcs1_sha256:mldsa65:mldsa87;
}
```

### BoringSSL

```
server {
    listen 443 ssl;
    listen 443 quic reuseport;
    server_name example.com;

    ssl_certificate     /opt/nginx/etc/ssl/certs/example.com.pem;
    ssl_certificate_key /opt/nginx/etc/ssl/keys/example.com.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers [ECDHE-ECDSA-AES256-GCM-SHA384|ECDHE-RSA-AES256-GCM-SHA384]:[ECDHE-ECDSA-AES128-GCM-SHA256|ECDHE-RSA-AES128-GCM-SHA256];
    ssl_prefer_server_ciphers on;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    http3 on;
    quic_retry on;

    # Provided by patches/nginx-dynamic-tls-records-1.29.2-plus.patch.
    ssl_dyn_rec_enable on;

    # Optional PQC/hybrid groups; names depend on the bundled BoringSSL snapshot.
    ssl_ecdh_curve MLKEM1024:X25519MLKEM768:X25519:P-384:P-256;
}
```

`ssl_ciphers` applies to TLS 1.2 and earlier; TLS 1.3 cipher-suite selection is handled by
the TLS library. `quic_gso on` is intentionally not enabled above: it is an optional Linux
kernel/network-interface optimization and should be enabled only after it has been tested in
the target environment.
<br/>

**This repository was developed with assistance from OpenAI Codex for scripting, review, and troubleshooting.**
