# tlsv1.3-nginx

**Before reading any further, I also have a docker [image](https://hub.docker.com/r/i81b4u/byo-nginx) you can use without having to compile things yourself.**

This is a new version of the scripts I use to compile nginx with either boringssl or openssl.
Because a lot of the logic used in my previous scripts was the same, I decided to do a rewrite
to merge most logic and add some features. Another big advantage is that root rights are not
needed anymore, except for installing and testing the build.<br/><br/>

## Requirements

The scripts are intended for a GNU/Linux system with Bash 4.3 or newer, GNU coreutils (`nproc` and
`realpath`), Git, a GCC-compatible C/C++ toolchain, Make, CMake, Ninja, Perl, `patch`, and
`tee`. Nginx also needs PCRE2 and zlib development files; zlib is enabled for the OpenSSL
build.

On Debian or Ubuntu, the following is a suitable starting point:

```
sudo apt-get install build-essential cmake ninja-build git patch perl libpcre2-dev zlib1g-dev
```

The selected BoringSSL snapshot requires CMake 3.22 or newer and a C++17-capable
compiler. Ubuntu 20.04 needs an updated CMake in addition to the fortify adjustment below.

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
`nginx -t`. With the defaults, files are owned by `root:www-data` and the policy is:

- Directories under the install prefix: `0750`.
- Regular files under the install prefix: `0640`.
- The nginx executable: `0750`.
- The private-key directory: `0700`, owned by `root:root`; all files inside: `0600`, owned by `root:root`.
- Access and error-log directories: `0750`; files within them: `0640`.
- The nginx cache root and its subdirectories: `0700`, owned by `www-data:www-data`.
- Regular files within the nginx cache hierarchy: `0600`, owned by `www-data:www-data`.

This prevents ordinary local users from traversing the install tree or reading its
configuration, certificates, keys, logs, and temporary/cache content. Workers can read
configuration and public content, but cannot modify the executable or configuration. The
root master loads private keys; workers do not need filesystem access to them. After this step, administrative nginx commands will normally
require `sudo`. Configuration verification uses root privileges to match the master process.

The policy is recursive: every file and directory placed below the install prefix is adjusted
on the next installation. Keep unrelated files outside that tree, or use
`--no-fix-permissions` if this ownership and mode policy does not fit the deployment. The
post-install ownership defaults can be changed with `NGINX_INSTALL_OWNER` and
`NGINX_INSTALL_GROUP`; these variables do not change nginx's configured runtime user and
group, which remain `www-data`. Override them only when the `www-data` account will still
retain the required access. Private keys remain root-only regardless of these overrides.
This policy assumes a root master and static certificate paths. Deployments that load
certificate keys in workers (for example, variable-based certificate paths) or run a
non-root master need a tailored policy and `--no-fix-permissions`.
Do not make the worker account the installation owner: that lets a compromised worker
replace the executable or change configuration subsequently loaded by root.

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
builds, set `NGX_BROTLI_REF` to a known-good commit hash. Merely checking out a detached
commit in a local mirror does not override the requested `master` ref.
<br/>
When building the first time the standard configtest can be omitted by issuing a command like:

```
./nginxcompile-openssl.sh --release --no-config-test
```
<br/><br/>
## Build behavior and review notes

Both backends enable `--with-control-api`, `--with-http_json_module`, and PCRE JIT.
The first two require a sufficiently recent nginx source tree; the default is 1.31.5.
See the [nginx configure reference](https://nginx.org/en/docs/configure.html).
Building control API support does not start a control listener; consult the
[command-line reference](https://nginx.org/en/docs/switches.html) before using `-l`.
Optional XSLT, image filtering, Perl, and legacy GeoIP modules are intentionally omitted:
they add dependencies and are not required for TLS or HTTP/3.

`NGINX_REF`, `OPENSSL_REF`, `BORINGSSL_REF`, and `NGX_BROTLI_REF` can be overridden
in the environment. Resolved Git commit IDs are saved in `source-refs.log` in the log
directory. Local mirrors are used as supplied and are not automatically fetched.

Each invocation creates a private `build.XXXXXXXX` directory beneath `--build-root`.
Existing builds are never erased at startup. Failed builds, `--keep-build`, and
`--no-install` retain that directory; successful installations remove only their own
build directory. A build-only invocation also records the compiled binary's `-V` output.
Relative paths resolve from the invoking directory. Paths containing whitespace or shell
metacharacters are rejected because nginx generates shell commands and Makefiles from them.
Use a dedicated install prefix: the permission policy recursively changes its contents.

For a build-only check:

```sh
./nginxcompile-openssl.sh --release --no-install
./nginxcompile-boringssl.sh --release --no-install
```

The existing `--debug` default is retained; use `--release` to omit nginx debug logging
support. GCC debug symbols (`-g`) remain available in both modes. The TLS backends are
statically linked, so TLS-library security updates require rebuilding nginx. The local
TLS-record and SHA-1 patches also need review whenever source versions change; patches
now fail without prompting if they no longer match, with context fuzz disabled.

Offline script regression checks can be run with `bash tests/build-safety.sh`.
See [REVIEW.md](REVIEW.md) for the review findings and validation scope.

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

    http2 on;
    http3 on;
    quic_retry on;

    # Provided by patches/nginx-dynamic-tls-records-1.29.2-plus.patch.
    ssl_buffer_size 16k;
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

    http2 on;
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
