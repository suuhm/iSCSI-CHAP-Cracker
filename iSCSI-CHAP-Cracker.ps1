#requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

<#
.SYNOPSIS
    iSCSI CHAP Cracker - Professional GUI for Hashcat Mode 10 workaround.
    (c) 2026 by suuhm - https://github.com/suuhm
.DESCRIPTION
    Tabbed dark-themed interface for converting iSCSI CHAP captures to Hashcat
    mode 10 format, cracking, and managing results.
#>

$script:cleanI      = ""
$script:cleanC      = ""
$script:cleanR      = ""
$script:hashFile    = ""
$script:hexWordlist = ""
$script:hashcatExe  = ""
$script:hashcatProcess = $null

$theme = @{
    BG_DARK       = [System.Drawing.Color]::FromArgb(28, 28, 36)
    BG_PANEL      = [System.Drawing.Color]::FromArgb(38, 38, 48)
    BG_INPUT      = [System.Drawing.Color]::FromArgb(48, 48, 62)
    BG_CARD       = [System.Drawing.Color]::FromArgb(42, 42, 55)
    ACCENT        = [System.Drawing.Color]::FromArgb(0, 160, 220)
    ACCENT_HOVER  = [System.Drawing.Color]::FromArgb(0, 200, 255)
    SUCCESS       = [System.Drawing.Color]::FromArgb(46, 180, 100)
    SUCCESS_HOVER = [System.Drawing.Color]::FromArgb(60, 220, 130)
    WARNING       = [System.Drawing.Color]::FromArgb(255, 180, 50)
    DANGER        = [System.Drawing.Color]::FromArgb(220, 70, 70)
    DANGER_HOVER  = [System.Drawing.Color]::FromArgb(255, 90, 90)
    TEXT_PRIMARY  = [System.Drawing.Color]::FromArgb(235, 235, 245)
    TEXT_SECONDARY= [System.Drawing.Color]::FromArgb(170, 170, 190)
    HEADER_BG     = [System.Drawing.Color]::FromArgb(20, 20, 30)
    BANNER_START  = [System.Drawing.Color]::FromArgb(15, 25, 45)
    BANNER_END    = [System.Drawing.Color]::FromArgb(25, 40, 70)
}


function Clean-Hex($inputStr) {
    $cleaned = ($inputStr -replace "0x", "" -replace "0X", "" -replace " ", "" -replace ":", "").ToLower()
    if ($cleaned.Length -eq 1) {
        $cleaned = "0" + $cleaned
    }
    return $cleaned
}

function Show-Error($msg) {
    [System.Windows.Forms.MessageBox]::Show($msg, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    Log("ERROR: $msg")
}

function Show-Info($msg) {
    [System.Windows.Forms.MessageBox]::Show($msg, "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    Log("SUCCESS: $msg")
}

function Log($msg) {
    $timestamp = Get-Date -Format "HH:mm:ss"
    $txtLog.AppendText("$timestamp  $msg`r`n")
    $txtLog.ScrollToCaret()
}

function Find-HashcatExe($hintPath) {
    if (Test-Path $hintPath) { return (Resolve-Path $hintPath).Path }
    $inPath = Get-Command "hashcat.exe" -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }
    $candidates = @(
        "C:\hashcat\hashcat.exe",
        "C:\Tools\hashcat\hashcat.exe",
        "$env:USERPROFILE\hashcat\hashcat.exe",
        "$env:LOCALAPPDATA\hashcat\hashcat.exe",
        ".\hashcat.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    return $null
}

function Decode-ResultFile($filePath) {
    if (-not (Test-Path $filePath)) { return $null }
    $lines = [System.IO.File]::ReadAllLines($filePath)
    foreach ($line in $lines) {
        if ($line -match '\$HEX\[([0-9a-fA-F]+)\]') {
            $fullHex = $matches[1]
            $idLen = $script:cleanI.Length
            if ($fullHex.Length -gt $idLen) {
                $passHex = $fullHex.Substring($idLen)
                $byteCount = $passHex.Length / 2
                $passBytes = New-Object byte[] $byteCount
                for ($i = 0; $i -lt $passHex.Length; $i += 2) {
                    $passBytes[$i/2] = [Convert]::ToByte($passHex.Substring($i, 2), 16)
                }
                $ascii = [System.Text.Encoding]::ASCII.GetString($passBytes).TrimEnd("`0")
                return $ascii
            }
        }
    }
    return $null
}

function Refresh-CrackedList() {
    $listCracked.Items.Clear()
    $files = @()
    if (Test-Path (Join-Path $txtOutCfg.Text "cracked.txt")) {
        $files += Join-Path $txtOutCfg.Text "cracked.txt"
    }
    if (Test-Path (Join-Path $txtOutCfg.Text "hashcat.potfile")) {
        $files += Join-Path $txtOutCfg.Text "hashcat.potfile"
    }
    $hashcatPath = Find-HashcatExe $txtHashcatCfg.Text
    if ($hashcatPath) {
        $pot = Join-Path (Split-Path $hashcatPath -Parent) "hashcat.potfile"
        if (Test-Path $pot) { $files += $pot }
    }

    $seen = @{}
    foreach ($f in $files | Select-Object -Unique) {
        $lines = [System.IO.File]::ReadAllLines($f)
        foreach ($line in $lines) {
            if ($line -match '\$HEX\[([0-9a-fA-F]+)\]') {
                $fullHex = $matches[1]
                if ($fullHex.Length -gt 2) {
                    $passHex = $fullHex.Substring(2)
                    $byteCount = $passHex.Length / 2
                    $passBytes = New-Object byte[] $byteCount
                    for ($i = 0; $i -lt $passHex.Length; $i += 2) {
                        $passBytes[$i/2] = [Convert]::ToByte($passHex.Substring($i, 2), 16)
                    }
                    $ascii = [System.Text.Encoding]::ASCII.GetString($passBytes).TrimEnd("`0")
                    if (-not $seen.ContainsKey($ascii)) {
                        $seen[$ascii] = $true
                        [void]$listCracked.Items.Add($ascii)
                    }
                }
            }
        }
    }
    $lblCrackedCount.Text = "Found: $($listCracked.Items.Count) password(s)"
}

# ============================================================================
# MAIN FORM
# ============================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "iSCSI CHAP Cracker"
$form.Size = New-Object System.Drawing.Size(1100, 850)
$form.MinimumSize = New-Object System.Drawing.Size(1000, 750)
$form.StartPosition = "CenterScreen"
$form.BackColor = $theme.BG_DARK
$form.MaximizeBox = $false
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle

$BANNER_HEIGHT = 130
$STATUS_HEIGHT = 24
$ACCENT_HEIGHT = 8

# --- Banner Panel (absolute position at top, NO Dock) ---
$banner = New-Object System.Windows.Forms.Panel
$banner.Location = New-Object System.Drawing.Point(0, 0)
$banner.Size = New-Object System.Drawing.Size(1100, 170)
$banner.BackColor = $theme.BANNER_START
$form.Controls.Add($banner)

# Banner accent line
$bannerLine = New-Object System.Windows.Forms.Panel
$bannerLine.Location = New-Object System.Drawing.Point(0, 128)
$bannerLine.Size = New-Object System.Drawing.Size(1100, 8)
$bannerLine.BackColor = $theme.ACCENT
$banner.Controls.Add($bannerLine)

$lblAsciiLogo = New-Object System.Windows.Forms.Label
$lblAsciiLogo.Location = New-Object System.Drawing.Point(24, 8)
$lblAsciiLogo.Size = New-Object System.Drawing.Size(800, 92)
$lblAsciiLogo.Font = New-Object System.Drawing.Font("Consolas", 8, [System.Drawing.FontStyle]::Bold)
$lblAsciiLogo.ForeColor = $theme.ACCENT
$lblAsciiLogo.BackColor = [System.Drawing.Color]::Transparent
 $logoLines = @(
    "██╗███████╗ ██████╗███████╗██╗     ██████╗██╗  ██╗ █████╗ ██████╗     ██████╗██████╗  █████╗  ██████╗██╗  ██╗███████╗██████╗          ",
    "██║██╔════╝██╔════╝██╔════╝██║    ██╔════╝██║  ██║██╔══██╗██╔══██╗   ██╔════╝██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗         ",
    "██║███████╗██║     ███████╗██║    ██║     ███████║███████║██████╔╝   ██║     ██████╔╝███████║██║     █████╔╝ █████╗  ██████╔╝         ",
    "██║╚════██║██║     ╚════██║██║    ██║     ██╔══██║██╔══██║██╔═══╝    ██║     ██╔══██╗██╔══██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗         ",
    "██║███████║╚██████╗███████║██║    ╚██████╗██║  ██║██║  ██║██║        ╚██████╗██║  ██║██║  ██║╚██████╗██║  ██╗███████╗██║  ██║         ",
    "╚═╝╚══════╝ ╚═════╝╚══════╝╚═╝     ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  v.0.5  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝         ",
    "                                                                                                                                      "
)
$lblAsciiLogo.Text = $logoLines -join [System.Environment]::NewLine
$banner.Controls.Add($lblAsciiLogo)

$lblBannerSub = New-Object System.Windows.Forms.Label
$lblBannerSub.Text = "Hashcat Mode 10 Workaround  |  Long Challenge Support  |  Auto-Decode | (c) 2026 by suuhm - https://github.com/suuhm"
$lblBannerSub.Location = New-Object System.Drawing.Point(16, 98)
$lblBannerSub.Size = New-Object System.Drawing.Size(900, 28)
$lblBannerSub.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$lblBannerSub.ForeColor = $theme.TEXT_SECONDARY
$lblBannerSub.BackColor = [System.Drawing.Color]::Transparent
$banner.Controls.Add($lblBannerSub)

$splitY = $BANNER_HEIGHT
$splitH = $form.ClientSize.Height - $BANNER_HEIGHT - $STATUS_HEIGHT

$splitMain = New-Object System.Windows.Forms.SplitContainer
$splitMain.Location = New-Object System.Drawing.Point(0, $splitY)
$splitMain.Size = New-Object System.Drawing.Size($form.ClientSize.Width, $splitH)
$splitMain.Orientation = [System.Windows.Forms.Orientation]::Horizontal
$splitMain.SplitterDistance = 460
$splitMain.IsSplitterFixed = $false
$form.Controls.Add($splitMain)

$form.Add_Resize({
    $banner.Size = New-Object System.Drawing.Size($form.ClientSize.Width, $BANNER_HEIGHT)
    $bannerLine.Size = New-Object System.Drawing.Size($form.ClientSize.Width, $ACCENT_HEIGHT)
    $splitMain.Location = New-Object System.Drawing.Point(0, $BANNER_HEIGHT)
    $splitMain.Size = New-Object System.Drawing.Size($form.ClientSize.Width, ($form.ClientSize.Height - $BANNER_HEIGHT - $STATUS_HEIGHT))
})

# ============================================================================
# TOP PANEL: TAB CONTROL
# ============================================================================
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabControl.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$tabControl.BackColor = $theme.BG_DARK
$splitMain.Panel1.Controls.Add($tabControl)

function New-TabPage($text) {
    $tp = New-Object System.Windows.Forms.TabPage
    $tp.Text = "  $text  "
    $tp.BackColor = $theme.BG_DARK
    $tp.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    return $tp
}

$tabCrack = New-TabPage "Generate & Crack"
$tabManage = New-TabPage "Manage Cracked"
$tabConfig = New-TabPage "Configuration"
$tabAbout = New-TabPage "About"
[void]$tabControl.Controls.Add($tabCrack)
[void]$tabControl.Controls.Add($tabManage)
[void]$tabControl.Controls.Add($tabConfig)
[void]$tabControl.Controls.Add($tabAbout)

# ============================================================================
# TAB 1: GENERATE & CRACK
# ============================================================================

# CHAP Inputs
$grpChap = New-Object System.Windows.Forms.GroupBox
$grpChap.Text = " CHAP Capture Data "
$grpChap.Location = New-Object System.Drawing.Point(14, 10)
$grpChap.Size = New-Object System.Drawing.Size(170, 130)
$grpChap.Anchor = "Top, Left, Right"
$grpChap.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$grpChap.ForeColor = $theme.TEXT_SECONDARY
$grpChap.BackColor = $theme.BG_PANEL
$tabCrack.Controls.Add($grpChap)

$lblI = New-Object System.Windows.Forms.Label
$lblI.Text = "CHAP_I (Identifier):"
$lblI.Location = New-Object System.Drawing.Point(15, 28)
$lblI.Size = New-Object System.Drawing.Size(140, 24)
$lblI.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblI.ForeColor = $theme.TEXT_PRIMARY
$grpChap.Controls.Add($lblI)

$txtI = New-Object System.Windows.Forms.TextBox
$txtI.Location = New-Object System.Drawing.Point(160, 26)
$txtI.Size = New-Object System.Drawing.Size(80, 24)
$txtI.Font = New-Object System.Drawing.Font("Consolas", 10)
$txtI.Text = ""
$txtI.BackColor = $theme.BG_INPUT
$txtI.ForeColor = $theme.TEXT_PRIMARY
$txtI.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$grpChap.Controls.Add($txtI)

$lblC = New-Object System.Windows.Forms.Label
$lblC.Text = "CHAP_C (Challenge):"
$lblC.Location = New-Object System.Drawing.Point(15, 58)
$lblC.Size = New-Object System.Drawing.Size(140, 24)
$lblC.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblC.ForeColor = $theme.TEXT_PRIMARY
$grpChap.Controls.Add($lblC)

$txtC = New-Object System.Windows.Forms.TextBox
$txtC.Location = New-Object System.Drawing.Point(160, 56)
$txtC.Size = New-Object System.Drawing.Size(860, 24)
$txtC.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtC.ScrollBars = [System.Windows.Forms.ScrollBars]::Horizontal
$txtC.Text = ""
$txtC.BackColor = $theme.BG_INPUT
$txtC.ForeColor = $theme.TEXT_PRIMARY
$txtC.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$grpChap.Controls.Add($txtC)

$lblR = New-Object System.Windows.Forms.Label
$lblR.Text = "CHAP_R (Response):"
$lblR.Location = New-Object System.Drawing.Point(15, 88)
$lblR.Size = New-Object System.Drawing.Size(140, 24)
$lblR.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblR.ForeColor = $theme.TEXT_PRIMARY
$grpChap.Controls.Add($lblR)

$txtR = New-Object System.Windows.Forms.TextBox
$txtR.Location = New-Object System.Drawing.Point(160, 86)
$txtR.Size = New-Object System.Drawing.Size(860, 24)
$txtR.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtR.ScrollBars = [System.Windows.Forms.ScrollBars]::Horizontal
$txtR.Text = ""
$txtR.BackColor = $theme.BG_INPUT
$txtR.ForeColor = $theme.TEXT_PRIMARY
$txtR.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$grpChap.Controls.Add($txtR)

$grpWord = New-Object System.Windows.Forms.GroupBox
$grpWord.Text = " Wordlist & Options "
$grpWord.Location = New-Object System.Drawing.Point(14, 148)
$grpWord.Size = New-Object System.Drawing.Size(700, 100)
$grpWord.Anchor = "Top, Left"
$grpWord.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$grpWord.ForeColor = $theme.TEXT_SECONDARY
$grpWord.BackColor = $theme.BG_PANEL
$tabCrack.Controls.Add($grpWord)

$lblWordlist = New-Object System.Windows.Forms.Label
$lblWordlist.Text = "Wordlist:"
$lblWordlist.Location = New-Object System.Drawing.Point(15, 28)
$lblWordlist.Size = New-Object System.Drawing.Size(80, 24)
$lblWordlist.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblWordlist.ForeColor = $theme.TEXT_PRIMARY
$grpWord.Controls.Add($lblWordlist)

$txtWordlist = New-Object System.Windows.Forms.TextBox
$txtWordlist.Location = New-Object System.Drawing.Point(100, 26)
$txtWordlist.Size = New-Object System.Drawing.Size(480, 24)
$txtWordlist.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$txtWordlist.ReadOnly = $true
$txtWordlist.BackColor = $theme.BG_INPUT
$txtWordlist.ForeColor = $theme.TEXT_PRIMARY
$txtWordlist.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$grpWord.Controls.Add($txtWordlist)

$btnBrowseWordlist = New-Object System.Windows.Forms.Button
$btnBrowseWordlist.Text = "Browse..."
$btnBrowseWordlist.Location = New-Object System.Drawing.Point(590, 24)
$btnBrowseWordlist.Size = New-Object System.Drawing.Size(90, 26)
$btnBrowseWordlist.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnBrowseWordlist.BackColor = $theme.BG_CARD
$btnBrowseWordlist.ForeColor = $theme.TEXT_PRIMARY
$btnBrowseWordlist.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowseWordlist.FlatAppearance.BorderSize = 0
$btnBrowseWordlist.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnBrowseWordlist.Tag = $theme.BG_CARD
$btnBrowseWordlist.Add_MouseEnter({ $this.BackColor = $theme.ACCENT })
$btnBrowseWordlist.Add_MouseLeave({ $this.BackColor = $this.Tag })
$btnBrowseWordlist.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
    $dlg.Title = "Select Wordlist"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtWordlist.Text = $dlg.FileName
    }
})
$grpWord.Controls.Add($btnBrowseWordlist)

$lblEnc = New-Object System.Windows.Forms.Label
$lblEnc.Text = "Encoding:"
$lblEnc.Location = New-Object System.Drawing.Point(15, 60)
$lblEnc.Size = New-Object System.Drawing.Size(80, 24)
$lblEnc.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblEnc.ForeColor = $theme.TEXT_PRIMARY
$grpWord.Controls.Add($lblEnc)

$cmbEnc = New-Object System.Windows.Forms.ComboBox
$cmbEnc.Location = New-Object System.Drawing.Point(100, 58)
$cmbEnc.Size = New-Object System.Drawing.Size(130, 24)
$cmbEnc.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$cmbEnc.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbEnc.BackColor = $theme.BG_INPUT
$cmbEnc.ForeColor = $theme.TEXT_PRIMARY
$cmbEnc.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
[void]$cmbEnc.Items.Add("ASCII")
[void]$cmbEnc.Items.Add("UTF8")
[void]$cmbEnc.Items.Add("UTF16LE")
$cmbEnc.SelectedIndex = 0
$grpWord.Controls.Add($cmbEnc)

$chkPad = New-Object System.Windows.Forms.CheckBox
$chkPad.Text = "Null-pad passwords to 16 bytes"
$chkPad.Location = New-Object System.Drawing.Point(250, 60)
$chkPad.Size = New-Object System.Drawing.Size(260, 24)
$chkPad.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$chkPad.ForeColor = $theme.TEXT_SECONDARY
$chkPad.BackColor = [System.Drawing.Color]::Transparent
$grpWord.Controls.Add($chkPad)

$grpResult = New-Object System.Windows.Forms.GroupBox
$grpResult.Text = " Recovered Password "
$grpResult.Location = New-Object System.Drawing.Point(730, 148)
$grpResult.Size = New-Object System.Drawing.Size(340, 100)
$grpResult.Anchor = "Top, Left"
$grpResult.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$grpResult.ForeColor = $theme.TEXT_SECONDARY
$grpResult.BackColor = $theme.BG_PANEL
$tabCrack.Controls.Add($grpResult)

$txtResult = New-Object System.Windows.Forms.TextBox
$txtResult.Location = New-Object System.Drawing.Point(12, 24)
$txtResult.Size = New-Object System.Drawing.Size(200, 36)
$txtResult.Font = New-Object System.Drawing.Font("Consolas", 14, [System.Drawing.FontStyle]::Bold)
$txtResult.ReadOnly = $true
$txtResult.BackColor = $theme.BG_DARK
$txtResult.ForeColor = $theme.TEXT_SECONDARY
$txtResult.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtResult.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center
$txtResult.Text = "Waiting..."
$grpResult.Controls.Add($txtResult)

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = "Copy to Clipboard"
$btnCopy.Location = New-Object System.Drawing.Point(12, 66)
$btnCopy.Size = New-Object System.Drawing.Size(200, 26)
$btnCopy.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnCopy.BackColor = $theme.ACCENT
$btnCopy.ForeColor = [System.Drawing.Color]::White
$btnCopy.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCopy.FlatAppearance.BorderSize = 0
$btnCopy.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnCopy.Tag = $theme.ACCENT
$btnCopy.Add_MouseEnter({ $this.BackColor = $theme.ACCENT_HOVER })
$btnCopy.Add_MouseLeave({ $this.BackColor = $this.Tag })
$btnCopy.Add_Click({
    if ($txtResult.Text -and $txtResult.Text -ne "Waiting..." -and $txtResult.Text -ne "Not found yet") {
        [System.Windows.Forms.Clipboard]::SetText($txtResult.Text)
        Log("[+] Password copied to clipboard: $($txtResult.Text)")
    }
})
$grpResult.Controls.Add($btnCopy)

$grpActions = New-Object System.Windows.Forms.GroupBox
$grpActions.Text = " Actions "
$grpActions.Location = New-Object System.Drawing.Point(14, 256)
$grpActions.Size = New-Object System.Drawing.Size(170, 70)
$grpActions.Anchor = "Top, Left, Right"
$grpActions.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$grpActions.ForeColor = $theme.TEXT_SECONDARY
$grpActions.BackColor = $theme.BG_PANEL
$tabCrack.Controls.Add($grpActions)

$btnGenerate = New-Object System.Windows.Forms.Button
$btnGenerate.Text = "GENERATE FILES"
$btnGenerate.Location = New-Object System.Drawing.Point(15, 24)
$btnGenerate.Size = New-Object System.Drawing.Size(150, 34)
$btnGenerate.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnGenerate.BackColor = $theme.SUCCESS
$btnGenerate.ForeColor = [System.Drawing.Color]::White
$btnGenerate.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnGenerate.FlatAppearance.BorderSize = 0
$btnGenerate.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnGenerate.Tag = $theme.SUCCESS
$btnGenerate.Add_MouseEnter({ $this.BackColor = $theme.SUCCESS_HOVER })
$btnGenerate.Add_MouseLeave({ $this.BackColor = $this.Tag })
$grpActions.Controls.Add($btnGenerate)

$btnDelPot = New-Object System.Windows.Forms.Button
$btnDelPot.Text = "DELETE POTFILE"
$btnDelPot.Location = New-Object System.Drawing.Point(180, 24)
$btnDelPot.Size = New-Object System.Drawing.Size(140, 34)
$btnDelPot.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnDelPot.BackColor = $theme.DANGER
$btnDelPot.ForeColor = [System.Drawing.Color]::White
$btnDelPot.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnDelPot.FlatAppearance.BorderSize = 0
$btnDelPot.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnDelPot.Tag = $theme.DANGER
$btnDelPot.Add_MouseEnter({ $this.BackColor = $theme.DANGER_HOVER })
$btnDelPot.Add_MouseLeave({ $this.BackColor = $this.Tag })
$grpActions.Controls.Add($btnDelPot)

$chkAutoDelPot = New-Object System.Windows.Forms.CheckBox
$chkAutoDelPot.Text = "Auto-delete before run"
$chkAutoDelPot.Location = New-Object System.Drawing.Point(335, 30)
$chkAutoDelPot.Size = New-Object System.Drawing.Size(170, 24)
$chkAutoDelPot.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$chkAutoDelPot.ForeColor = $theme.TEXT_SECONDARY
$chkAutoDelPot.BackColor = [System.Drawing.Color]::Transparent
$chkAutoDelPot.Checked = $true
$grpActions.Controls.Add($chkAutoDelPot)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "RUN HASHCAT"
$btnRun.Location = New-Object System.Drawing.Point(520, 24)
$btnRun.Size = New-Object System.Drawing.Size(140, 34)
$btnRun.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnRun.BackColor = $theme.ACCENT
$btnRun.ForeColor = [System.Drawing.Color]::White
$btnRun.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRun.FlatAppearance.BorderSize = 0
$btnRun.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnRun.Tag = $theme.ACCENT
$btnRun.Add_MouseEnter({ $this.BackColor = $theme.ACCENT_HOVER })
$btnRun.Add_MouseLeave({ $this.BackColor = $this.Tag })
$btnRun.Enabled = $false
$grpActions.Controls.Add($btnRun)

$btnDecode = New-Object System.Windows.Forms.Button
$btnDecode.Text = "DECODE"
$btnDecode.Location = New-Object System.Drawing.Point(680, 24)
$btnDecode.Size = New-Object System.Drawing.Size(100, 34)
$btnDecode.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnDecode.BackColor = $theme.WARNING
$btnDecode.ForeColor = [System.Drawing.Color]::Black
$btnDecode.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnDecode.FlatAppearance.BorderSize = 0
$btnDecode.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnDecode.Tag = $theme.WARNING
$btnDecode.Add_MouseEnter({ $this.BackColor = [System.Drawing.Color]::FromArgb(255, 210, 80) })
$btnDecode.Add_MouseLeave({ $this.BackColor = $this.Tag })
$btnDecode.Enabled = $false
$grpActions.Controls.Add($btnDecode)

$chkAutoDecode = New-Object System.Windows.Forms.CheckBox
$chkAutoDecode.Text = "Auto-decode after run"
$chkAutoDecode.Location = New-Object System.Drawing.Point(795, 30)
$chkAutoDecode.Size = New-Object System.Drawing.Size(170, 24)
$chkAutoDecode.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$chkAutoDecode.ForeColor = $theme.TEXT_SECONDARY
$chkAutoDecode.BackColor = [System.Drawing.Color]::Transparent
$chkAutoDecode.Checked = $true
$grpActions.Controls.Add($chkAutoDecode)

$lblCmdHeader = New-Object System.Windows.Forms.Label
$lblCmdHeader.Text = " Generated Command"
$lblCmdHeader.Location = New-Object System.Drawing.Point(14, 334)
$lblCmdHeader.Size = New-Object System.Drawing.Size(200, 20)
$lblCmdHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblCmdHeader.ForeColor = $theme.TEXT_SECONDARY
$tabCrack.Controls.Add($lblCmdHeader)

$txtCmd = New-Object System.Windows.Forms.TextBox
$txtCmd.Location = New-Object System.Drawing.Point(14, 356)
$txtCmd.Size = New-Object System.Drawing.Size(180, 62)
$txtCmd.Multiline = $true
$txtCmd.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtCmd.ReadOnly = $true
$txtCmd.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtCmd.BackColor = $theme.BG_DARK
$txtCmd.ForeColor = [System.Drawing.Color]::FromArgb(100, 220, 150)
$txtCmd.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtCmd.Anchor = "Top, Left, Right"
$tabCrack.Controls.Add($txtCmd)

# ============================================================================
# TAB 2: MANAGE CRACKED
# ============================================================================

$lblCrackedHeader = New-Object System.Windows.Forms.Label
$lblCrackedHeader.Text = "Previously Cracked Passwords"
$lblCrackedHeader.Location = New-Object System.Drawing.Point(20, 15)
$lblCrackedHeader.Size = New-Object System.Drawing.Size(400, 30)
$lblCrackedHeader.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$lblCrackedHeader.ForeColor = $theme.TEXT_PRIMARY
$tabManage.Controls.Add($lblCrackedHeader)

$listCracked = New-Object System.Windows.Forms.ListBox
$listCracked.Location = New-Object System.Drawing.Point(20, 50)
$listCracked.Size = New-Object System.Drawing.Size(500, 340)
$listCracked.Font = New-Object System.Drawing.Font("Consolas", 11)
$listCracked.BackColor = $theme.BG_INPUT
$listCracked.ForeColor = $theme.TEXT_PRIMARY
$listCracked.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$listCracked.HorizontalScrollbar = $true
$listCracked.Anchor = "Top, Left"
$tabManage.Controls.Add($listCracked)

$lblCrackedCount = New-Object System.Windows.Forms.Label
$lblCrackedCount.Text = "Found: 0 password(s)"
$lblCrackedCount.Location = New-Object System.Drawing.Point(20, 395)
$lblCrackedCount.Size = New-Object System.Drawing.Size(300, 24)
$lblCrackedCount.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblCrackedCount.ForeColor = $theme.TEXT_SECONDARY
$tabManage.Controls.Add($lblCrackedCount)

$btnRefreshList = New-Object System.Windows.Forms.Button
$btnRefreshList.Text = "Refresh List"
$btnRefreshList.Location = New-Object System.Drawing.Point(740, 50)
$btnRefreshList.Size = New-Object System.Drawing.Size(140, 36)
$btnRefreshList.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnRefreshList.BackColor = $theme.ACCENT
$btnRefreshList.ForeColor = [System.Drawing.Color]::White
$btnRefreshList.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRefreshList.FlatAppearance.BorderSize = 0
$btnRefreshList.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnRefreshList.Tag = $theme.ACCENT
$btnRefreshList.Add_MouseEnter({ $this.BackColor = $theme.ACCENT_HOVER })
$btnRefreshList.Add_MouseLeave({ $this.BackColor = $this.Tag })
$btnRefreshList.Add_Click({ Refresh-CrackedList })
$tabManage.Controls.Add($btnRefreshList)

$btnExportList = New-Object System.Windows.Forms.Button
$btnExportList.Text = "Export to File"
$btnExportList.Location = New-Object System.Drawing.Point(740, 96)
$btnExportList.Size = New-Object System.Drawing.Size(140, 36)
$btnExportList.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnExportList.BackColor = $theme.BG_CARD
$btnExportList.ForeColor = $theme.TEXT_PRIMARY
$btnExportList.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnExportList.FlatAppearance.BorderSize = 0
$btnExportList.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnExportList.Tag = $theme.BG_CARD
$btnExportList.Add_MouseEnter({ $this.BackColor = $theme.ACCENT })
$btnExportList.Add_MouseLeave({ $this.BackColor = $this.Tag })
$btnExportList.Add_Click({
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "Text files (*.txt)|*.txt"
    $sfd.FileName = "cracked_passwords.txt"
    if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $items = $listCracked.Items | ForEach-Object { $_ }
        [System.IO.File]::WriteAllLines($sfd.FileName, $items)
        Log("[+] Exported $($items.Count) passwords to: $($sfd.FileName)")
    }
})
$tabManage.Controls.Add($btnExportList)

$btnClearList = New-Object System.Windows.Forms.Button
$btnClearList.Text = "Clear All"
$btnClearList.Location = New-Object System.Drawing.Point(740, 142)
$btnClearList.Size = New-Object System.Drawing.Size(140, 36)
$btnClearList.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnClearList.BackColor = $theme.DANGER
$btnClearList.ForeColor = [System.Drawing.Color]::White
$btnClearList.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClearList.FlatAppearance.BorderSize = 0
$btnClearList.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClearList.Tag = $theme.DANGER
$btnClearList.Add_MouseEnter({ $this.BackColor = $theme.DANGER_HOVER })
$btnClearList.Add_MouseLeave({ $this.BackColor = $this.Tag })
$btnClearList.Add_Click({
    $result = [System.Windows.Forms.MessageBox]::Show("Delete all potfiles and cracked.txt?`n`nThis cannot be undone.", "Confirm Delete", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        $btnDelPot.PerformClick()
        $listCracked.Items.Clear()
        $lblCrackedCount.Text = "Found: 0 password(s)"
    }
})
$tabManage.Controls.Add($btnClearList)

# ============================================================================
# TAB 3: CONFIGURATION
# ============================================================================

$grpCfgPaths = New-Object System.Windows.Forms.GroupBox
$grpCfgPaths.Text = " Paths "
$grpCfgPaths.Location = New-Object System.Drawing.Point(20, 15)
$grpCfgPaths.Size = New-Object System.Drawing.Size(700, 120)
$grpCfgPaths.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$grpCfgPaths.ForeColor = $theme.TEXT_SECONDARY
$grpCfgPaths.BackColor = $theme.BG_PANEL
$tabConfig.Controls.Add($grpCfgPaths)

$lblHashcatCfg = New-Object System.Windows.Forms.Label
$lblHashcatCfg.Text = "Hashcat .exe:"
$lblHashcatCfg.Location = New-Object System.Drawing.Point(15, 28)
$lblHashcatCfg.Size = New-Object System.Drawing.Size(100, 24)
$lblHashcatCfg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblHashcatCfg.ForeColor = $theme.TEXT_PRIMARY
$grpCfgPaths.Controls.Add($lblHashcatCfg)

$txtHashcatCfg = New-Object System.Windows.Forms.TextBox
$txtHashcatCfg.Location = New-Object System.Drawing.Point(120, 26)
$txtHashcatCfg.Size = New-Object System.Drawing.Size(480, 24)
$txtHashcatCfg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$txtHashcatCfg.Text = "hashcat.exe"
$txtHashcatCfg.BackColor = $theme.BG_INPUT
$txtHashcatCfg.ForeColor = $theme.TEXT_PRIMARY
$txtHashcatCfg.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$grpCfgPaths.Controls.Add($txtHashcatCfg)

$btnBrowseHashcatCfg = New-Object System.Windows.Forms.Button
$btnBrowseHashcatCfg.Text = "Browse..."
$btnBrowseHashcatCfg.Location = New-Object System.Drawing.Point(610, 24)
$btnBrowseHashcatCfg.Size = New-Object System.Drawing.Size(70, 26)
$btnBrowseHashcatCfg.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnBrowseHashcatCfg.BackColor = $theme.BG_CARD
$btnBrowseHashcatCfg.ForeColor = $theme.TEXT_PRIMARY
$btnBrowseHashcatCfg.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowseHashcatCfg.FlatAppearance.BorderSize = 0
$btnBrowseHashcatCfg.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnBrowseHashcatCfg.Tag = $theme.BG_CARD
$btnBrowseHashcatCfg.Add_MouseEnter({ $this.BackColor = $theme.ACCENT })
$btnBrowseHashcatCfg.Add_MouseLeave({ $this.BackColor = $this.Tag })
$btnBrowseHashcatCfg.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Executable (*.exe)|*.exe"
    $dlg.Title = "Select hashcat.exe"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtHashcatCfg.Text = $dlg.FileName
    }
})
$grpCfgPaths.Controls.Add($btnBrowseHashcatCfg)

$lblOutCfg = New-Object System.Windows.Forms.Label
$lblOutCfg.Text = "Output Dir:"
$lblOutCfg.Location = New-Object System.Drawing.Point(15, 64)
$lblOutCfg.Size = New-Object System.Drawing.Size(100, 24)
$lblOutCfg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblOutCfg.ForeColor = $theme.TEXT_PRIMARY
$grpCfgPaths.Controls.Add($lblOutCfg)

$txtOutCfg = New-Object System.Windows.Forms.TextBox
$txtOutCfg.Location = New-Object System.Drawing.Point(120, 62)
$txtOutCfg.Size = New-Object System.Drawing.Size(480, 24)
$txtOutCfg.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$txtOutCfg.Text = (Get-Location).Path
$txtOutCfg.BackColor = $theme.BG_INPUT
$txtOutCfg.ForeColor = $theme.TEXT_PRIMARY
$txtOutCfg.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$grpCfgPaths.Controls.Add($txtOutCfg)

$btnBrowseOutCfg = New-Object System.Windows.Forms.Button
$btnBrowseOutCfg.Text = "Browse..."
$btnBrowseOutCfg.Location = New-Object System.Drawing.Point(610, 60)
$btnBrowseOutCfg.Size = New-Object System.Drawing.Size(70, 26)
$btnBrowseOutCfg.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnBrowseOutCfg.BackColor = $theme.BG_CARD
$btnBrowseOutCfg.ForeColor = $theme.TEXT_PRIMARY
$btnBrowseOutCfg.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowseOutCfg.FlatAppearance.BorderSize = 0
$btnBrowseOutCfg.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnBrowseOutCfg.Tag = $theme.BG_CARD
$btnBrowseOutCfg.Add_MouseEnter({ $this.BackColor = $theme.ACCENT })
$btnBrowseOutCfg.Add_MouseLeave({ $this.BackColor = $this.Tag })
$btnBrowseOutCfg.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Select Output Directory"
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtOutCfg.Text = $fbd.SelectedPath
    }
})
$grpCfgPaths.Controls.Add($btnBrowseOutCfg)

# 
$grpDefaults = New-Object System.Windows.Forms.GroupBox
$grpDefaults.Text = " Defaults "
$grpDefaults.Location = New-Object System.Drawing.Point(20, 150)
$grpDefaults.Size = New-Object System.Drawing.Size(700, 150)
$grpDefaults.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$grpDefaults.ForeColor = $theme.TEXT_SECONDARY
$grpDefaults.BackColor = $theme.BG_PANEL
$tabConfig.Controls.Add($grpDefaults)

$lblDefEnc = New-Object System.Windows.Forms.Label
$lblDefEnc.Text = "Default Encoding:"
$lblDefEnc.Location = New-Object System.Drawing.Point(15, 28)
$lblDefEnc.Size = New-Object System.Drawing.Size(120, 24)
$lblDefEnc.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblDefEnc.ForeColor = $theme.TEXT_PRIMARY
$grpDefaults.Controls.Add($lblDefEnc)

$cmbDefEnc = New-Object System.Windows.Forms.ComboBox
$cmbDefEnc.Location = New-Object System.Drawing.Point(145, 26)
$cmbDefEnc.Size = New-Object System.Drawing.Size(150, 24)
$cmbDefEnc.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$cmbDefEnc.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbDefEnc.BackColor = $theme.BG_INPUT
$cmbDefEnc.ForeColor = $theme.TEXT_PRIMARY
$cmbDefEnc.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
[void]$cmbDefEnc.Items.Add("ASCII")
[void]$cmbDefEnc.Items.Add("UTF8")
[void]$cmbDefEnc.Items.Add("UTF16LE")
$cmbDefEnc.SelectedIndex = 0
$grpDefaults.Controls.Add($cmbDefEnc)

$chkDefPad = New-Object System.Windows.Forms.CheckBox
$chkDefPad.Text = "Default: Null-pad passwords to 16 bytes"
$chkDefPad.Location = New-Object System.Drawing.Point(15, 58)
$chkDefPad.Size = New-Object System.Drawing.Size(300, 24)
$chkDefPad.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$chkDefPad.ForeColor = $theme.TEXT_SECONDARY
$chkDefPad.BackColor = [System.Drawing.Color]::Transparent
$grpDefaults.Controls.Add($chkDefPad)

$chkDefAutoDel = New-Object System.Windows.Forms.CheckBox
$chkDefAutoDel.Text = "Default: Auto-delete potfile before run"
$chkDefAutoDel.Location = New-Object System.Drawing.Point(15, 86)
$chkDefAutoDel.Size = New-Object System.Drawing.Size(300, 24)
$chkDefAutoDel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$chkDefAutoDel.ForeColor = $theme.TEXT_SECONDARY
$chkDefAutoDel.BackColor = [System.Drawing.Color]::Transparent
$chkDefAutoDel.Checked = $true
$grpDefaults.Controls.Add($chkDefAutoDel)

$chkDefAutoDec = New-Object System.Windows.Forms.CheckBox
$chkDefAutoDec.Text = "Default: Auto-decode after run"
$chkDefAutoDec.Location = New-Object System.Drawing.Point(15, 114)
$chkDefAutoDec.Size = New-Object System.Drawing.Size(300, 24)
$chkDefAutoDec.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$chkDefAutoDec.ForeColor = $theme.TEXT_SECONDARY
$chkDefAutoDec.BackColor = [System.Drawing.Color]::Transparent
$chkDefAutoDec.Checked = $true
$grpDefaults.Controls.Add($chkDefAutoDec)

$btnApplyCfg = New-Object System.Windows.Forms.Button
$btnApplyCfg.Text = "Apply to Main Tab"
$btnApplyCfg.Location = New-Object System.Drawing.Point(350, 26)
$btnApplyCfg.Size = New-Object System.Drawing.Size(150, 32)
$btnApplyCfg.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnApplyCfg.BackColor = $theme.SUCCESS
$btnApplyCfg.ForeColor = [System.Drawing.Color]::White
$btnApplyCfg.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnApplyCfg.FlatAppearance.BorderSize = 0
$btnApplyCfg.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnApplyCfg.Tag = $theme.SUCCESS
$btnApplyCfg.Add_MouseEnter({ $this.BackColor = $theme.SUCCESS_HOVER })
$btnApplyCfg.Add_MouseLeave({ $this.BackColor = $this.Tag })
$btnApplyCfg.Add_Click({
    $cmbEnc.SelectedIndex = $cmbDefEnc.SelectedIndex
    $chkPad.Checked = $chkDefPad.Checked
    $chkAutoDelPot.Checked = $chkDefAutoDel.Checked
    $chkAutoDecode.Checked = $chkDefAutoDec.Checked
    Log("[+] Configuration applied to Generate & Crack tab.")
})
$grpDefaults.Controls.Add($btnApplyCfg)

# ============================================================================
# TAB 4: ABOUT
# ============================================================================

$lblAboutTitle = New-Object System.Windows.Forms.Label
$lblAboutTitle.Text = "iSCSI CHAP Cracker v6.0"
$lblAboutTitle.Location = New-Object System.Drawing.Point(20, 15)
$lblAboutTitle.Size = New-Object System.Drawing.Size(500, 36)
$lblAboutTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$lblAboutTitle.ForeColor = $theme.TEXT_PRIMARY
$tabAbout.Controls.Add($lblAboutTitle)

$txtAbout = New-Object System.Windows.Forms.TextBox
$txtAbout.Location = New-Object System.Drawing.Point(20, 55)
$txtAbout.Size = New-Object System.Drawing.Size(160, 40)
$txtAbout.Multiline = $true
$txtAbout.ReadOnly = $true
$txtAbout.Font = New-Object System.Drawing.Font("Consolas", 10)
$txtAbout.BackColor = $theme.BG_INPUT
$txtAbout.ForeColor = $theme.TEXT_SECONDARY
$txtAbout.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtAbout.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtAbout.WordWrap = $true
$txtAbout.Anchor = "Top, Left, Right, Bottom"

$aboutLines = @(
    "iSCSI CHAP Cracker v0.5 (c) 2026 by suuhm"
    "========================================="
    ""
    "This tool automates the workaround for Hashcat's mode 4800 limitation,"
    "which only supports 16-byte CHAP challenges. Many Linux iSCSI targets"
    "(TGT/LIO) generate longer challenges (64+ bytes), causing a Token Length"
    "Exception in standard mode 4800."
    ""
    "HOW IT WORKS"
    "------------"
    "The tool converts your iSCSI CHAP capture into Hashcat mode 10 format:"
    "    MD5(password || salt)"
    "Where:"
    "    password = CHAP_I + your_word"
    "    salt     = CHAP_C (the full challenge)"
    ""
    "The wordlist is hex-encoded and the CHAP_I identifier is prepended to"
    "each candidate, allowing Hashcat to compute the correct iSCSI CHAP"
    "response hash."
    ""
    "TABS"
    "----"
    "Generate & Crack    - Paste capture data, select wordlist, run Hashcat"
    "Manage Cracked      - View, export, and clear previously cracked passwords"
    "Configuration       - Set default paths, encoding, and behavior options"
    ""
    "IMPORTANT"
    "---------"
    "  - Do NOT use -O (optimized kernel). Long salts require the pure kernel."
    "  - UTF16LE wordlists (e.g., rockyou_utf16.txt) are auto-converted to ASCII."
    "  - Enable Null-pad if your target pads passwords to 16 bytes with 0x00."
    ""
    "GitHub Issue: https://github.com/hashcat/hashcat/issues/1773"
)

$txtAbout.Text = $aboutLines -join [System.Environment]::NewLine
$tabAbout.Controls.Add($txtAbout)

# ============================================================================
# BOTTOM PANEL: LOG
# ============================================================================

$logHeader = New-Object System.Windows.Forms.Panel
$logHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$logHeader.Height = 26
$logHeader.BackColor = $theme.BG_PANEL
$splitMain.Panel2.Controls.Add($logHeader)

$lblLogHeader = New-Object System.Windows.Forms.Label
$lblLogHeader.Text = "  Log Output"
$lblLogHeader.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblLogHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblLogHeader.ForeColor = $theme.TEXT_SECONDARY
$lblLogHeader.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$logHeader.Controls.Add($lblLogHeader)

$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtLog.Multiline = $true
$txtLog.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.BackColor = $theme.BG_DARK
$txtLog.ForeColor = $theme.TEXT_PRIMARY
$txtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$splitMain.Panel2.Controls.Add($txtLog)

$status = New-Object System.Windows.Forms.StatusStrip
$status.Dock = [System.Windows.Forms.DockStyle]::Bottom
$status.BackColor = $theme.HEADER_BG
$status.Height = $STATUS_HEIGHT
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = " Ready"
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$statusLabel.ForeColor = $theme.TEXT_SECONDARY
[void]$status.Items.Add($statusLabel)
$form.Controls.Add($status)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    if ($script:hashcatProcess -ne $null) {
        if ($script:hashcatProcess.HasExited) {
            $timer.Stop()
            Log("[*] Hashcat process has exited.")
            $statusLabel.Text = " Ready"
            $script:hashcatProcess = $null
            if ($chkAutoDecode.Checked) {
                Start-Sleep -Milliseconds 600
                $btnDecode.PerformClick()
            }
            Refresh-CrackedList
        } else {
            $statusLabel.Text = " Hashcat running..."
        }
    }
})

# ============================================================================
# TOOLTIPS
# ============================================================================
$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.BackColor = $theme.BG_PANEL
$toolTip.ForeColor = $theme.TEXT_PRIMARY
$toolTip.AutoPopDelay = 10000
$toolTip.SetToolTip($txtI, "CHAP Identifier from capture. Usually 1, 2, etc. Paste with or without 0x.")
$toolTip.SetToolTip($txtC, "Full CHAP Challenge hex string from capture. Can be very long (64+ bytes).")
$toolTip.SetToolTip($txtR, "CHAP Response hash. Must be exactly 32 hex chars (16-byte MD5).")
$toolTip.SetToolTip($chkPad, "Some iSCSI targets pad passwords to 16 bytes with null bytes (0x00) before hashing.")
$toolTip.SetToolTip($cmbEnc, "ASCII/UTF8 for plain text wordlists. UTF16LE for wordlists like rockyou_utf16.txt.")
$toolTip.SetToolTip($btnCopy, "Copy recovered password to clipboard")

# ============================================================================
# EVENT HANDLERS
# ============================================================================

$btnGenerate.Add_Click({
    $txtLog.Clear()
    $txtCmd.Clear()
    $txtResult.Text = "Waiting..."
    $txtResult.ForeColor = $theme.TEXT_SECONDARY
    $btnRun.Enabled = $false
    $btnDecode.Enabled = $false

    if ([string]::IsNullOrWhiteSpace($txtI.Text))     { Show-Error "CHAP_I is required."; return }
    if ([string]::IsNullOrWhiteSpace($txtC.Text))     { Show-Error "CHAP_C is required."; return }
    if ([string]::IsNullOrWhiteSpace($txtR.Text))     { Show-Error "CHAP_R is required."; return }
    if ([string]::IsNullOrWhiteSpace($txtWordlist.Text)) { Show-Error "Please select a wordlist."; return }
    if (-not (Test-Path $txtWordlist.Text))           { Show-Error "Wordlist file not found."; return }
    if (-not (Test-Path $txtOutCfg.Text))              { Show-Error "Output directory not found."; return }

    $script:cleanI = Clean-Hex $txtI.Text
    $script:cleanC = Clean-Hex $txtC.Text
    $script:cleanR = Clean-Hex $txtR.Text

    Log("Cleaned CHAP_I : $script:cleanI")
    Log("Cleaned CHAP_C : $($script:cleanC.Substring(0,[Math]::Min(32,$script:cleanC.Length)))... ($($script:cleanC.Length) hex chars = $($script:cleanC.Length/2) bytes)")
    Log("Cleaned CHAP_R : $script:cleanR")

    if ($script:cleanC.Length % 2 -ne 0) { Show-Error "CHAP_C has odd length after cleaning (invalid hex)."; return }
    if ($script:cleanR.Length -ne 32)    { Show-Error "CHAP_R must be exactly 32 hex chars (16 bytes MD5). Got $($script:cleanR.Length)."; return }

    $script:hashFile = Join-Path $txtOutCfg.Text "hash.txt"
    "$($script:cleanR):$($script:cleanC)" | Set-Content -Path $script:hashFile -NoNewline -Encoding ASCII
    Log("[+] Hash file created: $($script:hashFile)")

    $script:hexWordlist = Join-Path $txtOutCfg.Text "wordlist_hex.txt"
    $encoding = $cmbEnc.SelectedItem
    $pad = $chkPad.Checked

    switch ($encoding) {
        "ASCII"    { $enc = [System.Text.Encoding]::ASCII }
        "UTF8"     { $enc = [System.Text.Encoding]::UTF8 }
        "UTF16LE"  { $enc = [System.Text.Encoding]::Unicode }
    }

    Log("Encoding: $encoding | Null-pad to 16: $pad")
    Log("Processing wordlist...")

    if ($encoding -eq "UTF16LE") {
        $reader = [System.IO.StreamReader]::new($txtWordlist.Text, [System.Text.Encoding]::Unicode)
    } else {
        $reader = [System.IO.StreamReader]::new($txtWordlist.Text, $enc)
    }

    $out = [System.IO.StreamWriter]::new($script:hexWordlist)
    $count = 0

    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($encoding -eq "UTF16LE") {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
            } else {
                $bytes = $enc.GetBytes($line)
            }

            if ($pad) {
                $padded = New-Object byte[] 16
                [Array]::Copy($bytes, $padded, [Math]::Min($bytes.Length, 16))
                $bytes = $padded
            }

            $hex = $script:cleanI + [System.BitConverter]::ToString($bytes).Replace("-", "").ToLower()
            $out.WriteLine($hex)
            $count++

            if ($count % 10000 -eq 0) {
                $statusLabel.Text = " Processing... $count lines"
                [System.Windows.Forms.Application]::DoEvents()
            }
        }
    } finally {
        $reader.Close()
        $out.Close()
    }

    $statusLabel.Text = " Ready"
    Log("[+] Hex wordlist created: $($script:hexWordlist)")
    Log("    Total lines processed: $count")

    $cmdLine = "hashcat.exe -m 10 -a 0 --hex-wordlist --hex-salt `"$($script:hashFile)`" `"$($script:hexWordlist)`" -o cracked.txt --force"
    $notes = @"

IMPORTANT NOTES:
  1. Do NOT add -O (optimized kernel). Salt is $($script:cleanC.Length/2) bytes.
  2. Add -w 3 for maximum GPU workload.
  3. Add --potfile-disable if you do NOT want to save to hashcat.potfile.
  4. Cracked passwords saved to: $($txtOutCfg.Text)\cracked.txt
  5. Click [Decode Result] after Hashcat finishes to convert `$HEX[] to ASCII.
"@

    $txtCmd.Text = $cmdLine + $notes
    $btnRun.Enabled = $true
    $btnDecode.Enabled = $true

    Show-Info "Files generated!`n`nHash: $($script:hashFile)`nWordlist: $($script:hexWordlist)`n`nClick 'Run Hashcat' to start."
})

$btnDelPot.Add_Click({
    $paths = @()
    if (-not [string]::IsNullOrWhiteSpace($txtOutCfg.Text)) {
        $paths += Join-Path $txtOutCfg.Text "hashcat.potfile"
        $paths += Join-Path $txtOutCfg.Text "cracked.txt"
    }
    $hashcatPath = Find-HashcatExe $txtHashcatCfg.Text
    if ($hashcatPath) {
        $parent = Split-Path $hashcatPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            $paths += Join-Path $parent "hashcat.potfile"
        }
    }

    $deleted = 0
    foreach ($p in $paths | Select-Object -Unique) {
        if (Test-Path $p) {
            Remove-Item $p -Force
            Log("[-] Deleted: $(Split-Path $p -Leaf)")
            $deleted++
        }
    }
    if ($deleted -eq 0) {
        Log("[i] No potfile or cracked.txt found to delete.")
    } else {
        Log("[+] Deleted $deleted file(s).")
    }
    $txtResult.Text = "Waiting..."
    $txtResult.ForeColor = $theme.TEXT_SECONDARY
    Refresh-CrackedList
})

$btnRun.Add_Click({
    $script:hashcatExe = Find-HashcatExe $txtHashcatCfg.Text
    if (-not $script:hashcatExe) {
        Show-Error "hashcat.exe not found.`n`nBrowse to the correct path in Configuration tab or ensure hashcat folder is in your PATH."
        return
    }
    Log("[*] Resolved Hashcat: $(Split-Path $script:hashcatExe -Leaf)")

    if ($chkAutoDelPot.Checked) {
        $btnDelPot.PerformClick()
    }

    if (-not (Test-Path $script:hashFile) -or -not (Test-Path $script:hexWordlist)) {
        Show-Error "Generated files not found. Click 'Generate Files' first."
        return
    }

    $outDir = $txtOutCfg.Text
    $crackedOut = Join-Path $outDir "cracked.txt"
    $argList = @(
        "-m","10",
        "-a","0",
        "--hex-wordlist",
        "--hex-salt",
        $script:hashFile,
        $script:hexWordlist,
        "-o", $crackedOut,
        "--force"
    )

    Log("[*] Launching Hashcat...")
    Log("    Command: hashcat.exe $($argList -join ' ')")

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:hashcatExe
    $psi.Arguments = $argList -join " "
    $psi.WorkingDirectory = $outDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $false

    $script:hashcatProcess = [System.Diagnostics.Process]::Start($psi)
    $timer.Start()
    $statusLabel.Text = " Hashcat running..."
})

$btnDecode.Add_Click({
    $crackedFile = Join-Path $txtOutCfg.Text "cracked.txt"
    $potFile    = Join-Path $txtOutCfg.Text "hashcat.potfile"
    $password = $null

    if (Test-Path $crackedFile) {
        $password = Decode-ResultFile $crackedFile
        if ($password) { Log("[+] Found result in cracked.txt") }
    }
    if (-not $password -and (Test-Path $potFile)) {
        $password = Decode-ResultFile $potFile
        if ($password) { Log("[+] Found result in hashcat.potfile (output dir)") }
    }
    if (-not $password -and $script:hashcatExe) {
        $hcDir = Split-Path $script:hashcatExe -Parent
        if (-not [string]::IsNullOrWhiteSpace($hcDir)) {
            $potFile2 = Join-Path $hcDir "hashcat.potfile"
            if (Test-Path $potFile2) {
                $password = Decode-ResultFile $potFile2
                if ($password) { Log("[+] Found result in hashcat.potfile (hashcat dir)") }
            }
        }
    }
    if (-not $password) {
        $hcPath = Find-HashcatExe $txtHashcatCfg.Text
        if ($hcPath) {
            $hcDir = Split-Path $hcPath -Parent
            if (-not [string]::IsNullOrWhiteSpace($hcDir)) {
                $potFile3 = Join-Path $hcDir "hashcat.potfile"
                if (Test-Path $potFile3) {
                    $password = Decode-ResultFile $potFile3
                    if ($password) { Log("[+] Found result in hashcat.potfile (configured dir)") }
                }
            }
        }
    }

    if ($password) {
        $txtResult.Text = $password
        $txtResult.ForeColor = [System.Drawing.Color]::FromArgb(100, 255, 150)
        Log("[+] DECODED PASSWORD:  $password")
        Log("[+] HEX:  $([System.BitConverter]::ToString([System.Text.Encoding]::ASCII.GetBytes($password)).Replace('-',' '))")
    } else {
        $txtResult.Text = "Not found yet"
        $txtResult.ForeColor = $theme.WARNING
        Log("[!] No password found. Hashcat may still be running or password not in wordlist.")
    }
})

[void]$form.ShowDialog()
