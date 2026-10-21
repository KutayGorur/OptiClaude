# Tests for setup.ps1 and statusline.ps1 (Windows PowerShell 5.1 or PowerShell 7).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tests/test.ps1   (exit code 1 if any check fails)
# If Git Bash is available, it also checks that setup.ps1 and setup.sh produce identical results.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Fix = Join-Path $PSScriptRoot 'fixtures'
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('opticlaude-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp | Out-Null
$PS = (Get-Process -Id $PID).Path   # run setup.ps1 with the same PowerShell that runs the tests
$script:Pass = 0; $script:Fail = 0

function Check([string]$name, [scriptblock]$test) {
    $ok = $false
    try { $ok = [bool](& $test) } catch { $ok = $false }
    if ($ok) { $script:Pass++; Write-Output "  ok    $name" } else { $script:Fail++; Write-Output "  FAIL  $name" }
}
function Setup { & $PS -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'setup.ps1') @args | Out-String }
function Snapshot([string]$dir) {
    Get-ChildItem -LiteralPath $dir -Recurse -File -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
        Sort-Object FullName | ForEach-Object { $_.FullName.Substring($dir.Length) + ' ' + (Get-FileHash -LiteralPath $_.FullName).Hash }
}
function Json([string]$path) { return ([System.IO.File]::ReadAllText($path) | ConvertFrom-Json) }
# Write $src's text to $dst with the opposite line endings (CRLF <-> LF): bytes differ, text doesn't.
function Flip-Eol([string]$src, [string]$dst) {
    $t = [System.IO.File]::ReadAllText($src)
    if ($t.Contains("`r")) { $t = $t -replace "`r", '' } else { $t = $t -replace "`n", "`r`n" }
    [System.IO.File]::WriteAllText($dst, $t, (New-Object System.Text.UTF8Encoding $false))
}
function StripAnsi([string]$s) { return ($s -replace "$([char]27)\[[0-9;]*m", '').Trim() }
function StatusLine([string]$fixture) {
    return ([System.IO.File]::ReadAllText((Join-Path $Fix $fixture)) | & $PS -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'templates\user\statusline.ps1') | Out-String)
}

$files = @('CLAUDE.md', '.claude\settings.json', '.claude\agents\log-digger.md', '.claude\agents\lesson-finder.md',
    '.claude\hooks\format-edited.sh', '.claude\skills\go\SKILL.md', '.claude\skills\handoff\SKILL.md',
    '.claude\skills\lesson\SKILL.md', '.claude\skills\lesson\find-mistakes.sh', '.claude\skills\auto-lesson\SKILL.md')

try {
    Write-Output "== setup.ps1 ($PS)"

    $dry = Join-Path $Tmp 'dry'; New-Item -ItemType Directory -Path $dry | Out-Null
    Setup -Target $dry -DryRun | Out-Null
    Check 'dry run writes nothing' { @(Get-ChildItem -LiteralPath $dry -Force).Count -eq 0 }

    $fresh = Join-Path $Tmp 'fresh'; New-Item -ItemType Directory -Path $fresh | Out-Null
    Setup -Target $fresh | Out-Null
    Check "fresh project gets all $($files.Count) files" { @($files | Where-Object { -not (Test-Path -LiteralPath (Join-Path $fresh $_)) }).Count -eq 0 }
    Check 'CLAUDE.md comes from the template' { (Get-FileHash (Join-Path $fresh 'CLAUDE.md')).Hash -eq (Get-FileHash (Join-Path $Root 'templates\project\CLAUDE.template.md')).Hash }
    $before = Snapshot $fresh; $out = Setup -Target $fresh
    Check 're-run changes nothing' { (Compare-Object @(Snapshot $fresh) @($before)) -eq $null }
    Check 're-run reports nothing created' { $out -notmatch 'created' }

    # Line endings: a kit file differing only in CRLF/LF is unchanged; a real edit is skipped, or replaced with -Force
    $e = Join-Path $Tmp 'eol'; New-Item -ItemType Directory -Path $e | Out-Null
    Setup -Target $e | Out-Null
    $tplGo = Join-Path $Root 'templates\project\.claude\skills\go\SKILL.md'; $go = Join-Path $e '.claude\skills\go\SKILL.md'
    Flip-Eol $tplGo $go
    Check 'eol: precondition, file differs byte-wise' { (Get-FileHash $tplGo).Hash -ne (Get-FileHash $go).Hash }
    $out = Setup -Target $e -Force
    Check 'eol: line-ending-only difference is unchanged' { $out -match 'unchanged\s+\.claude/skills/go/SKILL\.md' }
    Check 'eol: line-ending-only file is not rewritten' { (Get-FileHash $tplGo).Hash -ne (Get-FileHash $go).Hash }
    [System.IO.File]::AppendAllText($go, "`nlocal edit`n")
    $out = Setup -Target $e
    Check 'eol: real edit is skipped without -Force' { $out -match 'skipped\s+\.claude/skills/go/SKILL\.md' }
    $out = Setup -Target $e -Force
    Check 'eol: real edit is replaced with -Force' { $out -match 'replaced\s+\.claude/skills/go/SKILL\.md' }
    Check 'eol: -Force restored the template' { (Get-FileHash $tplGo).Hash -eq (Get-FileHash $go).Hash }
    Check 'eol: -Force kept a backup of the edit' { @(Get-ChildItem (Join-Path $e '.claude\backup') -Recurse -File | Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match 'local edit' }).Count -ge 1 }

    $p = Join-Path $Tmp 'existing'; New-Item -ItemType Directory -Path (Join-Path $p '.claude') | Out-Null
    & git -C $p init -q
    [System.IO.File]::WriteAllText((Join-Path $p 'CLAUDE.md'), "# My notes`nKeep me.`n")
    [System.IO.File]::WriteAllText((Join-Path $p '.claude\settings.json'), '{"permissions":{"allow":["Bash(make test *)"],"deny":["Read(.env)"]},"model":"opus"}')
    [System.IO.File]::WriteAllText((Join-Path $p '.gitignore'), 'node_modules/')
    Setup -Target $p | Out-Null; Setup -Target $p | Out-Null
    $s = Json (Join-Path $p '.claude\settings.json')
    Check 'existing CLAUDE.md untouched' { [System.IO.File]::ReadAllText((Join-Path $p 'CLAUDE.md')) -eq "# My notes`nKeep me.`n" }
    Check 'merge keeps existing allow rule' { @($s.permissions.allow) -contains 'Bash(make test *)' }
    Check 'merge adds all template deny rules' { @($s.permissions.deny).Count -eq 6 -and @($s.permissions.deny) -contains 'Read(secrets/**)' }
    Check 'merge keeps other keys' { $s.model -eq 'opus' }
    Check 'merge wrote a backup' { @(Get-ChildItem -LiteralPath (Join-Path $p '.claude\backup') -Recurse -Filter settings.json).Count -ge 1 }
    $gi = Get-Content -LiteralPath (Join-Path $p '.gitignore')
    Check '.gitignore keeps old lines' { $gi -contains 'node_modules/' }
    Check '.gitignore gets kit lines once' { @($gi | Where-Object { $_ -eq '.claude/handoff.md' }).Count -eq 1 }
    Check '.gitattributes forces LF for .claude scripts' { (Get-Content -LiteralPath (Join-Path $p '.gitattributes')) -contains '.claude/**/*.sh text eol=lf' }

    $u = Join-Path $Tmp 'home'
    Setup -Global -UserDir $u | Out-Null
    $skill = [System.IO.File]::ReadAllText((Join-Path $u 'skills\opticlaude-setup\SKILL.md'))
    $rootFwd = $Root -replace '\\', '/'
    Check 'global: status line script installed' { Test-Path -LiteralPath (Join-Path $u 'statusline.ps1') }
    Check 'global: settings.json has statusLine' { (Json (Join-Path $u 'settings.json')).statusLine.command -like '*statusline.ps1*' }
    Check "global: skill has this kit's path" { $skill -match ('(?m)^Kit folder: ' + [regex]::Escape($rootFwd) + '\s*$') }
    Check 'global: skill has no placeholder path' { $skill -notmatch '(?m)^Kit folder: <path to this repo>' }
    Check 'global: skill is manual-only' { $skill -match '(?m)^disable-model-invocation: true' }
    # Claude Code expands $ARGUMENTS, $1 and ${VARS} in skill text when it runs, so the skill must contain no "$".
    Check 'global: skill has no $ tokens to expand' { -not $skill.Contains('$') }
    $before = Snapshot $u; Setup -Global -UserDir $u | Out-Null
    Check 'global: re-run changes nothing' { (Compare-Object @(Snapshot $u) @($before)) -eq $null }

    # Global files that differ only in line endings count as unchanged (no backup, no rewrite)
    $u3 = Join-Path $Tmp 'home-eol'
    Setup -Global -UserDir $u3 | Out-Null
    Flip-Eol (Join-Path $Root 'templates\user\statusline.ps1') (Join-Path $u3 'statusline.ps1')
    $sk = Join-Path $u3 'skills\opticlaude-setup\SKILL.md'; Flip-Eol $sk "$sk.tmp"; Move-Item -Force "$sk.tmp" $sk
    $out = Setup -Global -UserDir $u3 -Force
    Check 'global eol: status line is unchanged' { $out -match 'unchanged\s+statusline\.ps1' }
    Check 'global eol: skill is unchanged' { $out -match 'unchanged\s+skills/opticlaude-setup/SKILL\.md' }
    Check 'global eol: no backup made' { -not (Test-Path -LiteralPath (Join-Path $u3 'backup')) }

    $u2 = Join-Path $Tmp 'home2'; New-Item -ItemType Directory -Path $u2 | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $u2 'settings.json'), '{"statusLine":{"type":"command","command":"echo mine"},"theme":"dark"}')
    Setup -Global -UserDir $u2 | Out-Null
    Check 'global: existing statusLine kept' { (Json (Join-Path $u2 'settings.json')).statusLine.command -eq 'echo mine' }
    Setup -Global -UserDir $u2 -Force | Out-Null
    $s2 = Json (Join-Path $u2 'settings.json')
    Check 'global -Force: statusLine replaced' { $s2.statusLine.command -like '*statusline.ps1*' }
    Check 'global -Force: other keys kept' { $s2.theme -eq 'dark' }

    Write-Output '== statusline.ps1'
    $full = StatusLine 'session-full.json'
    Check 'full session line' { (StripAnsi $full) -eq 'myapp | Opus (high) | ctx 23% 234k | $0.41 | cache 91% | 5h 24%' }
    Check '234k is yellow' { $full.Contains("$([char]27)[33m") }
    Check 'minimal session line' { (StripAnsi (StatusLine 'session-min.json')) -eq 'proj | Sonnet' }
    $red = StatusLine 'session-red.json'
    Check '410k is red, no cache part' { (StripAnsi $red) -eq 'big | Opus | ctx 41% 410k' }
    Check 'red color code' { $red.Contains("$([char]27)[31m") }
    Check 'empty input exits cleanly' { '' | & $PS -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'templates\user\statusline.ps1') | Out-Null; $LASTEXITCODE -eq 0 }

    # Cross-check against setup.sh when Git Bash is available (avoid WSL's bash.exe).
    $bash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
    if (-not (Test-Path -LiteralPath $bash)) { $bash = $null }
    if ($bash) {
        Write-Output '== setup.ps1 vs setup.sh'
        $shProj = Join-Path $Tmp 'sh-fresh'; New-Item -ItemType Directory -Path $shProj | Out-Null
        & $bash (($Root -replace '\\', '/') + '/setup.sh') --target ($shProj -replace '\\', '/') | Out-Null
        Check 'identical project files' { (Compare-Object @(Snapshot $shProj) @(Snapshot $fresh)) -eq $null }
        $shHome = Join-Path $Tmp 'sh-home'
        & $bash (($Root -replace '\\', '/') + '/setup.sh') --global --user-dir ($shHome -replace '\\', '/') | Out-Null
        Check 'identical /opticlaude-setup skill' { (Get-FileHash (Join-Path $shHome 'skills\opticlaude-setup\SKILL.md')).Hash -eq (Get-FileHash (Join-Path $u 'skills\opticlaude-setup\SKILL.md')).Hash }
    }
    else { Write-Output '  (Git Bash not found: skipped setup.ps1 vs setup.sh comparison)' }
}
finally {
    Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ''
Write-Output "passed: $($script:Pass)  failed: $($script:Fail)"
if ($script:Fail -gt 0) { exit 1 }
