# Yozgat

Yozgat is a simple self-hosted deployment platform.

## Installation

Install (latest release) — root required
```bash
curl -fsSL https://raw.githubusercontent.com/GroophyLifefor/yozgat-mrt/main/install.sh | sudo bash
```

Update to the latest release (with automatic rollback if fails)
```bash
curl -fsSL https://raw.githubusercontent.com/GroophyLifefor/yozgat-mrt/main/update.sh | sudo bash
```

Uninstall (removes everything incl. data)
```bash	
curl -fsSL https://raw.githubusercontent.com/GroophyLifefor/yozgat-mrt/main/uninstall.sh | sudo bash
```

Uninstall but keep the data directory
```bash
curl -fsSL https://raw.githubusercontent.com/GroophyLifefor/yozgat-mrt/main/uninstall.sh -o uninstall.sh \
  && sudo bash uninstall.sh --keep-data
```

The service listens on `<your-ip>:6637` by default.

---

## Development in Local

### Requirements

- Crystal >= 1.15
- Shards
- Native libraries (see below)


```bash
shards install
```

```bash
just build     # Windows: vendor/libata/win-x64, Linux: vendor/libata/linux-x64
```

Or manually (note: use **absolute** LIBPATHs — the compiler resolves them in the
link phase):

```powershell
# PowerShell
$root = (Get-Location).Path
crystal build src/main.cr -o bin/yozgat.exe --link-flags "/LIBPATH:$root/vendor/libata/win-x64 /LIBPATH:$root/libsqlite"
```

```bash
# Linux
crystal build src/main.cr -o bin/yozgat --link-flags "-Lvendor/libata/linux-x64 -Llibsqlite"
```

Run (DLLs must be findable at runtime):

```powershell
$env:PATH = "$PWD/vendor/libata/win-x64;$PWD/libsqlite;$env:PATH"
.\bin\yozgat.exe      # or: just run
```

Open http://localhost:3000 — the first visit leads to the admin registration
page.

API docs are at http://localhost:3000/docs (Scalar UI) and the raw spec at
`/openapi.json`.

## Configuration

| Env var | Default | Purpose |
|---------|---------|---------|
| `PORT` | `3000` | HTTP listen port |
| `YOZGAT_PUBLIC_DIR` | `./public` | Where the static pages live |
| `YOZGAT_DATA_DIR` | `./data` | Where the SQLite file lives |
| `YOZGAT_JWT_SECRET` | random per boot | Token signing secret. Set it in production; otherwise tokens invalidate on every restart |
