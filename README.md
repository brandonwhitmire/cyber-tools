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
├── .github/workflows/         # twice-weekly cron + manual trigger
└── tools/                     # flat binaries/scripts; code repos keep their own folders
```

## Quick start

```bash
chmod +x sync_tools.sh sync_extras.sh deliver_tools.sh
./sync_extras.sh
```

Optional: pass a GitHub token to raise API rate limits during sync:

```bash
GITHUB_TOKEN=<PAT> ./sync_extras.sh
```

## Staging server

```bash
SERVE_DIR=./tools SERVER_IP=0.0.0.0 HTTP_PORT=8080 SMB_SHARE=tools SMB_USER=guest SMB_PASS=guest ./deliver_tools.sh
```

## Acquisition strategies

Each entry in `sync.json` uses a `type` that selects one of three strategies:

| Type | What it does |
|------|--------------|
| `release` | Fetches matching assets from the latest GitHub Release into `tools/` |
| `file` | Raw-downloads specific file(s) from a repo at a given ref into `tools/` |
| `repo` | Shallow-clones the repo into `tools/<name>/` and strips `.git` |

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
  "name": "ligolo-ng",
  "type": "repo",
  "repo": "nicocha30/ligolo-ng",
  "ref": "master"
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

The workflow runs twice a week (Monday and Thursday at 06:00 UTC) and on manual trigger (`workflow_dispatch`). It runs `sync_tools.sh`, stages all changes, and commits/pushes only when `git diff --cached` is non-empty.

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
| `ligolo-ng/` | [Tunneling / pivoting toolkit](https://github.com/nicocha30/ligolo-ng) |
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
