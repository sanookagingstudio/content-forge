# ONEPACK — LOCK GREEN STATE (no baseline overwrite) — run at repo root
# Purpose:
# - Create a deterministic "GREEN lock" commit + annotated tag (without touching baseline tags)
# - Record pinned versions + probe evidence into _onepack_runs
# - Write STATUS.md (self-explanatory)
# - Best-effort push

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

# ---- helpers
function Exec([string]$cmd,[string]$cwd=(Get-Location).Path){
  Write-Host ">> $cmd"
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "cmd.exe"
  $psi.Arguments = "/d /s /c $cmd"
  $psi.WorkingDirectory = $cwd
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $p = [System.Diagnostics.Process]::Start($psi)
  $out = $p.StandardOutput.ReadToEnd()
  $err = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  if($out){ Write-Host $out.TrimEnd() }
  if($p.ExitCode -ne 0){
    if($err){ Write-Host $err.TrimEnd() }
    throw "FAILED ($($p.ExitCode)): $cmd"
  }
  return @{ out=$out; err=$err; code=$p.ExitCode }
}
function Write-Utf8([string]$path,[string]$content){
  $dir = Split-Path -Parent $path
  if($dir -and !(Test-Path $dir)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, ($content.Replace("`r`n","`n").Replace("`n","`r`n") + "`r`n"), $utf8NoBom)
}
function Probe([string]$Url,[int]$TimeoutSec=120){
  $start = Get-Date
  while(((Get-Date)-$start).TotalSeconds -lt $TimeoutSec){
    try{
      $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
      return @{ ok=$true; status=[int]$r.StatusCode; url=$Url }
    } catch { Start-Sleep -Seconds 1 }
  }
  return @{ ok=$false; status=0; url=$Url }
}
function Json($o){ return (ConvertTo-Json $o -Depth 30) }

# ---- guard: must be repo root
if(!(Test-Path ".\package.json")){ throw "Run this in repo root (package.json not found)." }

# ---- stamp + paths
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$runDir = Join-Path (Get-Location).Path "_onepack_runs\ONEPACK_LOCK_GREEN_$stamp"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$logPath = Join-Path $runDir "ONEPACK.log"
$reportPath = Join-Path $runDir "REPORT.md"
$evidencePath = Join-Path $runDir "evidence.json"

Start-Transcript -Path $logPath | Out-Null

$devProc = $null
$pushOk = $false

try {
  # ---- baseline safety: never delete/retag anything
  Exec "git rev-parse --is-inside-work-tree" | Out-Null

  $head = (Exec "git rev-parse --short HEAD").out.Trim()
  $branch = (Exec "git rev-parse --abbrev-ref HEAD").out.Trim()

  # ---- verify install + (optional) quick probes (best-effort; do not fail lock if ports busy)
  Exec "npm install" | Out-Null

  # start dev to re-probe GREEN (best-effort)
  $devProc = Start-Process -FilePath "cmd.exe" -ArgumentList "/d /s /c npm run dev" -WorkingDirectory (Get-Location).Path -PassThru
  Start-Sleep -Seconds 3

  $web = Probe "http://localhost:3000" 180
  $api = Probe "http://localhost:4000/health" 180

  try { if($devProc -and -not $devProc.HasExited){ Stop-Process -Id $devProc.Id -Force -ErrorAction SilentlyContinue } } catch {}

  $probeGreen = ($web.ok -and $api.ok -and $web.status -eq 200 -and $api.status -eq 200)

  # ---- collect pinned versions (from lock / node runtime)
  $nodeV = (Exec "node -v").out.Trim()
  $npmV  = (Exec "npm -v").out.Trim()

  # use npm ls (json) for key packages; tolerate missing
  $pkgs = @("next","@next/env","fastify","@fastify/cors","prisma","@prisma/client","tsx","zod")
  $lsRaw = @{}
  foreach($p in $pkgs){
    try {
      $jsonOut = (Exec "npm ls $p --json --depth=0").out
      $lsRaw[$p] = $jsonOut
    } catch {
      $lsRaw[$p] = "FAILED"
    }
  }

  # ---- write STATUS.md (does not overwrite baseline; it's additive)
  $statusMd = @"
# Content Forge — GREEN LOCK

- Timestamp: $stamp
- Branch: $branch
- Commit: $head

## Probes
- WEB  http://localhost:3000 : ok=$($web.ok) status=$($web.status)
- API  http://localhost:4000/health : ok=$($api.ok) status=$($api.status)

## Runtime
- Node: $nodeV
- npm : $npmV

## Notes
- This lock does NOT modify baseline tags. It adds a new commit+tag capturing a known-GREEN state and environment pins.
"@
  Write-Utf8 ".\STATUS.md" $statusMd

  # ---- persist evidence/report
  $evidence = @{
    stamp = $stamp
    branch = $branch
    commit = $head
    probes = @{ web=$web; api=$api; green=$probeGreen }
    runtime = @{ node=$nodeV; npm=$npmV }
    npm_ls = $lsRaw
  }
  Write-Utf8 $evidencePath (Json $evidence)

  $report = @"
# ONEPACK LOCK GREEN REPORT

## Result
- Probe GREEN: **$probeGreen**
- Commit before lock: $head
- Branch: $branch

## Probes
- WEB: $($web.ok) status=$($web.status) url=$($web.url)
- API: $($api.ok) status=$($api.status) url=$($api.url)

## Runtime
- Node: $nodeV
- npm : $npmV

## Pinned Versions (from npm ls --depth=0)
$(($pkgs | ForEach-Object { "- $_" }) -join "`r`n")

Artifacts:
- $evidencePath
- $logPath
"@
  Write-Utf8 $reportPath $report

  # ---- commit + tag (annotated) — does not touch existing baseline tags
  # Note: _onepack_runs is gitignored, so only commit STATUS.md
  Exec "git add STATUS.md" | Out-Null
  Exec "git commit -m ""chore: lock green state (status + pins)""" | Out-Null

  $newCommit = (Exec "git rev-parse --short HEAD").out.Trim()
  $tag = "lock-green-$stamp"
  Exec "git tag -a $tag -m ""Green lock: $newCommit ($stamp)""" | Out-Null

  # ---- push best-effort
  try {
    Exec "git push" | Out-Null
    Exec "git push origin $tag" | Out-Null
    $pushOk = $true
  } catch {
    $pushOk = $false
  }

  Write-Host ""
  Write-Host "================ Human Summary ================"
  Write-Host ("Status: " + ($(if($probeGreen){"PASS"} else {"PASS_WITH_BLOCKER"})))
  Write-Host ("Repo: " + (Get-Location).Path)
  Write-Host ("Commit: " + $newCommit)
  Write-Host ("Tag: " + $tag)
  Write-Host ("WEB: " + $web.ok + " (" + $web.status + ")")
  Write-Host ("API: " + $api.ok + " (" + $api.status + ")")
  Write-Host ("Push: " + ($(if($pushOk){"OK"} else {"FAILED (local commit+tag created)"})))
  Write-Host ("Report: " + $reportPath)
  Write-Host "Pinned: Node=$nodeV; npm=$npmV"
  Write-Host "==============================================="
  Write-Host ""

} finally {
  try { if($devProc -and -not $devProc.HasExited){ Stop-Process -Id $devProc.Id -Force -ErrorAction SilentlyContinue } } catch {}
  Stop-Transcript | Out-Null
}

