# Releasing

This repository is public and the source is not. The workflows here check out a tag of the private `bitbytelabio/kitsune-browser`, build it, and publish only the finished files. The steps that start a release, and the scripts the workflows call, are in that repository's `tools/release/`.

## What runs where

| Workflow | Started by | Does |
| --- | --- | --- |
| `release.yml` | `tools/release/cut.sh` in kitsune-browser | Builds the app, the server image and the server binaries from a `vX.Y.Z` tag into a draft release, then publishes it as latest. |
| `engine.yml` | A maintainer, by hand | Mirrors one engine build, adds it to `engines.json` and signs the list. |
| `check.yml` | Pull requests and pushes to `main` | actionlint, shellcheck, `docker compose config`, and the tests for `scripts/engine-list.sh`. No secrets. |

### An app release

1. In kitsune-browser, set the same version in `Cargo.toml`, `deploy/workspace.toml` and `apps/desktop/package.json`, and commit.
2. Run `tools/release/cut.sh 0.7.1 "what changed"`. It tags the commit and runs `release.yml` here with `ref`, `server` and `notes`. Pass `--no-server` to skip the server.

`release.yml` then runs these jobs:

- **prepare:** refuses a ref that is not `vX.Y.Z` or does not match `Cargo.toml`, then creates the draft. If a failed run left a draft behind, it is reused. A tag that is already published is refused.
- **desktop:** imports the signing certificate into a temporary keychain and runs `tools/release/build-macos.sh`. It attests the `.dmg` and `.app.tar.gz` and uploads them, plus the updater signature, to the draft.
- **server:** runs on native amd64 and arm64 runners. Each runs `tools/release/publish-server.sh --arch` and pushes `kitsune-server:<v>-<arch>`. It then copies the binary out of that image and checks that `--version` prints `kitsune-server <v>`. The binary is packed as `kitsune-server-<v>-linux-{x86_64,aarch64}.tar.gz` with a `.sha256`, attested and uploaded. `deploy/server-install.sh` in kitsune-browser downloads exactly these names.
- **server-merge:** `publish-server.sh --merge` tags `:<v>` and `:latest`, and the index digest is attested in the registry.
- **publish:** writes `latest.json` for the updater and a `SHA256SUMS` of every asset, then publishes the release as latest.

Installed apps read `releases/latest/download/latest.json`. This is why every other release here, the engines and the engine list, is created with `--latest=false`.

### An engine build

```sh
gh workflow run engine.yml -R bitbytelabio/kitsune-release \
  -f engine=ginko -f version=158.0.8127.18 \
  -f url=https://… -f sha256=… \
  -f strip_prefix=ginko-158.0.8127.18-macos-arm64 \
  -f executable=Chromium.app/Contents/MacOS/Chromium \
  -f min_app=0.7.0 -f notes="What changed"
```

- **`version`:** for `ginko`, use the Chromium version. The agent reports it to sites as the Chrome version.
- **`strip_prefix`:** the zip's single top-level directory, as named inside the zip.
- **`executable`:** the path inside the install directory.
- **Order:** the agent compares versions only as strings, so the list is ordered by run, newest first. The last build added for an engine counts as the newest. Running a version that is already listed again moves it back to the top.

`scripts/engine-list.sh` checks the inputs and edits the list. `strip_prefix` and `executable` must be relative paths with no `..`, because every Mac that installs the build joins them onto a directory. The list is read by `crates/kitsune-agent/src/engines.rs`. A list whose `serial` is lower than the one an agent already holds is refused.

The workflow checks the zip against `sha256` before anything is published, then attests the mirrored file. That attestation records that this repository published those bytes. Whether they are the right bytes is settled by the `sha256` you gave it.

## Rules for a public repository

Anyone can read the logs and artifacts here, and a pull request from a fork can read caches. So:

- Only someone with write access can start `release.yml` or `engine.yml`.
- The secrets are in the environment `release`, which only `main` can use. `check.yml` uses no environment.
- Build output goes to a file, because compiler errors quote the source. A failed run shows only the step and the error headings. To see the rest, run the same script locally.
- There is no build cache and no `upload-artifact`. Finished files go straight into a draft release, which is not public.

## Secrets

These are set by `tools/release/setup-ci.sh` in kitsune-browser, from `~/.kitsune-release-keys`, in the environment `release`:

| Secret | What it is |
| --- | --- |
| `SOURCE_DEPLOY_KEY` | A read-only deploy key on kitsune-browser, titled `kitsune-release-ci`. |
| `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD` | The self-signed code-signing certificate `Kitsune Release`, as a base64 `.p12`. |
| `TAURI_SIGNING_PRIVATE_KEY`, `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` | The minisign key that signs app updates and `engines.json`. |

Keep a copy of `~/.kitsune-release-keys` in a password manager. Two of these keys must never change:

- **The Tauri key.** Its public half is built into every installed app, in `apps/desktop/src-tauri/tauri.conf.json` and in `crates/kitsune-agent/src/engines.rs`, which a test keeps equal. If the key is lost or replaced, no installed app can verify an update or a new engine list again. Users would have to reinstall by hand.
- **The certificate.** macOS identifies the app by its signature. An app signed with a different certificate counts as a different app, so users would have to choose Open Anyway again and grant its permissions again.

## Signing

| What | How | Checked by |
| --- | --- | --- |
| App update (`.app.tar.gz`) | minisign, Tauri key | The app's updater, before it installs |
| `engines.json` | minisign, Tauri key | The agent, before it reads the list |
| App bundle and its sidecars | `codesign` with `Kitsune Release` | macOS |
| Every published file and the server image | Sigstore build provenance (`actions/attest`), keyless | Anyone, with `gh attestation verify --repo bitbytelabio/kitsune-release` |
| Every published file | `SHA256SUMS` | Anyone, with `shasum -a 256 -c` |

There is no GPG key, on purpose. Nothing that downloads from here checks a GPG signature: the app and the agent check minisign, and macOS checks codesign. A GPG key would be one more long-lived secret in a public repository, signing files nobody verifies. Sigstore attestations cover the "is this file really from that build" question for people, and need no stored key: each signature comes from a short-lived certificate issued to the workflow run.

To sign git tags, use your own key on your machine (`git tag -s`, GPG or SSH). That has nothing to do with CI.

## Not yet: ginko-core

`engine.yml` only takes a public `https` URL. The ginko-core release workflow makes a draft release in its own private repository, which this workflow cannot download from. The next step there:

- **A new source in `engine.yml`:** download a ginko-core release's `macos-arm64` zip and `.manifest.json` with a read-only token, verify its attestation, and take `sha256` and `strip_prefix` from the manifest. One caveat: GitHub only offers attestations in private repositories on GitHub Enterprise Cloud.
- **Fix the Python launcher in ginko-core.** `python/src/ginko/binary.py` expects `v<package_version>` tags here, which clash with the app's tags, and falls back to `releases/latest`, which is the app. Change it to the `engine-ginko-<chromium version>` tags, and update the `--repo` in its docs and tests to match.
