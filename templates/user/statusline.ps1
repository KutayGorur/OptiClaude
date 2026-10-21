# Claude Code status line for Windows PowerShell 5.1+.
# Claude Code pipes session JSON to stdin. This prints one line:
#   folder | model (effort) | ctx % and tokens | session cost | cache hit % | 5-hour limit %
# The context figure is green below 200k tokens, yellow below 350k, and red above that.
# Quality starts to drop at roughly 300-400k on 1M-context models.
$ErrorActionPreference = 'SilentlyContinue'
$raw = [Console]::In.ReadToEnd()
try { $d = $raw | ConvertFrom-Json } catch { Write-Output 'statusline: bad JSON'; exit 0 }
$esc = [char]27
function Paint([string]$code, [string]$text) { return "$esc[${code}m$text$esc[0m" }

$parts = New-Object System.Collections.Generic.List[string]

$dirPath = $d.workspace.current_dir
if (-not $dirPath) { $dirPath = $d.cwd }
if ($dirPath) { $parts.Add((Split-Path -Leaf $dirPath)) }

$model = [string]$d.model.display_name
if ($d.effort.level) { $model = "$model ($($d.effort.level))" }
if ($model) { $parts.Add($model) }

$pct = $d.context_window.used_percentage
$size = $d.context_window.context_window_size
if ($null -ne $pct -and "$pct" -ne '') {
    $pctNum = [double]$pct
    $label = 'ctx {0:N0}%' -f $pctNum
    $color = '32'
    if ($size) {
        $used = $pctNum * [double]$size / 100
        $label = '{0} {1:N0}k' -f $label, ($used / 1000)
        if ($used -ge 350000) { $color = '31' } elseif ($used -ge 200000) { $color = '33' }
    } elseif ($pctNum -ge 80) { $color = '31' } elseif ($pctNum -ge 50) { $color = '33' }
    $parts.Add((Paint $color $label))
}

$cost = $d.cost.total_cost_usd
if ($null -ne $cost -and "$cost" -ne '') {
    $parts.Add(('${0:N2}' -f [double]$cost))
}

$hit = $d.prompt_cache.hit_ratio
if ($null -ne $hit -and "$hit" -ne '' -and $d.prompt_cache.caching_observed -ne $false) {
    $parts.Add(('cache {0:N0}%' -f ([double]$hit * 100)))
}

$five = $d.rate_limits.five_hour.used_percentage
if ($null -ne $five -and "$five" -ne '') {
    $parts.Add(('5h {0:N0}%' -f [double]$five))
}

Write-Output ($parts -join ' | ')
