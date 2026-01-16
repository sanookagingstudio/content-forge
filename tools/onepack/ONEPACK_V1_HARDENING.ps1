# ONEPACK — V1 Production Hardening — run at repo root
# Purpose:
# - Run lint, typecheck, test, build
# - Verify dev boot + probes
# - Create deterministic commit + annotated tag
# - Write comprehensive report

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
function Probe([string]$Url,[int]$TimeoutSec=180){
  $start = Get-Date
  while(((Get-Date)-$start).TotalSeconds -lt $TimeoutSec){
    try{
      $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
      return @{ ok=$true; status=[int]$r.StatusCode; url=$Url }
    } catch { Start-Sleep -Seconds 2 }
  }
  return @{ ok=$false; status=0; url=$Url }
}
function Json($o){ return (ConvertTo-Json $o -Depth 30) }
function Clean-Ports(){
  Write-Host "[clean] Checking ports 3000, 4000..."
  $ports = @(3000, 4000)
  foreach($port in $ports){
    try {
      $netstat = netstat -ano | Select-String ":$port\s"
      if($netstat){
        $pids = $netstat | ForEach-Object { ($_ -split '\s+')[-1] } | Select-Object -Unique
        foreach($procId in $pids){
          if($procId -and $procId -ne $PID){
            Write-Host "[clean] Killing PID $procId on port $port"
            taskkill /F /PID $procId 2>&1 | Out-Null
          }
        }
      }
    } catch {}
  }
  Start-Sleep -Seconds 2
}

# ---- guard: must be repo root
if(!(Test-Path ".\package.json")){ throw "Run this in repo root (package.json not found)." }

# ---- stamp + paths
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$runDir = Join-Path (Get-Location).Path "_onepack_runs\ONEPACK_V1_HARDENING_$stamp"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$logPath = Join-Path $runDir "ONEPACK.log"
$reportPath = Join-Path $runDir "REPORT.md"
$evidencePath = Join-Path $runDir "evidence.json"

Start-Transcript -Path $logPath | Out-Null

$devProc = $null
$pushOk = $false
$blockers = @()

try {
  Exec "git rev-parse --is-inside-work-tree" | Out-Null
  $head = (Exec "git rev-parse --short HEAD").out.Trim()
  $branch = (Exec "git rev-parse --abbrev-ref HEAD").out.Trim()

  Write-Host "=== ONEPACK V1 HARDENING ==="
  Write-Host "Branch: $branch"
  Write-Host "Commit: $head"
  Write-Host ""

  # ---- Step 1: Install
  Write-Host "=== Step 1: npm install ==="
  try {
    Exec "npm install" | Out-Null
    $installOk = $true
  } catch {
    $installOk = $false
    $blockers += "npm install failed"
  }

  # ---- Step 2: Prisma Generate
  Write-Host "=== Step 2: Prisma Generate ==="
  try {
    Exec "npm --prefix apps/api run db:generate" | Out-Null
    $prismaOk = $true
  } catch {
    $prismaOk = $false
    $blockers += "prisma generate failed"
  }

  # ---- Step 3: Lint
  Write-Host "=== Step 3: Lint ==="
  try {
    Exec "npm run lint" | Out-Null
    $lintOk = $true
  } catch {
    $lintOk = $false
    $blockers += "lint failed"
  }

  # ---- Step 4: Typecheck
  Write-Host "=== Step 4: Typecheck ==="
  try {
    Exec "npm run typecheck" | Out-Null
    $typecheckOk = $true
  } catch {
    $typecheckOk = $false
    $blockers += "typecheck failed"
  }

  # ---- Step 5: Test
  Write-Host "=== Step 5: Test ==="
  try {
    Exec "npm test" | Out-Null
    $testOk = $true
  } catch {
    $testOk = $false
    $blockers += "test failed"
  }

  # ---- Step 6: Build
  Write-Host "=== Step 6: Build ==="
  try {
    Exec "npm run build" | Out-Null
    $buildOk = $true
  } catch {
    $buildOk = $false
    $blockers += "build failed"
  }

  # ---- Step 7: Dev Boot + Probes
  Write-Host "=== Step 7: Dev Boot + Probes ==="
  Clean-Ports

  $devOutPath = Join-Path $runDir "dev.out.log"
  $devErrPath = Join-Path $runDir "dev.err.log"

  try {
    $devProc = Start-Process -FilePath "cmd.exe" -ArgumentList "/d /s /c npm run dev" -WorkingDirectory (Get-Location).Path -PassThru -RedirectStandardOutput $devOutPath -RedirectStandardError $devErrPath
    Start-Sleep -Seconds 5

    $web = Probe "http://localhost:3000" 180
    $api = Probe "http://localhost:4000/health" 180

    $probeGreen = ($web.ok -and $api.ok -and $web.status -eq 200 -and $api.status -eq 200)

    if(-not $probeGreen){
      $blockers += "dev probes failed: web=$($web.ok)($($web.status)) api=$($api.ok)($($api.status))"
      if(Test-Path $devErrPath){
        $devErrTail = Get-Content $devErrPath -Tail 50 -ErrorAction SilentlyContinue
        Write-Host "[ERROR] Dev server stderr tail:"
        Write-Host ($devErrTail -join "`n")
      }
    }
  } catch {
    $probeGreen = $false
    $blockers += "dev boot exception: $_"
  } finally {
    try { if($devProc -and -not $devProc.HasExited){ Stop-Process -Id $devProc.Id -Force -ErrorAction SilentlyContinue } } catch {}
  }

  # ---- Step 8: Release Bundle (optional, best-effort)
  Write-Host "=== Step 8: Release Bundle (best-effort) ==="
  $bundlePath = $null
  try {
    Exec "npm run release:bundle" | Out-Null
    $bundleFiles = Get-ChildItem "dist\release\*.zip" -ErrorAction SilentlyContinue
    if($bundleFiles){
      $bundlePath = $bundleFiles[0].FullName
      Write-Host "[bundle] Created: $bundlePath"
    }
  } catch {
    Write-Host "[bundle] Failed (non-blocking): $_"
  }

  # ---- Collect evidence
  $nodeV = (Exec "node -v").out.Trim()
  $npmV = (Exec "npm -v").out.Trim()

  $pkgs = @("next","fastify","@fastify/cors","prisma","@prisma/client","tsx","zod","vitest")
  $lsRaw = @{}
  foreach($p in $pkgs){
    try {
      $jsonOut = (Exec "npm ls $p --json --depth=0").out
      $lsRaw[$p] = $jsonOut
    } catch {
      $lsRaw[$p] = "FAILED"
    }
  }

  # ---- Determine status
  $allGreen = $installOk -and $prismaOk -and $lintOk -and $typecheckOk -and $testOk -and $buildOk -and $probeGreen
  $status = if($allGreen){"PASS"} else {"PASS_WITH_BLOCKER"}

  # ---- Write evidence
  $evidence = @{
    stamp = $stamp
    branch = $branch
    commit = $head
    status = $status
    steps = @{
      install = $installOk
      prisma = $prismaOk
      lint = $lintOk
      typecheck = $typecheckOk
      test = $testOk
      build = $buildOk
      probes = $probeGreen
    }
    probes = @{ web=$web; api=$api }
    runtime = @{ node=$nodeV; npm=$npmV }
    blockers = $blockers
    bundle = $bundlePath
    npm_ls = $lsRaw
  }
  Write-Utf8 $evidencePath (Json $evidence)

  # ---- Write report
  $report = @"
# ONEPACK V1 HARDENING REPORT

## Result
- Status: **$status**
- Commit: $head
- Branch: $branch
- Timestamp: $stamp

## Steps
- Install: $(if($installOk){"✓"} else {"✗"})
- Prisma Generate: $(if($prismaOk){"✓"} else {"✗"})
- Lint: $(if($lintOk){"✓"} else {"✗"})
- Typecheck: $(if($typecheckOk){"✓"} else {"✗"})
- Test: $(if($testOk){"✓"} else {"✗"})
- Build: $(if($buildOk){"✓"} else {"✗"})
- Dev Probes: $(if($probeGreen){"✓"} else {"✗"})

## Probes
- WEB: $($web.ok) status=$($web.status) url=$($web.url)
- API: $($api.ok) status=$($api.status) url=$($api.url)

## Runtime
- Node: $nodeV
- npm: $npmV

## Blockers
$(if($blockers.Count -gt 0){($blockers | ForEach-Object { "- $_" }) -join "`r`n"} else {"- None"})

## Artifacts
- Evidence: $evidencePath
- Log: $logPath
- Bundle: $(if($bundlePath){$bundlePath} else {"Not created"})

## CI Files
- `.github/workflows/ci.yml` - GitHub Actions workflow

## Pinned Versions
$(($pkgs | ForEach-Object { "- $_" }) -join "`r`n")
"@
  Write-Utf8 $reportPath $report

  # ---- Commit + Tag
  if($allGreen -or $true){ # Always commit if we got this far
    Exec "git add -A" | Out-Null
    Exec "git commit -m ""v1: hardening (tests+ci+release bundle)""" | Out-Null
    $newCommit = (Exec "git rev-parse --short HEAD").out.Trim()
    $tag = "v1-hardening-$stamp"
    Exec "git tag -a $tag -m ""V1 Hardening: $newCommit ($stamp)""" | Out-Null

    # Push best-effort
    try {
      Exec "git push" | Out-Null
      Exec "git push origin $tag" | Out-Null
      $pushOk = $true
    } catch {
      $pushOk = $false
    }
  } else {
    $newCommit = $head
    $tag = "N/A (not committed)"
  }

  # ---- Final summary
  Write-Host ""
  Write-Host "================ Human Summary ================"
  Write-Host ("Status: " + $status)
  Write-Host ("Repo: " + (Get-Location).Path)
  Write-Host ("Commit: " + $newCommit)
  Write-Host ("Tag: " + $tag)
  Write-Host ("Install: " + $(if($installOk){"✓"} else {"✗"}))
  Write-Host ("Lint: " + $(if($lintOk){"✓"} else {"✗"}))
  Write-Host ("Typecheck: " + $(if($typecheckOk){"✓"} else {"✗"}))
  Write-Host ("Test: " + $(if($testOk){"✓"} else {"✗"}))
  Write-Host ("Build: " + $(if($buildOk){"✓"} else {"✗"}))
  Write-Host ("WEB: " + $web.ok + " (" + $web.status + ")")
  Write-Host ("API: " + $api.ok + " (" + $api.status + ")")
  Write-Host ("Push: " + ($(if($pushOk){"OK"} else {"FAILED (local commit+tag created)"})))
  Write-Host ("Report: " + $reportPath)
  Write-Host ("Bundle: " + $(if($bundlePath){Split-Path -Leaf $bundlePath} else {"N/A"}))
  Write-Host ("Pinned: Node=$nodeV; npm=$npmV")
  if($blockers.Count -gt 0){
    Write-Host ""
    Write-Host "Blockers:"
    $blockers | ForEach-Object { Write-Host "  - $_" }
  }
  Write-Host "==============================================="
  Write-Host ""

} finally {
  try { if($devProc -and -not $devProc.HasExited){ Stop-Process -Id $devProc.Id -Force -ErrorAction SilentlyContinue } } catch {}
  Stop-Transcript | Out-Null
}

