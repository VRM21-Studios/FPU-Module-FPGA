# ============================================================================
# VRM21 Studios - FPU-Module-FPGA
# ============================================================================
# Script: scripts/run_sim.ps1
# Purpose:
#   Runs every self-checking testbench of the repository with the AMD Vivado
#   simulator (xvlog / xelab / xsim) and reports PASS or FAIL per test.
# Usage (PowerShell 7, from any folder):
#   pwsh -File scripts/run_sim.ps1                     # all tests
#   pwsh -File scripts/run_sim.ps1 -Test native,axi    # selected tests
#   pwsh -File scripts/run_sim.ps1 -VivadoBin <path to Vivado bin folder>
# Vivado location, first match wins:
#   1. -VivadoBin parameter
#   2. scripts/local_settings.ps1 (not committed) setting $VivadoBin
#   3. environment variable XILINX_VIVADO (uses $env:XILINX_VIVADO/bin)
#   4. xvlog found on PATH
# Layout expected: rtl/*.v, tb/*.sv, tb/mem/*.mem. All output goes to
#   build/sim/ (ignored by Git): one log per test and summary.txt.
# Exit code: 0 when every selected test passes, 1 otherwise.
# A test passes only when its exact PASS line is printed and the log has no
# $fatal, error or FPU_ASSERT_* line.
# ============================================================================
param(
    [string[]] $Test = @(),
    [string] $VivadoBin = ''
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Build = Join-Path $Root 'build/sim'

# ---------------------------------------------------------------- tool lookup
if (-not $VivadoBin) {
    $local = Join-Path $PSScriptRoot 'local_settings.ps1'
    if (Test-Path -LiteralPath $local) { . $local }
}
if (-not $VivadoBin -and $env:XILINX_VIVADO) { $VivadoBin = Join-Path $env:XILINX_VIVADO 'bin' }
if (-not $VivadoBin) {
    $found = Get-Command xvlog -ErrorAction SilentlyContinue
    if ($found) { $VivadoBin = Split-Path -Parent $found.Source }
}
$ext = if ($IsWindows) { '.bat' } else { '' }
$Xvlog = Join-Path $VivadoBin "xvlog$ext"
$Xelab = Join-Path $VivadoBin "xelab$ext"
$Xsim = Join-Path $VivadoBin "xsim$ext"
foreach ($tool in $Xvlog, $Xelab, $Xsim) {
    if (-not (Test-Path -LiteralPath $tool)) { throw "Vivado simulator not found: $tool (use -VivadoBin)" }
}

# ---------------------------------------------------------------- test table
function Get-RecordCount([string] $mem) {
    $lines = Get-Content -LiteralPath $mem -TotalCount 2
    # Vector files start with the magic word f7540001 (kept as a string: a
    # PowerShell hex literal above 0x7fffffff is a negative Int32).
    if ($lines[0].Substring(56).ToLowerInvariant() -ne 'f7540001' -or $lines[0].Substring(0, 56) -match '[^0]') { throw "Bad vector header: $mem" }
    return [int][Convert]::ToUInt64($lines[1].Substring(48), 16)
}
function New-VectorTest([string] $name, [string] $top, [string] $mem, [string] $marker, [int] $kind = -1) {
    $path = (Join-Path $Root "tb/mem/$mem") -replace '\\', '/'
    $count = Get-RecordCount $path
    $generics = @("VECTOR_FILE=$path", "MAX_RECORDS=$count")
    if ($kind -ge 0) { $generics += "KIND=$kind" }
    return [pscustomobject]@{ Name = $name; Top = $top; Generics = $generics; Pass = ($marker -f $count) }
}
$tests = @(
    (New-VectorTest 'native'      'tb_vrm_fpu_native_64'   'integration_smoke.mem' 'QUAL_SUMMARY,{0},0'),
    (New-VectorTest 'axi'         'tb_vrm_fpu_axi_64'      'integration_smoke.mem' 'AXI_SUMMARY,1527,4323,0'),
    (New-VectorTest 'conv'        'tb_vrm_fpu_lanes_64'    'conv.mem'              'QUAL_SUMMARY,{0},0' 0),
    (New-VectorTest 'misc'        'tb_vrm_fpu_lanes_64'    'misc.mem'              'QUAL_SUMMARY,{0},0' 1),
    (New-VectorTest 'mul'         'tb_vrm_fpu_lanes_64'    'mul.mem'               'QUAL_SUMMARY,{0},0' 2),
    (New-VectorTest 'add_sub'     'tb_vrm_fpu_arith_64'    'add_sub.mem'           'QUAL_SUMMARY,{0},0' 3),
    (New-VectorTest 'div'         'tb_vrm_fpu_arith_64'    'div.mem'               'QUAL_SUMMARY,{0},0' 4),
    (New-VectorTest 'sqrt'        'tb_vrm_fpu_arith_64'    'sqrt.mem'              'QUAL_SUMMARY,{0},0' 5),
    (New-VectorTest 'lane_stream' 'tb_vrm_fpu_lane_stream' 'lanes-0.mem'           'STREAM_SUMMARY,{0},0'),
    (New-VectorTest 'round'       'tb_vrm_fpu_round_64'    'round.mem'             'ROUND_SUMMARY,{0},0'),
    [pscustomobject]@{ Name = 'prenorm';    Top = 'tb_vrm_fpu_prenorm_64'; Generics = @(); Pass = 'PRENORM_PASS finite=4196 specials=3' },
    [pscustomobject]@{ Name = 'lane_reset'; Top = 'tb_vrm_fpu_lane_reset'; Generics = @(); Pass = 'V2_RESET_PASS modes=5 lanes=6' }
)
$Test = @($Test | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
if ($Test.Count -gt 0) {
    $unknown = $Test | Where-Object { $_ -notin $tests.Name }
    if ($unknown) { throw "Unknown test(s): $($unknown -join ', '). Known: $($tests.Name -join ', ')" }
    $tests = $tests | Where-Object { $_.Name -in $Test }
}

# ---------------------------------------------------------------- helpers
# Every argument is quoted in a generated command file so that the simulator
# batch wrappers keep "NAME=value" generics and paths with spaces intact.
function Invoke-Tool([string] $tool, [string[]] $arguments, [string] $logFile) {
    $quoted = ($arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    if ($IsWindows) {
        $cmdFile = Join-Path $Build '_invoke.cmd'
        Set-Content -LiteralPath $cmdFile -Encoding ascii -Value @(
            '@echo off',
            ('call "' + $tool + '" ' + $quoted + ' > "' + $logFile + '" 2>&1'),
            'exit /b %ERRORLEVEL%')
        & $env:ComSpec /d /c "`"$cmdFile`""
    } else {
        $shFile = Join-Path $Build '_invoke.sh'
        Set-Content -LiteralPath $shFile -Value ('"' + $tool + '" ' + $quoted + ' > "' + $logFile + '" 2>&1')
        & /bin/sh $shFile
    }
    return $LASTEXITCODE
}

# ---------------------------------------------------------------- compile
New-Item -ItemType Directory -Force -Path $Build | Out-Null
Push-Location $Build
try {
    $rtl = Get-ChildItem -LiteralPath (Join-Path $Root 'rtl') -Filter '*.v' | Sort-Object Name | ForEach-Object { $_.FullName -replace '\\', '/' }
    $tbs = Get-ChildItem -LiteralPath (Join-Path $Root 'tb') -Filter '*.sv' | Sort-Object Name | ForEach-Object { $_.FullName -replace '\\', '/' }
    Write-Host "Compiling $($rtl.Count) RTL files (Verilog) and $($tbs.Count) testbenches (SystemVerilog)..."
    if ((Invoke-Tool $Xvlog (@('--nolog') + $rtl) (Join-Path $Build 'compile_rtl.log')) -ne 0) { throw 'RTL compile failed, see build/sim/compile_rtl.log' }
    if ((Invoke-Tool $Xvlog (@('--nolog', '--sv') + $tbs) (Join-Path $Build 'compile_tb.log')) -ne 0) { throw 'Testbench compile failed, see build/sim/compile_tb.log' }

    # ------------------------------------------------------------ run
    $results = @()
    foreach ($t in $tests) {
        $snapshot = "snap_$($t.Name)"
        $log = Join-Path $Build "$($t.Name).log"
        $elab = @('--nolog', '--debug', 'off', '--snapshot', $snapshot)
        foreach ($g in $t.Generics) { $elab += @('-generic_top', $g) }
        $elab += "work.$($t.Top)"
        $start = Get-Date
        $status = 'FAIL'
        $detail = ''
        if ((Invoke-Tool $Xelab $elab (Join-Path $Build "$($t.Name).elab.log")) -ne 0) {
            $detail = "elaboration failed ($($t.Name).elab.log)"
        } else {
            [void](Invoke-Tool $Xsim @($snapshot, '-R', '--nolog') $log)
            $text = Get-Content -LiteralPath $log -Raw
            $bad = [regex]::Match($text, '(?m)^.*(Fatal|FATAL|ERROR:|FPU_ASSERT_)\S*.*$')
            if ($bad.Success) { $detail = $bad.Value.Trim() }
            elseif ($text -notmatch [regex]::Escape($t.Pass)) { $detail = "PASS line '$($t.Pass)' not found" }
            else { $status = 'PASS'; $detail = $t.Pass }
        }
        $seconds = [int]((Get-Date) - $start).TotalSeconds
        $results += [pscustomobject]@{ Test = $t.Name; Status = $status; Seconds = $seconds; Detail = $detail }
        Write-Host ('{0,-12} {1,-4} {2,5}s  {3}' -f $t.Name, $status, $seconds, $detail)
    }
} finally {
    Pop-Location
}

# ---------------------------------------------------------------- summary
$failed = @($results | Where-Object Status -ne 'PASS').Count
$summary = @("FPU-Module-FPGA simulation summary $((Get-Date).ToString('s'))",
    ($results | Format-Table -AutoSize | Out-String).TrimEnd(),
    "TOTAL $($results.Count) tests, $failed failed")
$summary | Set-Content -LiteralPath (Join-Path $Build 'summary.txt')
Write-Host "TOTAL $($results.Count) tests, $failed failed (build/sim/summary.txt)"
exit ($(if ($failed) { 1 } else { 0 }))
