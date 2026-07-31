# Maintaining this fork

This repository is upstream [mkj/dropbear](https://github.com/mkj/dropbear) plus a small set
of ClearML-only files. The release assets are static builds of that tree, for use inside
containers.

## What this fork adds

| File | Change |
|---|---|
| `src/svr-auth.c` | `DROPBEAR_CLEARML_FIXED_PASSWORD=<pw>` lets any username log in with that password, as the user the server runs as |
| `src/svr-chansession.c` | `SFTPSERVER_PATH` overrides the compiled-in sftp-server path |
| `Dockerfile`, `build.sh` | static musl build of `dropbearmulti` |
| `openssh_sftp_server_build_static.Dockerfile`, `build_openssh_sftp_server.sh` | static `sftp-server` from openssh-portable |
| `test_fixed_password_login.sh` | starts a server and drops you into an interactive SSH session |
| `.github/scripts/`, `.github/workflows/clearml-*.yml` | build, test and sync automation |

`.github/scripts/check_patch.sh` holds the authoritative list of these files and CI enforces
it, so **a new fork-only file has to be added there as well**.

## Syncing a new upstream release

This tree shares no git history with upstream, so a sync is not a `git merge`. It applies
only upstream's delta between two releases, as a per-file 3-way merge:

```bash
git remote add upstream https://github.com/mkj/dropbear.git
git fetch upstream --no-tags 'refs/tags/*:refs/tags/upstream/*'
git diff upstream/DROPBEAR_<old> upstream/DROPBEAR_<new> | git apply --3way --whitespace=nowarn
```

The fork's own changes survive automatically; only a genuine overlap produces conflict
markers, which in practice can only happen in the two patched source files. Fetching
upstream's tags into the `upstream/` namespace keeps them from colliding with this repo's
own `DROPBEAR_*` release tags, which name the upstream release they were synced from.

Which release the tree is based on comes from `DROPBEAR_VERSION` in `src/sysoptions.h`,
which upstream bumps as part of every release.

## Automation

- **`clearml-sync.yml`** — checks nightly for a newer upstream release, applies the delta as
  above and opens a PR. On a conflict it opens an issue instead and changes nothing.
- **`clearml-ci.yml`** — on every PR and push to `master`: checks the tree is the upstream
  release it claims to be plus the files listed above, then builds and tests both
  architectures on native runners.
- **`clearml-release.yml`** — when a sync PR is merged: rebuilds and re-tests both
  architectures, then tags `DROPBEAR_<version>` and publishes the release assets.

Building and testing locally, exactly as CI does:

```bash
.github/scripts/build_and_test.sh linux/amd64 linux/arm64
```
