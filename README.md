# Kitsune release

Releases of Kitsune: the team server, the macOS app, and the browser engines the app runs. The source is developed elsewhere. This repository is where the builds are made and published.

- **Server:** the image `ghcr.io/bitbytelabio/kitsune-server` and the compose file in this repository.
- **App:** a DMG for macOS on Apple Silicon, on the [Releases](https://github.com/bitbytelabio/kitsune-release/releases) page.
- **Engines:** the Chrome (`ginko`) and Firefox (`kitsunebi`) builds the app downloads for each profile. They live in releases named `engine-…` and are listed in the signed `engines` release.

## Install the server

You need a machine with Docker. A small team fits on 1 vCPU and 1 GB of RAM.

```sh
git clone https://github.com/bitbytelabio/kitsune-release
cd kitsune-release
cp .env.example .env
# Set KITSUNE_DB_PASSWORD in .env to a password of your own
docker compose up -d
```

To check that the server is up, run the command below. A working server answers `{"error":"unauthenticated"}`:

```sh
curl http://127.0.0.1:8901/v1/me
```

The server only listens on `127.0.0.1:8901`. To reach it from other machines, put a reverse proxy with TLS in front of it, such as Caddy or Cloudflare Tunnel.

### The first account

A new server has no users, so you create the first invitation yourself:

```sh
docker compose exec server kitsune-server invite --email you@example.com --org "My team"
```

It prints an invitation code. In the app, choose that you have an invitation, then enter the server's address and the code.

### Email (optional)

When `KITSUNE_SMTP_URL` and `KITSUNE_MAIL_FROM` are set in `.env`, the server emails a six-digit code to confirm that an invitation is used by the person it was sent to. Without them, an invitation code works for whoever enters it first. See `.env.example` for the format.

### Update

```sh
docker compose pull
docker compose up -d
```

To stay on one version, set `KITSUNE_VERSION=0.7.0` (or any released version) in `.env`.

### Back up

The data is in two volumes, `kitsune-db` and `kitsune-bundles`. Back them up together: the database lists profile versions whose contents are in the bundles volume.

Keep `docker-compose.yml` where it is and run it from this directory. Docker Compose names the volumes after the directory. If you move or rename it, the server starts with new, empty volumes.

### Without Docker

Each release also carries `kitsune-server-<version>-linux-x86_64.tar.gz` and `kitsune-server-<version>-linux-aarch64.tar.gz`, each with a `.sha256`. Each archive holds one binary, the same one that is in the image. It needs glibc 2.36 or newer (Debian 12, Ubuntu 22.04 or later) and a PostgreSQL database. The server must connect as a role that is not a superuser: a superuser bypasses row-level security. `postgres-init/10-kitsune-role.sh` shows the role it expects.

## Install the app

Download the DMG for macOS on Apple Silicon from [Releases](https://github.com/bitbytelabio/kitsune-release/releases), open it and drag Kitsune into Applications.

The app is signed with Kitsune's own certificate, not one issued by Apple, so macOS blocks it the first time you open it. Open System Settings → Privacy & Security, scroll down and choose **Open Anyway**. You only do this once.

After that the app updates itself. When an update is ready, a **Restart to update** button appears at the top of the window. Close any open profiles before you press it.

When a new Chrome or Firefox build is available, a profile shows a badge next to its name. Each profile keeps the build it has until you choose **Update** in that profile's menu.

## Verify a download

Releases after 0.7.0 come with a build provenance attestation for every file and for the server image. An attestation is a Sigstore signature that ties the file to the workflow run in this repository that built it. To check one, use the [GitHub CLI](https://cli.github.com):

```sh
gh attestation verify Kitsune_0.7.1_aarch64.dmg --repo bitbytelabio/kitsune-release
gh attestation verify oci://ghcr.io/bitbytelabio/kitsune-server:0.7.1 --repo bitbytelabio/kitsune-release
```

Those releases also have a `SHA256SUMS`. In the folder you downloaded the release's files to, run:

```sh
shasum -a 256 -c --ignore-missing SHA256SUMS
```

You don't need to do anything to check updates and engines. The app checks every update and the engine list against a key built into it before it uses them.

## Maintainers

How releases are built, signed and published is described in [docs/releasing.md](docs/releasing.md).
