# yozgat-crystal

Crystal web application (Kemal) — the Crystal sibling of `yozgat-rust`.

## Current features

- **First-run setup**: if no user exists, you must register the first account
  (email + password). That account is the mandatory admin.
- **Login / logout**: HMAC-signed stateless tokens; logout is client-side
  (the page just deletes the stored token).
- **Pages**: `setup.html` (register first admin), `login.html`, `index.html`
  (dashboard shell).
- **API**:
  - `GET /setup-status` → `{"needs_setup": bool}`
  - `POST /auth/register` → creates first admin only (`409` if one exists)
  - `POST /auth/login` → `{token, expiresAt, user}`
  - `GET /auth/me` → current user (requires `Authorization: Bearer <token>`)
- **Storage**: SQLite (WAL, `busy_timeout=5000`, `synchronous=NORMAL`) with
  `PRAGMA user_version`-based migrations.
- **Security**: `Crypto::Bcrypt` password hashing (pure Crystal, no C dep),
  HMAC-SHA256 signed tokens, constant-time signature comparison.

## Requirements

- Crystal >= 1.15
- Shards
- Native libraries (see below)

## Install

```bash
shards install
```

Fetches `ata-validator-crystal`, `kemal`, and `sqlite3` into `lib/`. The native
libraries are not bundled by the shards and must be provided:

## Native libraries

Two pairs are required — `ata` (JSON Schema validation, from
`ata-validator-crystal`) and `sqlite3` (database):

| Pair   | Link time      | Runtime      |
|--------|----------------|--------------|
| ata    | `libata/ata.lib` | `libata/ata.dll` |
| sqlite | `libsqlite/sqlite3.lib` | `libsqlite/sqlite3.dll` |

The repo keeps both folders populated for convenience. On Windows, `sqlite3.lib`
is the import library generated from SQLite's official `sqlite3.def`
(`lib.exe /def:sqlite3.def /out:sqlite3.lib /machine:x64`).

## Layout

```
src/
  main.cr        entry point: requires the folders, opens DB, starts Kemal
  config.cr      env-driven config (data dir, JWT secret)
  db/            SQLite pool, migrations, user repository
  api/           JSON API endpoints (auth, hello)
  app/           UI routing (GET / redirects to setup/login/dashboard)
  lib/           shared helpers (auth: bcrypt + tokens)
public/          static pages (setup.html, login.html, index.html, app.js)
lib/             dependencies fetched by shards
libata/          ata.dll + ata.lib
libsqlite/       sqlite3.dll + sqlite3.lib
spec/            package consumption tests
data/            runtime SQLite file (created on first run, gitignored)
```

## Build and run

```bash
just build     # Windows: uses absolute LIBPATHs, Linux: -Llibata -Llibsqlite
```

Or manually (note: use **absolute** LIBPATHs — the compiler resolves them in the
link phase):

```powershell
# PowerShell
$root = (Get-Location).Path
crystal build src/main.cr -o bin/yozgat.exe --link-flags "/LIBPATH:$root\libata /LIBPATH:$root\libsqlite"
```

```bash
# Linux
crystal build src/main.cr -o bin/yozgat --link-flags "-Llibata -Llibsqlite"
```

Run (DLLs must be findable at runtime):

```powershell
$env:PATH = "$PWD\libata;$PWD\libsqlite;$env:PATH"
.\bin\yozgat.exe      # or: just run
```

Open http://localhost:3000 — the first visit leads to the admin registration
page.

## Configuration

| Env var | Default | Purpose |
|---------|---------|---------|
| `PORT` | `3000` | HTTP listen port |
| `YOZGAT_PUBLIC_DIR` | `./public` | Where the static pages live |
| `YOZGAT_DATA_DIR` | `./data` | Where the SQLite file lives |
| `YOZGAT_JWT_SECRET` | random per boot | Token signing secret. Set it in production; otherwise tokens invalidate on every restart |

## VPS deploy

Releases are built for `x86_64-linux-gnu` on every `v*` tag push
(`.github/workflows/release.yml`) and uploaded as `yozgat-x86_64-linux-gnu.tar.gz`
containing the binary, `libata.so` and `public/`.

```bash
# Install (latest release) — root required
curl -fsSL https://raw.githubusercontent.com/GroophyLifefor/yozgat-crystal/main/install.sh | sudo bash

# Update to the latest release (with automatic rollback)
sudo bash update.sh        # or fetch update.sh from the repo first

# Uninstall
sudo bash uninstall.sh            # removes everything incl. data
sudo bash uninstall.sh --keep-data

# Service management
sudo systemctl status yozgat
sudo journalctl -u yozgat -f
```

The install writes `/etc/yozgat/env` (`PORT`, `YOZGAT_DATA_DIR`,
`YOZGAT_PUBLIC_DIR`, `YOZGAT_JWT_SECRET`) and installs a systemd unit that runs
the binary as the `yozgat` user with `LD_LIBRARY_PATH` pointing at
`/usr/local/lib/yozgat` (where `libata.so` lives). Data is stored in
`/var/lib/yozgat`.

The service listens on `0.0.0.0:6637` by default.

## Test

```bash
$env:PATH = "$PWD\libata;$env:PATH"
crystal spec --link-flags "/LIBPATH:$((Get-Location).Path)\libata"
```
