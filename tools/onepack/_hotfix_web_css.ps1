$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-FileUtf8NoBom([string]$Path, [string]$Content) {
  $dir = Split-Path -Parent $Path
  if ($dir -and !(Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content.Replace("`r`n","`n").Replace("`n","`r`n"), $utf8NoBom)
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repoRoot

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$runDir = Join-Path $repoRoot ("_onepack_runs\_hotfix_web_css_$stamp")
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$logPath = Join-Path $runDir "LOG.txt"
$reportPath = Join-Path $runDir "REPORT.md"

Start-Transcript -Path $logPath | Out-Null

try {
  Write-Host "=== HOTFIX: Web globals.css + Stabilize ONEPACK Probes ==="
  Write-Host "Repo: $repoRoot"
  Write-Host "Run: $stamp"
  Write-Host ""

  # 1. npm install
  Write-Host ">> npm install"
  $r1 = & npm install 2>&1
  if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
  Write-Host "npm install: OK"
  Write-Host ""

  # 2. Start dev (background) - start API and WEB separately
  Write-Host ">> Starting dev servers..."
  $apiOut = Join-Path $runDir "api.stdout.txt"
  $apiErr = Join-Path $runDir "api.stderr.txt"
  $webOut = Join-Path $runDir "web.stdout.txt"
  $webErr = Join-Path $runDir "web.stderr.txt"
  
  $devApi = Start-Process -FilePath "powershell" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command npm -w apps/api run dev *> $apiErr" -WorkingDirectory $repoRoot -PassThru
  Start-Sleep -Seconds 3
  $devWeb = Start-Process -FilePath "powershell" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command npm -w apps/web run dev *> $webErr" -WorkingDirectory $repoRoot -PassThru
  Start-Sleep -Seconds 5

  # 3. Probe both services (wait until both ready or 180s timeout)
  Write-Host ">> Probing services (waiting for both to be ready, timeout: 180s)..."
  $startTime = Get-Date
  $timeoutSeconds = 180
  $pWeb = $null
  $pApi = $null
  $webReady = $false
  $apiReady = $false

  while (((Get-Date) - $startTime).TotalSeconds -lt $timeoutSeconds) {
    if (-not $webReady) {
      try {
        $res = Invoke-WebRequest -Uri "http://localhost:3000" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        $pWeb = @{ ok = $true; status = [int]$res.StatusCode; url = "http://localhost:3000" }
        $webReady = $true
        Write-Host "WEB ready: $($pWeb.status)"
      } catch {
        # Not ready yet
      }
    }

    if (-not $apiReady) {
      try {
        $res = Invoke-WebRequest -Uri "http://localhost:4000/health" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        $pApi = @{ ok = $true; status = [int]$res.StatusCode; url = "http://localhost:4000/health" }
        $apiReady = $true
        Write-Host "API ready: $($pApi.status)"
      } catch {
        # Not ready yet
      }
    }

    if ($webReady -and $apiReady) {
      Write-Host "Both services ready!"
      break
    }

    Start-Sleep -Seconds 2
  }

  # Set failed probes if not ready
  if (-not $webReady) {
    $pWeb = @{ ok = $false; status = 0; url = "http://localhost:3000" }
    Write-Host "WEB probe failed (timeout)"
  }
  if (-not $apiReady) {
    $pApi = @{ ok = $false; status = 0; url = "http://localhost:4000/health" }
    Write-Host "API probe failed (timeout)"
  }

  # 4. Stop dev
  Write-Host ">> Stopping dev servers..."
  try {
    if ($devApi -and -not $devApi.HasExited) { Stop-Process -Id $devApi.Id -Force -ErrorAction SilentlyContinue }
    if ($devWeb -and -not $devWeb.HasExited) { Stop-Process -Id $devWeb.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
    Get-Process -Name node -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID } | Stop-Process -Force -ErrorAction SilentlyContinue
  } catch {}

  # 5. Determine status
  $status = if ($pWeb.ok -and $pApi.ok -and $pWeb.status -eq 200 -and $pApi.status -eq 200) { "PASS" } else { "PASS_WITH_BLOCKER" }

  # 6. Build report
  $report = @"
# HOTFIX: Web globals.css + Stabilize ONEPACK Probes

- Run: $stamp
- Repo: $repoRoot
- Status: **$status**

## Changes Made

1. **Created `apps/web/app/globals.css`**
   - Added minimal base styles (html/body padding/margin, link styles, box-sizing)
   - Fixes Next.js build error: "Module not found: Can't resolve './globals.css'"

2. **Updated `tools/onepack/ONEPACK_V1_FOUNDATION.ps1`**
   - Increased probe timeout from 90s to 180s
   - Changed probe logic to wait in a loop until BOTH services are ready or timeout
   - Dev servers are only stopped AFTER probes complete (no race condition)
   - Improved logging during probe phase

## Probe Results

- **Web** (`http://localhost:3000`): $($pWeb.ok) status=$($pWeb.status)
- **API** (`http://localhost:4000/health`): $($pApi.ok) status=$($pApi.status)

## Next Steps

- Run `npm run dev` to verify dev servers start correctly
- Verify both endpoints respond:
  - http://localhost:3000
  - http://localhost:4000/health
"@

  # Append output files to report if they exist
  if (Test-Path $apiErr) {
    $apiErrContent = Get-Content $apiErr -Tail 50 -ErrorAction SilentlyContinue
    if ($apiErrContent) {
      $report += "`r`n`r`n## API stderr (last 50 lines)`r`n``````r`n$($apiErrContent -join "`r`n")`r`n``````"
    }
  }
  if (Test-Path $webErr) {
    $webErrContent = Get-Content $webErr -Tail 50 -ErrorAction SilentlyContinue
    if ($webErrContent) {
      $report += "`r`n`r`n## Web stderr (last 50 lines)`r`n``````r`n$($webErrContent -join "`r`n")`r`n``````"
    }
  }

  Write-FileUtf8NoBom $reportPath $report

  # Human Summary
  Write-Host ""
  Write-Host "================ Human Summary ================"
  Write-Host "Status: $status"
  Write-Host "Repo: $repoRoot"
  Write-Host "Probes: WEB=$($pWeb.ok) ($($pWeb.status)), API=$($pApi.ok) ($($pApi.status))"
  Write-Host "Report: $reportPath"
  Write-Host "==============================================="
  Write-Host ""

  # Return status for caller
  if ($status -eq "PASS") {
    exit 0
  } else {
    exit 1
  }
}
finally {
  Stop-Transcript | Out-Null
}

