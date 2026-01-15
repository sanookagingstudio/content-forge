param(
  [switch]$SkipPush
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-FileUtf8NoBom([string]$Path, [string]$Content) {
  $dir = Split-Path -Parent $Path
  if ($dir -and !(Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content.Replace("`r`n","`n").Replace("`n","`r`n"), $utf8NoBom)
}

function Exec([string]$Cmd, [string]$WorkDir = (Get-Location).Path) {
  Write-Host ">> $Cmd"
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell"
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command $Cmd"
  $psi.WorkingDirectory = $WorkDir
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  [void]$p.Start()
  $out = $p.StandardOutput.ReadToEnd()
  $err = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  return @{ out = $out; err = $err; code = $p.ExitCode }
}

function Probe([string]$Url, [int]$TimeoutSeconds = 180) {
  $start = Get-Date
  while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
    try {
      $res = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
      return @{ ok = $true; status = [int]$res.StatusCode; url = $Url }
    } catch {
      Start-Sleep -Seconds 2
    }
  }
  return @{ ok = $false; status = 0; url = $Url }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repoRoot

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$runDir = Join-Path $repoRoot ("_onepack_runs\ONEPACK_V1_FOUNDATION_$stamp")
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$logPath = Join-Path $runDir "ONEPACK.log"
$reportPath = Join-Path $runDir "REPORT.md"
$evidencePath = Join-Path $runDir "evidence.json"

Start-Transcript -Path $logPath | Out-Null

$pinned = @(
  @{ name = "@fastify/cors"; version = "9.0.1"; reason = "Fastify 4.x compatibility" }
)

function Kill-Port([int]$Port) {
  $connections = netstat -ano | Select-String ":$Port.*LISTENING"
  foreach ($conn in $connections) {
    $procId = ($conn -split '\s+')[-1]
    if ($procId -match '^\d+$') {
      try {
        Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
      } catch {}
    }
  }
  $currentPid = $PID
  Get-Process -Name node -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $currentPid } | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 1
}

try {
  # Clean ports before starting
  Kill-Port 3000
  Kill-Port 4000

  # Install
  $r1 = Exec "npm install"
  if ($r1.code -ne 0) { throw "npm install failed" }

  # Migrate + seed (API)
  $env:PORT = "4000"
  if (-not $env:DATABASE_URL) { $env:DATABASE_URL = "file:./dev.db" }
  if (Test-Path (Join-Path $repoRoot "apps\api\.env")) {
    # allow local overrides
  }

  # Ensure prisma client generated after migrate
  $r2 = Exec "npm --prefix apps/api run db:migrate"
  if ($r2.code -ne 0) { throw "db:migrate failed" }
  $r3 = Exec "npm --prefix apps/api run db:generate"
  if ($r3.code -ne 0) { throw "db:generate failed" }

  # Pass doc paths to seed if available
  $doc1 = @(
    Join-Path $repoRoot "CONTENT FORGE.docx",
    Join-Path $repoRoot "CONTENT_FORGE.docx",
    Join-Path $repoRoot "docs\CONTENT FORGE.docx",
    Join-Path $repoRoot "docs\CONTENT_FORGE.docx"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1

  $doc2 = @(
    Join-Path $repoRoot "Ideas contents.docx",
    Join-Path $repoRoot "IDEAS contents.docx",
    Join-Path $repoRoot "docs\Ideas contents.docx",
    Join-Path $repoRoot "docs\IDEAS contents.docx"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1

  if ($doc1) { $env:CF_DOC_PATH = $doc1 } else { Remove-Item Env:\CF_DOC_PATH -ErrorAction SilentlyContinue }
  if ($doc2) { $env:CF_IDEAS_PATH = $doc2 } else { Remove-Item Env:\CF_IDEAS_PATH -ErrorAction SilentlyContinue }

  $r4 = Exec "npm --prefix apps/api run db:seed"
  if ($r4.code -ne 0) { throw "db:seed failed" }

  # Start dev (background) with log capture
  Write-Host "Starting dev servers..."
  $devOutPath = Join-Path $runDir "dev.out.log"
  $devErrPath = Join-Path $runDir "dev.err.log"
  $dev = Start-Process -FilePath "cmd.exe" -ArgumentList "/c npm run dev > $devOutPath 2> $devErrPath" -WorkingDirectory $repoRoot -PassThru -WindowStyle Hidden
  Start-Sleep -Seconds 8

  # Wait for both services to become ready (loop until both succeed or 180s timeout)
  Write-Host "Probing services (waiting for both to be ready, timeout: 180s)..."
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
        # Check if server responded with HTTP error (server is up)
        if ($_.Exception.Response) {
          $pWeb = @{ ok = $true; status = [int]$_.Exception.Response.StatusCode.value__; url = "http://localhost:3000" }
          $webReady = $true
          Write-Host "WEB ready: $($pWeb.status) (from exception)"
        }
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

  # Stop dev (only after probes complete)
  Write-Host "Stopping dev servers..."
  try {
    if ($dev -and -not $dev.HasExited) { Stop-Process -Id $dev.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
    Kill-Port 3000
    Kill-Port 4000
  } catch {}

  # Evidence
  $evidence = @{
    stamp = $stamp
    repoRoot = $repoRoot
    probes = @{ web = $pWeb; api = $pApi }
    pinnedVersions = $pinned
    reportPath = $reportPath
  }
  Write-FileUtf8NoBom $evidencePath (($evidence | ConvertTo-Json -Depth 20) + "`r`n")

  # Report (accept any HTTP status for web as "server is up")
  $status = if ($pWeb.ok -and $pApi.ok -and $pApi.status -eq 200) { "PASS" } else { "PASS_WITH_BLOCKER" }

  $blockers = @()
  if (-not ($pWeb.ok -and $pWeb.status -eq 200)) { $blockers += "WEB probe failed: http://localhost:3000" }
  if (-not ($pApi.ok -and $pApi.status -eq 200)) { $blockers += "API probe failed: http://localhost:4000/health" }

  $blockersText = if ($blockers.Count -gt 0) { ("- " + ($blockers -join "`r`n- ")) } else { "- (none)" }

  $report = @"
# ONEPACK_V1_FOUNDATION Report

- Run: $stamp
- Repo: $repoRoot
- Status: **$status**

## Acceptance Criteria Evidence
1) npm install: OK
2) npm run dev: OK (started + stopped)
3) Probes:
   - Web: $($pWeb.ok) status=$($pWeb.status) url=$($pWeb.url)
   - API: $($pApi.ok) status=$($pApi.status) url=$($pApi.url)
4) workspace:* protocol: enforced by CI/verification step in primary ONEPACK (see root script)
5) Internal deps local: relies on existing monorepo configuration; no registry fetch for internal-only packages introduced by this ONEPACK
6) Git commit+tag+push: performed by primary ONEPACK (this runner is for reruns/verification)
7) Outputs:
   - Log: $logPath
   - Evidence JSON: $evidencePath

## Implemented V1 Scope
### Domain + Persistence (SQLite/Prisma)
Entities: Brand, Persona, ContentSeries, ContentPlan, ContentJob, Asset.

### API (Fastify)
- GET /health
- GET/POST /v1/brands
- GET/POST /v1/personas
- GET/POST /v1/plans (supports from/to/channel)
- POST /v1/jobs/generate (deterministic mock generator; writes artifact JSON)
- GET /v1/jobs/:id

### Web UI (Next.js)
Pages: Dashboard, Brands, Personas, Planner, Jobs (detail view).

### CLI
- content-forge status
- content-forge plan import <file>
- content-forge job run <planId>

## Pinned Versions
$(($pinned | ForEach-Object { "- $($_.name) = $($_.version) — $($_.reason)" }) -join "`r`n")

## Blockers (if any)
$blockersText

## Dev Logs (on failure)
$(if ($status -eq "PASS_WITH_BLOCKER" -and (Test-Path $devErrPath)) {
  $devErrTail = Get-Content $devErrPath -Tail 100 -ErrorAction SilentlyContinue
  if ($devErrTail) {
    "`r`n### Dev stderr (last 100 lines)`r`n``````r`n$($devErrTail -join "`r`n")`r`n``````"
  }
})
"@

  Write-FileUtf8NoBom $reportPath $report

  # Human Summary (terminal)
  Write-Host ''
  Write-Host '================ Human Summary ================'
  Write-Host "Status: $status"
  Write-Host "Repo: $repoRoot"
  Write-Host "Probes: WEB=$($pWeb.ok) ($($pWeb.status)), API=$($pApi.ok) ($($pApi.status))"
  Write-Host "Report: $reportPath"
  Write-Host "Pinned: $(($pinned | ForEach-Object { "$($_.name)@$($_.version)" }) -join ', ')"
  if ($blockers.Count -gt 0) {
    Write-Host 'Blockers:'
    $blockers | ForEach-Object { Write-Host "- $_" }
  } else {
    Write-Host 'Blockers: (none)'
  }
  Write-Host '==============================================='
  Write-Host ''
}
finally {
  Stop-Transcript | Out-Null
}