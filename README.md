# iSCSI-CHAP-Cracker
Cracking iSCSI CHAP authentication hashes with long challenges (64+ bytes), which Hashcat's native mode 4800 cannot handle.

---

<img width="1093" height="845" alt="grafik" src="https://github.com/user-attachments/assets/539cdb6a-aaf7-4c70-be6e-d2d65a1c3628" />


---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🎨 **Dark-themed GUI** | Professional tabbed interface with modern color scheme |
| 🔢 **Long Challenge Support** | Handles CHAP challenges of any length (64–1024 bytes), bypassing Hashcat mode 4800's 16-byte limit |
| 📝 **Auto-Clean Input** | Paste hex values with `0x`, spaces, or colons — the tool sanitizes automatically |
| 🌐 **Multi-Encoding Support** | ASCII, UTF-8, and UTF-16LE wordlists with automatic conversion |
| 🧩 **Null-Pad Option** | Optional 16-byte null padding for targets that pad passwords before hashing |
| ⚡ **One-Click Hashcat Launch** | Generates files and launches Hashcat directly from the GUI |
| 🔓 **Auto-Decode Results** | Converts `$HEX[...]` Hashcat output back to readable plaintext automatically |
| 🗂️ **Cracked Password Manager** | View, export, and clear previously cracked passwords across sessions |
| 🔍 **Auto-Detect Hashcat** | Automatically finds `hashcat.exe` in common locations or PATH |
| 🧹 **Potfile Management** | Delete potfiles before runs to avoid cached results interfering |
| 📋 **Clipboard Copy** | One-click copy of recovered passwords to clipboard |
| 📤 **Export Results** | Save cracked passwords to a text file |
| ⏱️ **Live Status Monitor** | Timer-based process monitoring with status bar updates |
| 💡 **Tooltips** | Hover help on every input field |
| 🖥️ **Resize-Aware Layout** | Form resize handler keeps all elements properly positioned |

---

## 🚨 Why this Tool? The Problem

### Windows iSCSI Initiator + Long CHAP Challenges

Hashcat's native **mode 4800** (iSCSI CHAP authentication, MD5) only supports **16-byte CHAP challenges**. However, many modern Linux iSCSI targets (TGT, LIO/TCMU, ESXi, etc.) generate **longer challenges — typically 64 bytes or more**.

When you try to crack these with Hashcat mode 4800, you get:

```
Token length exception
```

This happens because:
- **RFC 3720** allows CHAP challenges up to **1024 bytes**
- Hashcat mode 4800 was hardcoded for the legacy **16-byte** challenge length
- Windows iSCSI Initiator happily accepts and uses these long challenges
- Your captured handshake is valid — Hashcat just can't ingest it

### The Workaround

This tool converts the iSCSI CHAP capture into **Hashcat mode 10** format:

```
MD5(password || salt)
```

Where:
- `password` = `CHAP_I` (1-byte identifier) + your candidate password
- `salt` = full `CHAP_C` challenge (can be 64, 128, 256+ bytes)

By hex-encoding the wordlist and prepending `CHAP_I` to every candidate, Hashcat mode 10 computes the exact same hash as the iSCSI CHAP response — without the 16-byte limitation.


---

## 📦 Requirements

- **Windows** with PowerShell 5.1 or later
- **[Hashcat](https://hashcat.net/hashcat/)** (tested with 6.2.x+)
- A **wordlist** (e.g., `rockyou.txt`, custom lists)
- iSCSI CHAP capture data (see [Getting CHAP Hashes](#getting-chap-hashes-from-a-capture))

### Optional
- GPU with OpenCL/CUDA support (Hashcat will use CPU otherwise)
- Large wordlists for complex passwords

---

## 🚀 Installation

1. **Download** `iSCSI_CHAP_Cracker.ps1`
2. **Install Hashcat** and ensure `hashcat.exe` is in your PATH, or configure the full path in the tool
3. **Right-click → Run with PowerShell**, or execute:
   ```powershell
   .\iSCSI_CHAP_Cracker.ps1
   ```

> ⚠️ **Note:** If execution policy blocks the script, run:
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
> ```

---

## 🔍 Getting CHAP Hashes from a Capture

### Method 1: Wireshark

1. Start a capture on the network interface connected to your iSCSI target
2. Filter for iSCSI protocol: `iscsi.keyvalue`
3. Look for the **CHAP Authentication** sequence:
   - `CHAP_C` — Challenge from target (long hex string, 128+ chars)
   - `CHAP_R` — Response from initiator (32 hex chars = 16-byte MD5)
   - `CHAP_I` — Identifier (usually `0x01`, `0x02`, etc.)

4. Right-click each field → **Copy → Value** (as hex string)

```
Example Wireshark fields:
  iscsi.chap.c    → CHAP_C (Challenge)
  iscsi.chap.r    → CHAP_R (Response)
  iscsi.chap.i    → CHAP_I (Identifier)
```

### Method 2: tcpdump / tshark (Linux)

```bash
# Capture iSCSI traffic
sudo tcpdump -i eth0 -w iscsi.pcap port 3260

# Extract CHAP fields
tshark -r iscsi.pcap -Y "iscsi.opcode == 0x03" -T fields -e iscsi.chap.i -e iscsi.chap.c -e iscsi.chap.r
```

### Method 3: Windows Event Logs / iSCSI Initiator Logs

Some iSCSI initiators log authentication details. Check:
- `Event Viewer → Applications and Services Logs → Microsoft → Windows → iSCSI`
- Initiator debug logs (if enabled)

### What You Need

| Field | Format | Example |
|-------|--------|---------|
| **CHAP_I** | 1-2 hex digits | `0x01` or just `1` |
| **CHAP_C** | Long hex string (64–1024 bytes) | `0xb06ceb4baefc3362...` (128+ chars) |
| **CHAP_R** | Exactly 32 hex chars (16-byte MD5) | `0x713b60dcda2cfcc4a02ece6852fdf2ad` |

> 💡 **Tip:** The tool accepts `0x` prefix, spaces, colons — it auto-cleans everything.

---

## 🖥️ How to: Using the Tool

### Tab 1: Generate & Crack

1. **Paste** `CHAP_I`, `CHAP_C`, `CHAP_R` into the fields
2. **Select wordlist** via Browse button
3. Choose **encoding**:
   - `ASCII` — Standard text wordlists
   - `UTF8` — Unicode wordlists
   - `UTF16LE` — Windows-style UTF-16 (auto-converted to ASCII hex)
4. Check **Null-pad** if your target pads passwords to 16 bytes with `0x00`
5. Click **GENERATE FILES** — creates `hash.txt` + `wordlist_hex.txt`
6. Click **RUN HASHCAT** — launches Hashcat mode 10
7. Click **DECODE** — converts `$HEX[...]` output to readable plaintext

### Tab 2: Manage Cracked

View, export, and clear previously cracked passwords from:
- `cracked.txt` (output directory)
- `hashcat.potfile` (output directory + Hashcat directory)

<img width="928" height="459" alt="grafik" src="https://github.com/user-attachments/assets/a6c93849-0a73-45da-a7e8-26a420c42eea" />



### Tab 3: Configuration

| Setting | Description |
|---------|-------------|
| **Hashcat .exe** | Path to `hashcat.exe` (auto-detected if in PATH) |
| **Output Dir** | Where generated files are saved |
| **Default Encoding** | Pre-selected wordlist encoding |
| **Null-pad default** | Auto-check null-pad option |
| **Auto-delete potfile** | Clear previous results before run |
| **Auto-decode** | Automatically decode after Hashcat finishes |

<img width="753" height="422" alt="grafik" src="https://github.com/user-attachments/assets/93a1621a-d386-4d52-90cf-82879042158c" />


---

## ⚠️ Important Notes

### Do NOT Use `-O` (Optimized Kernel)

Long salts (>16 bytes) require Hashcat's **pure kernel**. The tool generates the command without `-O`. If you run Hashcat manually, omit `-O`:

```bash
# ✅ CORRECT
hashcat.exe -m 10 -a 0 --hex-wordlist --hex-salt hash.txt wordlist_hex.txt -o cracked.txt --force

# ❌ WRONG — will fail with long challenges
hashcat.exe -m 10 -a 0 -O --hex-wordlist --hex-salt hash.txt wordlist_hex.txt
```

### Performance Tips

- Add `-w 3` for maximum GPU workload
- Add `-d 1` to specify a specific GPU device
- Use `--potfile-disable` if you don't want to save to `hashcat.potfile`

---


## 🔬 Technical Details

### iSCSI CHAP Authentication Flow

```
Initiator                          Target
─────────                          ──────
   │ ─────── CHAP_I (identifier) ──────> │
   │ <──── CHAP_C (random challenge) ──── │
   │                                     │
   │  response = MD5(CHAP_I || password || CHAP_C)
   │ ─────── CHAP_R (response) ─────────> │
   │                                     │
   │  Target verifies: MD5(CHAP_I || password || CHAP_C) == CHAP_R
```

### Why Mode 10 Works

Hashcat mode 10: `md5($pass.$salt)`

| iSCSI CHAP | Hashcat Mode 10 |
|------------|-----------------|
| `password` = `CHAP_I \|\| user_password` | `pass` = hex-encoded `CHAP_I \|\| candidate` |
| `salt` = `CHAP_C` (full challenge) | `salt` = full `CHAP_C` |
| Hash = `MD5(password \|\| salt)` | Hash = `MD5(pass \|\| salt)` |

By hex-encoding the wordlist and prepending `CHAP_I`, each candidate becomes the correct iSCSI CHAP password format.

---

## 📝 Info

This tool is provided for **authorized security testing and research** only. Always ensure you have permission to test target systems.

---

## 🙏 Credits

- Hashcat team for the excellent cracking engine
- GitHub issue #1773 contributors for the mode 10 workaround concept
