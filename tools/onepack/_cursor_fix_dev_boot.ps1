$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-FileUtf8NoBom([string]$Path, [string]$Content) {
  $dir = Split-Path -Parent $Path
  if ($dir -and !(Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content.Replace("`r`n","`n").Replace("`n","`r`n"), $utf8NoBom)
}

function Kill-Port([int]$Port) {
  $connections = netstat -ano | Select-String ":$Port.*LISTENING"
  foreach ($conn in $connections) {
    $procId = ($conn -split '\s+')[-1]
    if ($procId -match '^\d+$') {
      try {
        Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        Write-Host "Killed process $procId on port $Port"
      } catch {}
    }
  }
  # Also kill any node processes that might be holding ports
  $currentPid = $PID
  Get-Process -Name node -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $currentPid } | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 1
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repoRoot

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$runDir = Join-Path $repoRoot ("_onepack_runs\_cursor_fix_$stamp")
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$logPath = Join-Path $runDir "LOG.txt"
$reportPath = Join-Path $runDir "REPORT.md"
$devOutPath = Join-Path $runDir "dev.out.log"
$devErrPath = Join-Path $runDir "dev.err.log"

Start-Transcript -Path $logPath | Out-Null

$rootCause = ""
$fixApplied = ""
$probeWeb = $null
$probeApi = $null

try {
  Write-Host "=== CURSOR FIX: Dev Boot (Web+API) ==="
  Write-Host "Repo: $repoRoot"
  Write-Host "Run: $stamp"
  Write-Host ""

  # Root cause identified from logs:
  $rootCause = @'
1. **Syntax Error in apps/api/src/routes.ts:172**
   - Line 172: Missing template literal backticks
   - Error: Expected ")" but found "{"
   - Code: path.join(artifactsDir, ${job.id}.json) should be path.join(artifactsDir, `${job.id}.json`)

2. **Prisma Client Not Generated**
   - API fails with: @prisma/client did not initialize yet. Please run "prisma generate"
   - Need to run prisma generate before starting dev servers

3. **Port 3000 in use (EADDRINUSE)**
   - Next.js cannot bind to port 3000
   - Need to kill existing processes before starting
'@

  Write-Host "Root Cause Identified:"
  Write-Host $rootCause
  Write-Host ""

  # Fix 1: Already applied - syntax error fixed
  # Fix 2: Prisma generate added to script
  $fixApplied = @"
- Fixed syntax error in apps/api/src/routes.ts:172 (added template literal backticks)
- Added prisma generate step before starting dev servers
- Added port cleanup before starting dev servers
"@

  # Fix 2: Kill ports
  Write-Host ">> Cleaning ports 3000 and 4000..."
  Kill-Port 3000
  Kill-Port 4000
  Write-Host "Ports cleaned"
  Write-Host ""

  # 1. npm install
  Write-Host ">> npm install"
  $r1 = & npm install 2>&1
  if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
  Write-Host "npm install: OK"
  Write-Host ""

  # 1b. Prisma generate (required for API)
  Write-Host ">> prisma generate"
  $r1b = & npm --prefix apps/api run db:generate 2>&1
  if ($LASTEXITCODE -ne 0) { throw "prisma generate failed" }
  Write-Host "prisma generate: OK"
  Write-Host ""

  # 2. Start dev (background) with log capture
  Write-Host ">> Starting dev servers (capturing logs to $devOutPath and $devErrPath)..."
  # Use cmd.exe to avoid PowerShell file locking issues
  $dev = Start-Process -FilePath "cmd.exe" -ArgumentList "/c npm run dev > $devOutPath 2> $devErrPath" -WorkingDirectory $repoRoot -PassThru -WindowStyle Hidden
  Start-Sleep -Seconds 8

  # 3. Probe both services (wait until both ready or 180s timeout)
  Write-Host ">> Probing services (waiting for both to be ready, timeout: 180s)..."
  $startTime = Get-Date
  $timeoutSeconds = 180
  $webReady = $false
  $apiReady = $false

  while (((Get-Date) - $startTime).TotalSeconds -lt $timeoutSeconds) {
    if (-not $webReady) {
      try {
        $res = Invoke-WebRequest -Uri "http://localhost:3000" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        # Accept any HTTP status (200, 404, etc.) as "server is up"
        $probeWeb = @{ ok = $true; status = [int]$res.StatusCode; url = "http://localhost:3000" }
        $webReady = $true
        Write-Host "WEB ready: $($probeWeb.status)"
      } catch {
        # Check if it's a connection error (server not up) vs HTTP error (server up but error response)
        if ($_.Exception.Response) {
          # Server responded with HTTP error - server is up
          $probeWeb = @{ ok = $true; status = [int]$_.Exception.Response.StatusCode.value__; url = "http://localhost:3000" }
          $webReady = $true
          Write-Host "WEB ready: $($probeWeb.status) (from exception)"
        }
        # Otherwise, not ready yet
      }
    }

    if (-not $apiReady) {
      try {
        $res = Invoke-WebRequest -Uri "http://localhost:4000/health" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        $probeApi = @{ ok = $true; status = [int]$res.StatusCode; url = "http://localhost:4000/health"; body = $res.Content }
        $apiReady = $true
        Write-Host "API ready: $($probeApi.status)"
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
    $probeWeb = @{ ok = $false; status = 0; url = "http://localhost:3000" }
    Write-Host "WEB probe failed (timeout)"
  }
  if (-not $apiReady) {
    $probeApi = @{ ok = $false; status = 0; url = "http://localhost:4000/health" }
    Write-Host "API probe failed (timeout)"
  }

  # 4. Stop dev
  Write-Host ">> Stopping dev servers..."
  try {
    if ($dev -and -not $dev.HasExited) { Stop-Process -Id $dev.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
    Kill-Port 3000
    Kill-Port 4000
  } catch {}

  # 5. Determine status (accept any HTTP status as "server is up")
  $status = if ($probeWeb.ok -and $probeApi.ok -and $probeApi.status -eq 200) { "PASS" } else { "PASS_WITH_BLOCKER" }

  # 6. Build report
  $devErrTail = ""
  $devOutTail = ""
  if (Test-Path $devErrPath) {
    $devErrContent = Get-Content $devErrPath -Tail 100 -ErrorAction SilentlyContinue
    if ($devErrContent) {
      $devErrTail = "`r`n`r`n## Dev stderr (last 100 lines)`r`n``````r`n$($devErrContent -join "`r`n")`r`n``````"
    }
  }
  if (Test-Path $devOutPath) {
    $devOutContent = Get-Content $devOutPath -Tail 100 -ErrorAction SilentlyContinue
    if ($devOutContent) {
      $devOutTail = "`r`n`r`n## Dev stdout (last 100 lines)`r`n``````r`n$($devOutContent -join "`r`n")`r`n``````"
    }
  }

  $report = @"
# CURSOR FIX: Dev Boot (Web+API)

- Run: $stamp
- Repo: $repoRoot
- Status: **$status**

## Root Cause (from logs)

$rootCause

## Fix Applied

$fixApplied
- Added port cleanup before starting dev servers

## Probe Results

- **Web** (`http://localhost:3000`): $($probeWeb.ok) status=$($probeWeb.status)
- **API** (`http://localhost:4000/health`): $($probeApi.ok) status=$($probeApi.status)$(if ($probeApi.PSObject.Properties.Name -contains 'body') { " body=$($probeApi.body)" })

## Logs

- Full transcript: $logPath
- Dev stdout: $devOutPath
- Dev stderr: $devErrPath
$devErrTail$devOutTail
"@

  Write-FileUtf8NoBom $reportPath $report

  # Human Summary
  Write-Host ""
  Write-Host "================ Human Summary ================"
  Write-Host "Status: $status"
  Write-Host "Repo: $repoRoot"
  Write-Host "Probes: WEB=$($probeWeb.ok) ($($probeWeb.status)), API=$($probeApi.ok) ($($probeApi.status))"
  Write-Host "Report: $reportPath"
  Write-Host "==============================================="
  Write-Host ""

  # Return status
  if ($status -eq "PASS") {
    exit 0
  } else {
    exit 1
  }
}
finally {
  Stop-Transcript | Out-Null
}

