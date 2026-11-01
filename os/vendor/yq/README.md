# Bundled YAML parser

Unmodified Mike Farah yq **v4.54.1** release binaries for macOS and Linux,
ARM64 and x86-64. `os/yq.sh` selects the matching executable. No system yq,
Python, Ruby, or install-time download is required. Unsupported architectures
fail explicitly. This does not expand the automated VM matrix beyond ARM64.

`UPSTREAM.json` records download URLs and SHA-256 hashes, verified against the
upstream GitHub release asset digests before vendoring. `LICENSE` is upstream's
MIT license. The four binaries total approximately 55 MB before Git compression.

To update, choose an explicit release, download these four named assets from
that release, verify every SHA-256 against its published asset digest, preserve
executable modes, update the provenance and license, and run the macOS and
Debian VM suites. Do not fetch `latest` at install time.

Upstream: https://github.com/mikefarah/yq/releases/tag/v4.54.1
