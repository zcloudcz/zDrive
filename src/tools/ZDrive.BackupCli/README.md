# ZDrive.BackupCli

Headless Linux backup tool for zDrive. Mirrors a local directory into a
zDrive account through the public API — no Flutter client involved. Meant to
be run from cron on a Linux server.

## What it does

- Recursively walks a local directory, creating matching folders in zDrive
  and uploading files that don't already exist there unchanged.
- Idempotent: on every run it checks each file's remote upload manifest and
  skips files whose chunk hashes already match the local file. A changed
  file gets re-uploaded as a new version on the same file node (not a
  duplicate).
- Resumable: if a run is killed mid-upload, the next run finds the
  half-finished file (a node with no completed manifest) and re-uploads it.
  There is no local state file — every run re-derives what's missing from
  what the API reports.
- Progress goes to stdout, errors to stderr, exit code is non-zero on any
  failure — safe to run from cron and alert on non-zero exit.

## Install (Linux)

```bash
# On the build machine (needs the .NET 8 SDK):
dotnet publish src/tools/ZDrive.BackupCli -c Release -r linux-x64 \
  --self-contained false -o /opt/zdrive-backup

# On the target server (needs the .NET 8 runtime installed):
scp -r /opt/zdrive-backup user@server:/opt/zdrive-backup
```

## Configuration (environment variables)

| Variable | Purpose |
|----------|---------|
| `ZDRIVE_API_URL` | Base URL of the API Gateway, e.g. `https://zdrive.example.com/api/v1` |
| `ZDRIVE_USER` | Email of a dedicated backup user (register one separately — this tool does not register accounts) |
| `ZDRIVE_PASSWORD` | Password for that user. Never logged; keep it out of shell history (see cron example) |

All three are required. The tool refreshes its access token automatically
using the refresh token issued at login — no need to re-authenticate mid-run.

## Usage

```bash
dotnet zdrive-backup.dll <local-directory> [--dest <remote-folder-path>]
```

- `<local-directory>` — required, the directory to back up.
- `--dest` — optional remote folder path (created if missing). Omit to
  upload directly into the account root.

Example:

```bash
ZDRIVE_API_URL=https://zdrive.example.com/api/v1 \
ZDRIVE_USER=backup@example.com \
ZDRIVE_PASSWORD=... \
dotnet /opt/zdrive-backup/zdrive-backup.dll /data/photos --dest backup/photos
```

## Cron example

Keep the password out of the crontab itself — put it in a root-only env file:

```bash
# /etc/zdrive-backup.env (chmod 600, owned by root)
export ZDRIVE_API_URL=https://zdrive.example.com/api/v1
export ZDRIVE_USER=backup@example.com
export ZDRIVE_PASSWORD='...'
```

Plain (non-exported) shell variables in the env file would not be inherited by
`dotnet`, so `export` (or `set -a`) is required — a sourced-but-not-exported
file fails silently with "Missing required env vars".

```cron
# /etc/cron.d/zdrive-backup — nightly at 02:30
30 2 * * * root . /etc/zdrive-backup.env && dotnet /opt/zdrive-backup/zdrive-backup.dll /data/photos --dest backup/photos >> /var/log/zdrive-backup.log 2>&1
```

## What it deliberately doesn't do

- No download/restore command — this tool is one-directional (local ->
  zDrive). Use the Flutter client or the API directly to restore.
- No chunk-level resume — a file that needs re-uploading is uploaded whole
  again, not just its changed chunks. Simpler, and the server already
  dedupes identical chunk content, so re-uploaded chunks that are byte-
  identical to an existing version don't consume extra blob storage.
- No account registration — point it at an existing dedicated backup user.
