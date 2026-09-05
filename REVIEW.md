# Build-script review — 2026-09-05

The two selected TLS backends successfully compile nginx 1.31.5, including all
three repository patches, Brotli, HTTP/2, HTTP/3, the control API, and JSON support.

## Findings addressed

| Finding | Change |
| --- | --- |
| Missing new nginx features | Added `--with-control-api` and `--with-http_json_module` to the shared configure arguments. |
| Worker account owned executable and configuration | Default installation ownership is now `root:www-data`; private keys are root-only, including keys without a `.key` suffix. Runtime caches remain worker-owned. |
| Startup recursively deleted a supplied build directory | Allocate a private directory with `mktemp`; cleanup only removes that invocation's directory. |
| Successful `--no-install` removed the only binary | Build-only runs now retain the build tree and verify the binary with `-V`. |
| Relative paths changed meaning after `cd` | Normalize paths before building and reject characters unsafe in generated Makefiles/shell commands. Reject broad install prefixes and overlapping protected paths. |
| Executable access did not imply permission to run `nginx -t` | Installed configuration testing uses root to match the expected master process. |
| A writable parent did not imply an existing prefix was writable | Installation checks the existing prefix when present. |
| Reproducibility guidance did not actually pin `master` | Allow environment overrides for all refs and document explicit commit pinning. Record source commits and submodule revisions in logs. |
| Patch commands could prompt or accept mismatched context | Apply patches in batch/forward mode with context fuzz disabled. |
| Repeated cache/log permission passes with newline IFS | Deduplicate paths using associative arrays. |
| Missing PCRE JIT and duplicate linker flag | Enable PCRE JIT and remove the duplicate BoringSSL LTO flag. |
| Documentation gaps | Document BoringSSL's CMake 3.22 requirement, ownership changes, retention behavior, and explicit control-listener activation. Enable HTTP/2 in the examples and use a 16 KiB buffer so dynamic TLS records can grow beyond the intermediate size. |

## Validation

- Full release builds completed for OpenSSL 4.0.2 and BoringSSL 0.20260813.0.
- All local patches applied with zero context fuzz.
- Both binaries report nginx 1.31.5 and the new configure options via `-V`.
- Both README server examples passed `nginx -t`, including their optional TLS settings,
  using a generated RSA test certificate and port 18443. The test also exercised the
  JSON module's `json_max_depth` directive.
- ELF inspection confirmed PIE, GNU RELRO, and immediate symbol binding for both binaries.
- Bash syntax, ShellCheck, whitespace checks, and six offline regression cases passed.
- No production installation, permission changes, service restart, or live traffic test
  was performed. Configuration parsing does not establish client interoperability or
  measure HTTP/3 performance. The cryptographic patches were checked for build compatibility;
  this was not an independent cryptographic audit.

Source commits used for the full builds:

| Component | Commit |
| --- | --- |
| nginx | `231a60ee3e90a43b829b9ca0a3013a8359b98d7e` |
| OpenSSL | `f089acdf4bc7ba94a79f4bf6eb7362c3e7d14aa9` |
| BoringSSL | `7c1efd8d6ffb36a57feba44e8c73cf674801f3cb` |
| ngx_brotli | `a71f9312c2deb28875acc7bacfdd5695a111aa53` |

## Choices retained

- `ngx_brotli` defaults to moving `master`, as the repository intends. Pin its commit
  through `NGX_BROTLI_REF` when reproducibility is required.
- Existing mail, stream, DAV, FLV, and MP4 modules remain available. Completeness does
  not require enabling every optional module: XSLT, image filtering, Perl, and legacy
  GeoIP introduce additional dependencies without serving the stated TLS build purpose.
- Debug support remains the existing default; production builds can use `--release`.
- TLS 1.2 and TLS 1.3 remain enabled in examples. Optional PQC lists and signature
  restrictions are deployment policy, not universally suitable defaults.
- Local branding and cryptographic patches remain in place. Branding is cosmetic;
  the SHA-1 patch changes handshake signature policy, not a universal ban on every
  use of SHA-1 in the library. Reassess these patches on each dependency update.
- TLS libraries are statically linked; updating the system TLS package alone does
  not update these nginx binaries.

## Upstream references

Checked against the selected source trees and these upstream documents:

- [nginx build options](https://nginx.org/en/docs/configure.html)
- [nginx control-listener command-line option](https://nginx.org/en/docs/switches.html)
- [nginx QUIC build guidance](https://nginx.org/en/docs/quic.html)
- [nginx security advisories](https://nginx.org/en/security_advisories.html): the selected
  1.31.5 release is outside the affected ranges listed at review time.
- [OpenSSL releases](https://openssl-library.org/source/)
- [BoringSSL snapshot build requirements](https://github.com/google/boringssl/blob/0.20260813.0/BUILDING.md)
