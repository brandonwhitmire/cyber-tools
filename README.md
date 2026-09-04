# cyber-tools

Offline repository for curated cybersecurity tools:

- Manifest file declares each tool and how to fetch it
- Sync engine pulls updates
- Scheduled GitHub Action commits only when something changes

## Layout

```
cyber-tools/
├── sync.json                  # declare each tool + how to grab it
├── sync_tools.sh              # the sync engine
├── sync_extras.sh             # sync + extras (AccessChk, extract Python)
├── deliver_tools.sh           # one-command HTTP + SMB staging server
├── tools.sh                   # `tools` launcher (find repo + deliver)
├── .github/workflows/         # twice-weekly cron + manual trigger
└── tools/                     # flat binaries/scripts; code repos keep their own folders
```

## Quick start

```bash
chmod +x sync_tools.sh sync_extras.sh deliver_tools.sh tools.sh
./sync_extras.sh
```

Optional: pass a GitHub token to raise API rate limits during sync:

```bash
GITHUB_TOKEN=<PAT> ./sync_extras.sh
```

## Staging server

Prints the connect IP (not `0.0.0.0`), a compact file table, and pasteable wget / SMB commands. Replace `FILE` with a name from the table.

```bash
CONNECT_IP=10.10.14.5 SERVE_DIR=./tools SERVER_IP=0.0.0.0 HTTP_PORT=8080 SMB_PORT=445 SMB_SHARE=tools SMB_USER=guest SMB_PASS=guest ./deliver_tools.sh
```

`CONNECT_IP` is optional — when unset, the script uses `SERVER_IP` if it is a real address, otherwise the default-route IPv4. Other local IPv4s are listed so you can pin `tun0` vs `eth0`.

### `tools` command

`tools/` is the payload directory, so the launcher is `tools.sh`. After install you type `tools`:

```bash
./tools.sh --install    # appends `source .../tools.sh` to ~/.zshrc or ~/.bashrc
source ~/.zshrc         # or open a new terminal
tools
```

Or source it yourself:

```bash
source /path/to/cyber-tools/tools.sh
tools
```

The function finds the repo (or uses `CYBER_TOOLS_DIR`), `cd`s there, and runs `deliver_tools.sh`. Running `./tools.sh` directly does the same without changing your shell's cwd.

## Acquisition strategies

Each entry in `sync.json` uses a `type` that selects one of four strategies:

| Type | What it does |
|------|--------------|
| `release` | Fetches matching assets from the latest GitHub Release into `tools/` |
| `file` | Raw-downloads specific file(s) from a repo at a given ref into `tools/` |
| `repo` | Shallow-clones the repo into `tools/<name>/` and strips `.git` |
| `build` | Temp-clones the repo, runs `commands`, keeps only `artifacts` in `tools/` |

Optional per-tool `rename` map rewrites each matched asset basename (regex → dest name). Use `"$lower"` to lowercase the matched name (current default for all tools).

Optional `extract: true` unpacks downloaded `.zip` / `.tar.gz` archives and keeps only files whose basename matches `extract_keep` (string or array of regexes). Kept files are written lowercase into `tools/` and the archive is deleted. Omit `extract` for archives you want to keep intact (e.g. `static-python`).

## Adding a tool

Add one JSON object to the `tools` array in `sync.json`. No script edits required.

### Release (latest build artifacts)

```json
{
  "name": "runascs",
  "type": "release",
  "repo": "antonioCoco/RunasCs",
  "assets": ["^RunasCs\\.zip$"],
  "rename": {
    "^RunasCs\\.zip$": "$lower"
  },
  "extract": true,
  "extract_keep": ["^RunasCs\\.exe$", "^RunasCs_net2\\.exe$"]
}
```

### File (specific paths, not a full clone)

```json
{
  "name": "powersploit",
  "type": "file",
  "repo": "PowerShellMafia/PowerSploit",
  "ref": "master",
  "paths": ["Privesc/PowerUp.ps1"],
  "rename": {
    "^PowerUp\\.ps1$": "$lower"
  }
}
```

### Repo (full shallow clone)

```json
{
  "name": "my-scripts",
  "type": "repo",
  "repo": "owner/repo",
  "ref": "master"
}
```

### Build (temp clone → compile → keep binaries)

Requires build tooling on the runner (e.g. Go + UPX for ligolo-ng). The clone is discarded after artifacts are copied.

```json
{
  "name": "ligolo-ng",
  "type": "build",
  "repo": "nicocha30/ligolo-ng",
  "ref": "master",
  "commands": [
    "CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -ldflags=\"-s -w\" -o agent.exe cmd/agent/main.go",
    "CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -ldflags=\"-s -w\" -o proxy.exe cmd/proxy/main.go",
    "CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags=\"-s -w\" -o agent cmd/agent/main.go",
    "CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags=\"-s -w\" -o proxy cmd/proxy/main.go",
    "upx --lzma agent.exe proxy.exe agent proxy"
  ],
  "artifacts": ["^agent$", "^agent\\.exe$", "^proxy$", "^proxy\\.exe$"],
  "rename": {
    "^agent$": "ligolo-agent",
    "^agent\\.exe$": "ligolo-agent.exe",
    "^proxy$": "ligolo-proxy",
    "^proxy\\.exe$": "ligolo-proxy.exe"
  }
}
```

## Extras fetched by sync_extras.sh

Some tools are not in `sync.json` because they have no suitable GitHub source:

- **AccessChk** — downloaded from Sysinternals (`live.sysinternals.com`) as `tools/accesschk.exe` and `tools/accesschk64.exe`.
- **Portable Python** — the `static-python` release tarball is extracted into `tools/python/` after sync.

## Local testing

```bash
chmod +x sync_tools.sh
GITHUB_TOKEN=<PAT> ./sync_tools.sh
```

`GITHUB_TOKEN` is optional locally but recommended — it is sent only on GitHub API calls (not asset downloads) to raise the rate limit.

## GitHub Action setup

The workflow runs twice a week (Monday and Thursday at 06:00 UTC) and on manual trigger (`workflow_dispatch`). It installs **Go** and **UPX** (needed for `type: build` tools like ligolo-ng), runs `sync_tools.sh`, stages all changes, and commits/pushes only when `git diff --cached` is non-empty.

**Required repo setting:** Settings → Actions → General → Workflow permissions → **Read and write permissions**.

## Tool inventory

| Filename | Description |
|----------|-------------|
| `accesschk.exe` | [Sysinternals access checker (x86)](https://learn.microsoft.com/en-us/sysinternals/downloads/accesschk) |
| `accesschk64.exe` | [Sysinternals access checker (x64)](https://learn.microsoft.com/en-us/sysinternals/downloads/accesschk) |
| `bloodhound-cli` | [BloodHound CLI for Linux](https://github.com/SpecterOps/bloodhound-cli) |
| `cpython-3.11.15+20260807-x86_64-pc-windows-msvc-install_only.tar.gz` | [Standalone Windows Python build](https://github.com/indygreg/python-build-standalone) |
| `domainpasswordspray.ps1` | [AD password spraying script](https://github.com/dafthack/DomainPasswordSpray) |
| `firefox_decrypt.py` | [Firefox password decryptor](https://github.com/unode/firefox_decrypt) |
| `godpotato-net2.exe` | [Potato priv-esc for .NET 2](https://github.com/BeichenDream/GodPotato) |
| `godpotato-net35.exe` | [Potato priv-esc for .NET 3.5](https://github.com/BeichenDream/GodPotato) |
| `godpotato-net4.exe` | [Potato priv-esc for .NET 4](https://github.com/BeichenDream/GodPotato) |
| `hack-browser-data.exe` | [Browser credential extractor](https://github.com/moonD4rk/HackBrowserData) |
| `inveigh.exe` | [Windows mitm/spoofing toolkit](https://github.com/Kevin-Robertson/Inveigh) |
| `john.smith.txt` | [Likely username wordlist](https://github.com/insidetrust/statistically-likely-usernames) |
| `johnsmith.txt` | [Likely username wordlist](https://github.com/insidetrust/statistically-likely-usernames) |
| `jsmith.txt` | [Likely username wordlist](https://github.com/insidetrust/statistically-likely-usernames) |
| `jsmith2.txt` | [Likely username wordlist](https://github.com/insidetrust/statistically-likely-usernames) |
| `juicypotato.exe` | [Windows potato priv-esc](https://github.com/ohpe/juicy-potato) |
| `kerbrute_linux_amd64` | [Kerberos user enum (Linux)](https://github.com/ropnop/kerbrute) |
| `kerbrute_windows_amd64.exe` | [Kerberos user enum (Windows)](https://github.com/ropnop/kerbrute) |
| `lapstoolkit.ps1` | [LAPS enumeration toolkit](https://github.com/leoloobeek/LAPSToolkit) |
| `lazagne.exe` | [Credential recovery tool](https://github.com/AlessandroZ/LaZagne) |
| `ligolo-agent` | [Ligolo-ng agent (Linux)](https://github.com/nicocha30/ligolo-ng) |
| `ligolo-agent.exe` | [Ligolo-ng agent (Windows)](https://github.com/nicocha30/ligolo-ng) |
| `ligolo-proxy` | [Ligolo-ng proxy (Linux)](https://github.com/nicocha30/ligolo-ng) |
| `ligolo-proxy.exe` | [Ligolo-ng proxy (Windows)](https://github.com/nicocha30/ligolo-ng) |
| `linpeas.sh` | [Linux priv-esc enumerator](https://github.com/peass-ng/PEASS-ng) |
| `lse.sh` | [Linux smart enumeration](https://github.com/diego-treitos/linux-smart-enumeration) |
| `nc-x64` | [Static netcat Linux x64](https://github.com/mermehr/static-binaries) |
| `nc-x64.exe` | [Static netcat Windows x64](https://github.com/mermehr/static-binaries) |
| `nc-x86` | [Static netcat Linux x86](https://github.com/mermehr/static-binaries) |
| `nc-x86.exe` | [Static netcat Windows x86](https://github.com/mermehr/static-binaries) |
| `nmap` | [Static nmap Linux binary](https://github.com/andrew-d/static-binaries) |
| `nmap.exe` | [Static nmap Windows binary](https://github.com/andrew-d/static-binaries) |
| `powerhuntshares.psm1` | [Share hunting PowerShell module](https://github.com/NetSPI/PowerHuntShares) |
| `powerup.ps1` | [Windows priv-esc checks](https://github.com/PowerShellMafia/PowerSploit) |
| `powerview.ps1` | [AD situational awareness](https://github.com/PowerShellMafia/PowerSploit) |
| `pretender` | [LLMNR/NBT-NS/mDNS spoofing](https://github.com/RedTeamPentesting/pretender) |
| `pretender.exe` | [LLMNR/NBT-NS/mDNS spoofing](https://github.com/RedTeamPentesting/pretender) |
| `printerbug.py` | [MS-RPRN coercion helper](https://github.com/dirkjanm/krbrelayx) |
| `printspoofer32.exe` | [PrintSpooler priv-esc (x86)](https://github.com/itm4n/PrintSpoofer) |
| `printspoofer64.exe` | [PrintSpooler priv-esc (x64)](https://github.com/itm4n/PrintSpoofer) |
| `pspy32` | [Linux process monitor (x86)](https://github.com/DominicBreuker/pspy) |
| `pspy64` | [Linux process monitor (x64)](https://github.com/DominicBreuker/pspy) |
| `pssqlite.psd1` | [SQLite PowerShell module](https://github.com/RamblingCookieMonster/PSSQLite) |
| `rogueoxidresolver.exe` | [RoguePotato Oxid resolver](https://github.com/antonioCoco/RoguePotato) |
| `roguepotato.exe` | [RoguePotato priv-esc](https://github.com/antonioCoco/RoguePotato) |
| `roothound-collector.sh` | [RootHound collector helper](https://github.com/Noz2/RootHound) |
| `roothound.py` | [RootHound AD collector](https://github.com/Noz2/RootHound) |
| `runascs.exe` | [RunasCs privilege tool](https://github.com/antonioCoco/RunasCs) |
| `runascs_net2.exe` | [RunasCs for .NET 2](https://github.com/antonioCoco/RunasCs) |
| `seatbelt.exe` | [GhostPack host survey](https://github.com/r3motecontrol/Ghostpack-CompiledBinaries) |
| `sharpup.exe` | [GhostPack priv-esc checks](https://github.com/r3motecontrol/Ghostpack-CompiledBinaries) |
| `smtp-user-enum.py` | [SMTP user enumeration](https://github.com/cytopia/smtp-user-enum) |
| `snaffler.exe` | [AD share content finder](https://github.com/SnaffCon/Snaffler) |
| `socat` | [Static socat Linux binary](https://github.com/andrew-d/static-binaries) |
| `socatx64.exe` | [Static socat Windows x64](https://github.com/3ndG4me/socat) |
| `socatx86.exe` | [Static socat Windows x86](https://github.com/3ndG4me/socat) |
| `sweetpotato.exe` | [SweetPotato priv-esc](https://github.com/uknowsec/SweetPotato) |
| `winpeasx64.exe` | [Windows priv-esc enumerator](https://github.com/peass-ng/PEASS-ng) |
| `winpeasx86.exe` | [Windows priv-esc enumerator](https://github.com/peass-ng/PEASS-ng) |
