param(
    [switch]$RefreshDNA,
    [switch]$SkipGPU
)

$ErrorActionPreference = "Continue"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$Godot = "C:\Users\steph\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
$OutDir = Join-Path $RepoRoot "docs\self_review_latest"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Write-Host "=== Pootis Builder 2.0 — Automated Self-Review & Regression Gate ===" -ForegroundColor Cyan
$Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

# 1. Ensure Official Valve TF2 Design DNA exists (or refresh on request)
$DnaPath = Join-Path $RepoRoot "godot\data\tf2_design_dna.json"
if ($RefreshDNA -or -not (Test-Path $DnaPath)) {
    Write-Host "[1/4] Mining Official Valve TF2 Map DNA..." -ForegroundColor Yellow
    & $Godot --headless --path godot --script res://tools/study_tf2_maps.gd | Out-Host
}

# 2. Run ALL Automated Test Suites
Write-Host "[2/4] Running Automated Test Suites..." -ForegroundColor Yellow
$Suites = @(
    "res://tests/test_overhaul_all_phases.gd",
    "res://tests/test_milestone_30.gd",
    "res://tests/test_milestone_33_35.gd",
    "res://tests/test_milestone_37_39.gd"
)
$SuiteResults = @()
$AllPassed = $true
foreach ($s in $Suites) {
    $t0 = Get-Date
    $out = (& $Godot --headless --path godot --script $s 2>&1) -join "`n"
    $code = $LASTEXITCODE
    $dur = [math]::Round(((Get-Date) - $t0).TotalSeconds, 2)
    $ok = ($code -eq 0) -and ($out -match "0 failures")
    if (-not $ok) { $AllPassed = $false }
    $SuiteResults += [PSCustomObject]@{
        suite = $s
        passed = $ok
        exit_code = $code
        seconds = $dur
    }
    $statusTag = if ($ok) { "PASS" } else { "FAIL" }
    Write-Host ("  [{0}] {1} ({2}s)" -f $statusTag, $s, $dur) -ForegroundColor $(if ($ok) { "Green" } else { "Red" })
}

# 3. Run Performance Benchmark & Enforce Regression Budgets
Write-Host "[3/4] Running Performance Benchmarks..." -ForegroundColor Yellow
$BenchOut = (& $Godot --headless --path godot --script res://tests/bench_editor_perf.gd 2>&1) -join "`n"
$BenchOk = ($LASTEXITCODE -eq 0) -and ($BenchOut -match "ALL PASS")
if (-not $BenchOk) { $AllPassed = $false }
$BenchLines = ($BenchOut -split "`n") | Where-Object { $_ -match "\[PASS\]|Baseline" }
foreach ($bl in $BenchLines) { Write-Host $bl -ForegroundColor Gray }

# 4. Capture Fresh Live GPU Audit Screenshots (unless -SkipGPU)
$Shots = @()
if (-not $SkipGPU) {
    Write-Host "[4/4] Capturing Live GPU Self-Review Screenshots..." -ForegroundColor Yellow
    $s1 = Join-Path $OutDir "audit_fonts_arrows.png"
    $s2 = Join-Path $OutDir "audit_ai_arena_dna.png"
    & $Godot --path godot '--' --shot "v19_fonts_arrows:$s1" --shot "v20_ai_arena_dna:$s2" | Out-Null
    if (Test-Path $s1) { $Shots += $s1 }
    if (Test-Path $s2) { $Shots += $s2 }
    Write-Host ("  Captured {0} GPU audit screenshot(s) in {1}" -f $Shots.Count, $OutDir) -ForegroundColor Green
}

# Extract top 3 unchecked P0/P1 items from docs/hammer_parity_backlog.md
$BacklogPath = Join-Path $RepoRoot "docs\hammer_parity_backlog.md"
$NextItems = @()
if (Test-Path $BacklogPath) {
    $NextItems = (Get-Content $BacklogPath | Where-Object { $_ -match "^- \[ \]" } | Select-Object -First 3)
}

# Write Structured JSON & Markdown Self-Review Reports
$Report = [PSCustomObject]@{
    timestamp = $Timestamp
    overall_pass = $AllPassed
    dna_present = (Test-Path $DnaPath)
    suites = $SuiteResults
    benchmarks = $BenchLines
    gpu_screenshots = $Shots
    next_recommended_features = $NextItems
}
$JsonPath = Join-Path $OutDir "report.json"
$Report | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $JsonPath

$MdLines = @(
    "# Pootis Builder 2.0 — Self-Review Audit Report",
    "",
    "- **Timestamp:** $Timestamp",
    "- **Overall Gate:** $(if ($AllPassed) { 'PASS (0 Regressions)' } else { 'FAIL — Investigate Below' })",
    "- **Official Valve TF2 DNA Loaded:** $(Test-Path $DnaPath)",
    "",
    "## Automated Test Suites",
    "| Suite | Status | Duration |",
    "|---|---|---|"
)
foreach ($sr in $SuiteResults) {
    $MdLines += "| ``$($sr.suite)`` | $(if ($sr.passed) { 'PASS' } else { 'FAIL' }) | $($sr.seconds)s |"
}
$MdLines += @("", "## Performance Benchmarks", '```')
$MdLines += $BenchLines
$MdLines += @('```', "", "## Top Recommended Next Features (from `docs/hammer_parity_backlog.md`)")
foreach ($ni in $NextItems) { $MdLines += $ni }
$MdPath = Join-Path $OutDir "report.md"
$MdLines -join "`n" | Set-Content -Encoding UTF8 $MdPath

Write-Host "=== Self-Review Report Saved: $MdPath ===" -ForegroundColor Cyan
if (-not $AllPassed) { exit 1 } else { exit 0 }
