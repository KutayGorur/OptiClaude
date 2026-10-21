<#
.SYNOPSIS
  OptiClaude starter kit installer for Windows PowerShell 5.1+.

.DESCRIPTION
  Project mode (-Target): copies the lean Claude Code setup into a project:
    CLAUDE.md template, .claude/settings.json (secret-file deny rules), the log-digger and
    lesson-finder agents, the /go, /handoff and /lesson skills, the auto-lesson skill, and a
    format hook script.
    It also adds local-only files to .gitignore and *.sh line endings to .gitattributes (git repos only).
  Global mode (-Global): installs into your user folder (~/.claude):
    the status line script plus its settings entry, and the /opticlaude-setup skill
    generated from BOOTSTRAP-PROMPT.md.

  Safety rules:
    - CLAUDE.md is never overwritten. Fill it in or merge it with the bootstrap prompt.
    - settings.json is merged: permission lists are unioned and existing keys are kept.
    - Other existing files are skipped unless -Force is given. With -Force they are backed up
      to .claude/backup/<timestamp>/ (or ~/.claude/backup/<timestamp>/) before being replaced.
    - -DryRun shows what would happen without writing anything.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1 -Target C:\code\myapp
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1 -Global
#>
[CmdletBinding()]
param(
    [string]$Target,
    [switch]$Global,
    [string]$UserDir = (Join-Path $HOME '.claude'),
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Kit = $PSScriptRoot
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
$Log = New-Object System.Collections.Generic.List[string]

function Note([string]$status, [string]$path) {
    if ($DryRun) { $status = "would-$status" }
    $Log.Add(('{0,-16} {1}' -f $status, $path))
}

function Write-TextFile([string]$path, [string]$text) {
    if ($DryRun) { return }
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::WriteAllText($path, $text, $Utf8NoBom)
}

function Copy-FileSafe([string]$src, [string]$dest) {
    if ($DryRun) { return }
    $dir = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dest -Force
}

function Backup-File([string]$path, [string]$backupRoot, [string]$rel) {
    if ($DryRun) { return }
    $dest = Join-Path $backupRoot $rel
    $dir = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Copy-Item -LiteralPath $path -Destination $dest -Force
}

# File text with CR characters removed, so CRLF and LF checkouts of the same file compare equal.
function Read-Normalized([string]$path) { return ([System.IO.File]::ReadAllText($path) -replace "`r", '') }
function Test-SameContent([string]$a, [string]$b) { return ((Read-Normalized $a) -ceq (Read-Normalized $b)) }

function Read-Json([string]$path) {
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.Trim().Length -eq 0) { return New-Object PSObject }
    return $text | ConvertFrom-Json
}

# Re-indent ConvertTo-Json output (Windows PowerShell 5.1 pads it oddly) to 2 spaces.
function Format-Json([string]$json) {
    $indent = 0
    $lines = foreach ($line in ($json -split "`r?`n")) {
        $t = $line.Trim()
        if ($t.Length -eq 0) { continue }
        if ($t -match '^[\}\]]') { $indent-- }
        $t = $t -replace '^("(?:[^"\\]|\\.)*"):\s+', '$1: '
        ('  ' * [Math]::Max($indent, 0)) + $t
        if ($t -match '[\{\[]$') { $indent++ }
    }
    return (($lines -join "`n") + "`n")
}

function To-Json($obj) { return (Format-Json ($obj | ConvertTo-Json -Depth 32)) }

function Set-Prop($obj, [string]$name, $value) {
    if ($obj.PSObject.Properties[$name]) { $obj.$name = $value }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}

# Union the permission lists of a template settings file into an existing one.
# Returns the merged JSON text, or $null if nothing changed.
function Merge-Settings([string]$existingPath, [string]$templatePath) {
    $e = Read-Json $existingPath
    $t = Read-Json $templatePath
    $changed = $false
    if ($t.permissions) {
        if (-not $e.permissions) { Set-Prop $e 'permissions' (New-Object PSObject) }
        foreach ($k in @('allow', 'deny', 'ask')) {
            $tv = @(@($t.permissions.$k) | Where-Object { $_ })
            if ($tv.Count -eq 0) { continue }
            $ev = @(@($e.permissions.$k) | Where-Object { $_ })
            $add = @($tv | Where-Object { $ev -notcontains $_ })
            if ($add.Count -gt 0) {
                Set-Prop $e.permissions $k ([object[]]($ev + $add))
                $changed = $true
            }
        }
    }
    if ($changed) { return (To-Json $e) }
    return $null
}

# Append any missing lines to a text file such as .gitignore, under a short header.
function Add-Lines([string]$path, [string[]]$lines, [string]$label) {
    $existing = @()
    $text = ''
    if (Test-Path -LiteralPath $path) {
        $text = [System.IO.File]::ReadAllText($path)
        $existing = $text -split "`r?`n"
    }
    $missing = @($lines | Where-Object { $existing -notcontains $_ })
    if ($missing.Count -eq 0) { Note 'unchanged' $label; return }
    $prefix = ''
    if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $prefix = "`n" }
    $block = $prefix + "# Claude Code (OptiClaude starter kit)`n" + (($missing -join "`n") + "`n")
    if (-not $DryRun) { [System.IO.File]::AppendAllText($path, $block, $Utf8NoBom) }
    Note 'appended' ("$label (+" + $missing.Count + ' lines)')
}

# ---------------------------------------------------------------- project mode
function Install-Project([string]$targetDir) {
    if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) { throw "Target folder not found: $targetDir" }
    $targetFull = (Resolve-Path -LiteralPath $targetDir).Path
    $tplRoot = Join-Path $Kit 'templates\project'
    $backupRoot = Join-Path $targetFull ".claude\backup\$Stamp"
    $Log.Add("Project: $targetFull")

    Get-ChildItem -LiteralPath $tplRoot -Recurse -File -Force | ForEach-Object {
        $rel = $_.FullName.Substring($tplRoot.Length).TrimStart('\', '/')
        # Stored as CLAUDE.template.md so Claude Code doesn't load it as instructions inside this repo.
        if ($rel -eq 'CLAUDE.template.md') { $rel = 'CLAUDE.md' }
        $relShown = $rel -replace '\\', '/'
        $dest = Join-Path $targetFull $rel
        if (-not (Test-Path -LiteralPath $dest)) {
            Copy-FileSafe $_.FullName $dest
            Note 'created' $relShown
        }
        elseif ($relShown -eq 'CLAUDE.md') {
            Note 'kept' 'CLAUDE.md (exists: merge it with the bootstrap prompt)'
        }
        elseif ($relShown -eq '.claude/settings.json') {
            $merged = Merge-Settings $dest $_.FullName
            if ($null -eq $merged) { Note 'unchanged' $relShown }
            else {
                Backup-File $dest $backupRoot $rel
                Write-TextFile $dest $merged
                Note 'merged' "$relShown (backup in .claude/backup/$Stamp)"
            }
        }
        elseif (Test-SameContent $dest $_.FullName) {
            Note 'unchanged' $relShown
        }
        elseif ($Force) {
            Backup-File $dest $backupRoot $rel
            Copy-FileSafe $_.FullName $dest
            Note 'replaced' "$relShown (backup in .claude/backup/$Stamp)"
        }
        else {
            Note 'skipped' "$relShown (exists; use -Force to replace)"
        }
    }

    if (Test-Path -LiteralPath (Join-Path $targetFull '.git')) {
        Add-Lines (Join-Path $targetFull '.gitignore') @('.claude/settings.local.json', '.claude/handoff.md', '.claude/backup/') '.gitignore'
        Add-Lines (Join-Path $targetFull '.gitattributes') @('.claude/**/*.sh text eol=lf') '.gitattributes'
    }
    else {
        $Log.Add('note             not a git repo: skipped .gitignore and .gitattributes')
    }
}

# ---------------------------------------------------------------- global mode
function Install-Global([string]$userDir) {
    $userFull = [System.IO.Path]::GetFullPath($userDir)
    $backupRoot = Join-Path $userFull "backup\opticlaude-$Stamp"
    $Log.Add("User folder: $userFull")

    # 1. Status line script
    $slSrc = Join-Path $Kit 'templates\user\statusline.ps1'
    $slDest = Join-Path $userFull 'statusline.ps1'
    if (-not (Test-Path -LiteralPath $slDest)) { Copy-FileSafe $slSrc $slDest; Note 'created' 'statusline.ps1' }
    elseif (Test-SameContent $slDest $slSrc) { Note 'unchanged' 'statusline.ps1' }
    elseif ($Force) { Backup-File $slDest $backupRoot 'statusline.ps1'; Copy-FileSafe $slSrc $slDest; Note 'replaced' 'statusline.ps1' }
    else { Note 'skipped' 'statusline.ps1 (exists; use -Force to replace)' }

    # 2. statusLine entry in the user's settings.json
    $settingsPath = Join-Path $userFull 'settings.json'
    $slCommand = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + ($slDest -replace '\\', '/') + '"'
    $entry = [pscustomobject]@{ type = 'command'; command = $slCommand; padding = 0 }
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        $obj = New-Object PSObject
        Set-Prop $obj 'statusLine' $entry
        Write-TextFile $settingsPath (To-Json $obj)
        Note 'created' 'settings.json (statusLine)'
    }
    else {
        $obj = Read-Json $settingsPath
        if ($obj.statusLine -and $obj.statusLine.command -eq $slCommand) {
            Note 'unchanged' 'settings.json (statusLine)'
        }
        elseif ($obj.statusLine -and -not $Force) {
            Note 'skipped' 'settings.json statusLine (you already have one; use -Force to replace)'
        }
        else {
            Backup-File $settingsPath $backupRoot 'settings.json'
            Set-Prop $obj 'statusLine' $entry
            Write-TextFile $settingsPath (To-Json $obj)
            Note 'merged' "settings.json (statusLine; backup in backup/opticlaude-$Stamp)"
        }
    }

    # 3. /opticlaude-setup skill, generated from BOOTSTRAP-PROMPT.md
    $promptFile = Join-Path $Kit 'BOOTSTRAP-PROMPT.md'
    $all = [System.IO.File]::ReadAllText($promptFile)
    $m = [regex]::Match($all, '(?s)<!-- PROMPT START -->\r?\n(.*?)<!-- PROMPT END -->')
    if (-not $m.Success) { throw "Prompt markers not found in $promptFile" }
    $kitFwd = ($Kit -replace '\\', '/')
    $body = [regex]::Replace($m.Groups[1].Value, '(?m)^Kit folder: .*$', "Kit folder: $kitFwd")
    $skill = "---`nname: opticlaude-setup`ndescription: Set up the current project with the OptiClaude starter kit (lean CLAUDE.md, permissions, /go /handoff /lesson skills, format hook).`ndisable-model-invocation: true`n---`n" + ($body -replace "`r`n", "`n")
    $skillDest = Join-Path $userFull 'skills\opticlaude-setup\SKILL.md'
    if (-not (Test-Path -LiteralPath $skillDest)) { Write-TextFile $skillDest $skill; Note 'created' 'skills/opticlaude-setup/SKILL.md' }
    elseif ((Read-Normalized $skillDest) -ceq ($skill -replace "`r", '')) { Note 'unchanged' 'skills/opticlaude-setup/SKILL.md' }
    else {
        Backup-File $skillDest $backupRoot 'skills\opticlaude-setup\SKILL.md'
        Write-TextFile $skillDest $skill
        Note 'updated' 'skills/opticlaude-setup/SKILL.md (regenerated from BOOTSTRAP-PROMPT.md)'
    }
}

# ---------------------------------------------------------------- main
if (-not $Target -and -not $Global) { $Target = (Get-Location).Path }
if ($Global) { Install-Global $UserDir }
if ($Target) { Install-Project $Target }

Write-Output ''
Write-Output ('OptiClaude starter kit' + $(if ($DryRun) { ' (dry run: nothing was written)' } else { '' }))
$Log | ForEach-Object { Write-Output "  $_" }
Write-Output ''
if ($Target) { Write-Output 'Next: in a Claude Code session in that project, run /opticlaude-setup (or paste BOOTSTRAP-PROMPT.md) to fill in CLAUDE.md, permissions and the format hook.' }
if ($Global) { Write-Output 'Restart Claude Code (or start a new session) to see the status line and the /opticlaude-setup skill.' }
