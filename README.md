# cyber-tools

Offline vendoring repository for curated cybersecurity tools. A manifest declares each tool and how to fetch it; a sync engine pulls updates; a scheduled GitHub Action commits only when something actually changed.

## Layout

```
cyber-tools/
├── tools.json                  # declare each tool + how to grab it
├── sync.sh                     # the sync engine
├── .github/workflows/sync.yml  # daily cron + manual trigger
└── tools/                      # auto-populated, one dir per tool
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
