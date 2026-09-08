# 🐺 Roothound

**Map your path from a low-priv shell to root — like BloodHound, but for local Linux privilege escalation.**

You landed a shell as a low-privilege user. Now what? Instead of scrolling through hundreds of lines of enumeration output, Roothound draws you a clear graph of **every path to root** — and tells you exactly how to abuse each one.

##  Features

- 🗺️ **Attack-path graph** — see `YOU → technique → ROOT`, left to right
- 🔴 **Confidence coloring** — confirmed paths in red, likely leads in amber
- 🖱️ **Click any node** — get what it is + the exact abuse command (copy-ready)
- 🔗 **Multi-hop chains** — spots paths across separate findings (e.g. writable script → root cron → root)
- 🧠 **Editable rulebook** — SUID/SGID, sudo, capabilities, dangerous groups, writable files, NFS, PATH hijack, and kernel/sudo CVE matching
- 📴 **Fully offline** — no dependencies, no internet, single self-contained HTML output

##  Usage

##  Installation

**Option 1 — clone it:**
```bash
git clone https://github.com/Noz2/RootHound.git
cd RootHound
# feed it LinPEAS output:
python3 RootHound.py linpeas.txt -o report.html
```


**Option 2 — download ZIP:**
Click the green **Code** button above → **Download ZIP**, unzip, and run it.

Then open `report.html` in any browser.

##  Demo

<img width="1709" height="1031" alt="Screenshot 2026-07-24 at 19 03 33" src="https://github.com/user-attachments/assets/5e0d97a7-ce22-4bff-8501-ef7cdb8a7cd1" />




<img width="1710" height="1036" alt="Screenshot 2026-07-24 at 19 04 00" src="https://github.com/user-attachments/assets/4c1e5aa1-730b-48e1-af24-32b0662c5d21" />



See Roothound in action: **[Watch the demo on X →](https://x.com/N0ur2dd1n2/status/2080720705184825372?s=20)**

## ⚠️ Disclaimer

Roothound is built for **authorized** security testing and education (CTFs, HTB, your own labs). Only use it on systems you have explicit permission to test.

