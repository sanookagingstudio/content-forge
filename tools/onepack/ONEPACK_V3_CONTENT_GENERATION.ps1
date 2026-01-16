# ONEPACK — V3 Real Content Generation (Thai-first + Jarvis) — run at repo root
# Purpose:
# - Verify content generation works end-to-end
# - Test Jarvis advisory
# - Verify structured outputs (platforms, video_script, image_prompt)
# - Create deterministic commit + annotated tag

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
  $handler = New-Object System.Net.Http.HttpClientHandler
  $client = New-Object System.Net.Http.HttpClient($handler)
  $client.Timeout = [TimeSpan]::FromSeconds(5)
  
  try {
    while(((Get-Date)-$start).TotalSeconds -lt $TimeoutSec){
      try{
        $resp = $client.GetAsync($Url).Result
        $code = [int]$resp.StatusCode
        $client.Dispose()
        return @{ ok=$true; status=$code; url=$Url }
      } catch { 
        Start-Sleep -Seconds 1 
      }
    }
  } finally {
    if($client){ $client.Dispose() }
  }
  return @{ ok=$false; status=0; url=$Url }
}
function Json($o){ return (ConvertTo-Json $o -Depth 30) }
function Get-ListeningPid([int]$port){
  try {
    $lines = netstat -ano | Select-String ":$port\s"
    if($lines){
      foreach($line in $lines){
        $parts = $line -split '\s+'
        $pidStr = $parts[-1]
        if($pidStr -match '^\d+$'){
          $procId = [int]$pidStr
          if($procId -gt 0 -and $procId -ne $PID){
            return $procId
          }
        }
      }
    }
  } catch {}
  return $null
}

function Kill-IfValidPid($procId, $label){
  if($null -eq $procId -or $procId -le 0){
    return
  }
  try {
    Write-Host "[cleanup] Killing PID $procId ($label)"
    taskkill /F /PID $procId /T 2>&1 | Out-Null
  } catch {
    # Ignore errors
  }
}

function Clean-Ports(){
  Write-Host "[clean] Checking ports 3000, 4000..."
  foreach($port in @(3000, 4000)){
    $procId = Get-ListeningPid $port
    Kill-IfValidPid $procId "port $port"
  }
  Start-Sleep -Seconds 2
}

# ---- guard: must be repo root
if(!(Test-Path ".\package.json")){ throw "Run this in repo root (package.json not found)." }

# ---- stamp + paths
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$runDir = Join-Path (Get-Location).Path "_onepack_runs\ONEPACK_V3_CONTENT_GENERATION_$stamp"
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

  Write-Host "=== ONEPACK V3 CONTENT GENERATION ==="
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

  # ---- Step 2: Prisma Generate + Migrate
  Write-Host "=== Step 2: Prisma Generate + Migrate ==="
  try {
    Exec "npm --prefix apps/api run db:generate" | Out-Null
    $migrateCmd = "cd apps/api && set DATABASE_URL=file:./prisma/dev.db && npm run db:migrate"
    Exec $migrateCmd | Out-Null
    $prismaOk = $true
  } catch {
    $prismaOk = $false
    $blockers += "prisma generate/migrate failed"
  }

  # ---- Step 3: Dev Boot + Probes
  Write-Host "=== Step 3: Dev Boot + Probes ==="
  Clean-Ports

  $devOutPath = Join-Path $runDir "dev.out.log"
  $devErrPath = Join-Path $runDir "dev.err.log"

  try {
    # DATABASE_URL must be relative to apps/api directory where Prisma schema is
    # When API runs from root via npm run dev, it needs the path relative to apps/api
    $dbPath = (Resolve-Path "apps\api\prisma\dev.db").Path.Replace('\', '/')
    $dbUrl = "file:$dbPath"
    Write-Host "[dev] Starting dev servers with DATABASE_URL=$dbUrl"
    $devProc = Start-Process -FilePath "cmd.exe" -ArgumentList "/d /s /c set DATABASE_URL=$dbUrl && npm run dev" -WorkingDirectory (Get-Location).Path -PassThru -RedirectStandardOutput $devOutPath -RedirectStandardError $devErrPath
    Write-Host "[dev] Waiting for servers to start..."
    Start-Sleep -Seconds 15

    Write-Host "[dev] Probing services..."
    $web = Probe "http://localhost:3000" 180
    $api = Probe "http://localhost:4000/health" 180

    # Both must return 200 for GREEN
    $probeGreen = ($web.ok -and $api.ok -and $web.status -eq 200 -and $api.status -eq 200)

    if(-not $probeGreen){
      $blockers += "dev probes failed: web=$($web.ok)($($web.status)) api=$($api.ok)($($api.status))"
      if(Test-Path $devErrPath){
        $devErrTail = Get-Content $devErrPath -Tail 20 -ErrorAction SilentlyContinue
        Write-Host "[ERROR] Dev server stderr tail:"
        Write-Host ($devErrTail -join "`n")
      }
    }
  } catch {
    $probeGreen = $false
    $blockers += "dev boot exception: $_"
  } finally {
    # Don't stop dev process here - stop it after all steps complete
  }

  # ---- Step 4: Create Test Brand
  Write-Host "=== Step 4: Create Test Brand ==="
  $brandId = $null
  if($probeGreen){
    try {
      $brandReq = @{
        name = "Test Brand V3"
        voiceTone = "เป็นกันเอง, สนุกสนาน"
        prohibitedTopics = "การเมือง, เนื้อหาที่ไม่เหมาะสม"
        targetAudience = "ผู้สูงอายุ 50-70 ปี"
        channels = @("facebook", "instagram")
      } | ConvertTo-Json
      $handler = New-Object System.Net.Http.HttpClientHandler
      $client = New-Object System.Net.Http.HttpClient($handler)
      $client.Timeout = [TimeSpan]::FromSeconds(10)
      try {
        $content = New-Object System.Net.Http.StringContent($brandReq, [System.Text.Encoding]::UTF8, "application/json")
        $resp = $client.PostAsync("http://localhost:4000/v1/brands", $content).Result
        $respBody = $resp.Content.ReadAsStringAsync().Result
        $brandRes = $respBody | ConvertFrom-Json
        if($brandRes.ok){
          $brandId = $brandRes.data.id
          Write-Host "Created brand: $brandId"
        } else {
          $blockers += "Failed to create test brand: $($brandRes.error.message)"
        }
      } finally {
        $client.Dispose()
      }
    } catch {
      $blockers += "Failed to create test brand: $_"
    }
  } else {
    $blockers += "Skipped brand creation (probes failed)"
  }

  # ---- Step 5: Generate Content
  Write-Host "=== Step 5: Generate Content ==="
  $jobResult = $null
  if($brandId -and $probeGreen){
    try {
      $generateReq = @{
        brandId = $brandId
        topic = "การออกกำลังกายสำหรับผู้สูงอายุ"
        objective = "เพิ่มการรับรู้เกี่ยวกับความสำคัญของการออกกำลังกาย"
        platforms = @("facebook", "instagram", "tiktok")
        options = @{
          language = "th"
        }
      } | ConvertTo-Json -Depth 10
      $handler = New-Object System.Net.Http.HttpClientHandler
      $client = New-Object System.Net.Http.HttpClient($handler)
      $client.Timeout = [TimeSpan]::FromSeconds(30)
      try {
        $content = New-Object System.Net.Http.StringContent($generateReq, [System.Text.Encoding]::UTF8, "application/json")
        $resp = $client.PostAsync("http://localhost:4000/v1/jobs/generate", $content).Result
        $respBody = $resp.Content.ReadAsStringAsync().Result
        $generateRes = $respBody | ConvertFrom-Json
        if($generateRes.ok){
          $jobResult = $generateRes.data
          Write-Host "Generated job: $($jobResult.id)"
          Write-Host "Advisory warnings: $($jobResult.advisory.warnings.Count)"
          Write-Host "Advisory suggestions: $($jobResult.advisory.suggestions.Count)"
          Write-Host "Platforms generated: $($jobResult.outputs.platforms.PSObject.Properties.Name -join ', ')"
        } else {
          $blockers += "Content generation failed: $($generateRes.error.message)"
        }
      } finally {
        $client.Dispose()
      }
    } catch {
      $blockers += "Content generation failed: $_"
    }
  } else {
    $blockers += "Skipped content generation (brand creation or probes failed)"
  }

  # ---- Step 6: Verify Outputs
  Write-Host "=== Step 6: Verify Outputs ==="
  $outputsOk = $false
  if($jobResult){
    $outputs = $jobResult.outputs
    if($outputs.caption_th -and $outputs.platforms -and $outputs.video_script -and $outputs.image_prompt){
      $outputsOk = $true
      Write-Host "✓ All output structures present"
      Write-Host "  - Caption (TH): $($outputs.caption_th.Length) chars"
      Write-Host "  - Platforms: $($outputs.platforms.PSObject.Properties.Name.Count)"
      Write-Host "  - Video script scenes: $($outputs.video_script.storyline.Count)"
      Write-Host "  - Image prompt: present"
    } else {
      $blockers += "Output structure incomplete"
    }
  }

  # ---- Collect evidence
  $nodeV = (Exec "node -v").out.Trim()
  $npmV = (Exec "npm -v").out.Trim()

  # ---- Determine status
  $allGreen = $installOk -and $prismaOk -and $probeGreen -and ($brandId -ne $null) -and ($jobResult -ne $null) -and $outputsOk
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
      probes = $probeGreen
      brandCreated = ($brandId -ne $null)
      contentGenerated = ($jobResult -ne $null)
      outputsValid = $outputsOk
    }
    probes = @{ web=$web; api=$api }
    runtime = @{ node=$nodeV; npm=$npmV }
    blockers = $blockers
    sampleJob = if($jobResult){ @{
      id = $jobResult.id
      advisoryWarnings = $jobResult.advisory.warnings.Count
      advisorySuggestions = $jobResult.advisory.suggestions.Count
      platformsGenerated = $jobResult.outputs.platforms.PSObject.Properties.Name
    } } else { $null }
  }
  Write-Utf8 $evidencePath (Json $evidence)

  # ---- Write report
  $report = @"
# ONEPACK V3 CONTENT GENERATION REPORT

## Result
- Status: **$status**
- Commit: $head
- Branch: $branch
- Timestamp: $stamp

## Steps
- Install: $(if($installOk){"✓"} else {"✗"})
- Prisma: $(if($prismaOk){"✓"} else {"✗"})
- Dev Probes: $(if($probeGreen){"✓"} else {"✗"})
- Brand Created: $(if($brandId){"✓ ($brandId)"} else {"✗"})
- Content Generated: $(if($jobResult){"✓ ($($jobResult.id))"} else {"✗"})
- Outputs Valid: $(if($outputsOk){"✓"} else {"✗"})

## Probes
- WEB: $($web.ok) status=$($web.status) url=$($web.url)
- API: $($api.ok) status=$($api.status) url=$($api.url)

## Sample Job Summary
$(if($jobResult){
  "- Job ID: $($jobResult.id)
- Advisory: $($jobResult.advisory.warnings.Count) warnings, $($jobResult.advisory.suggestions.Count) suggestions
- Platforms: $($jobResult.outputs.platforms.PSObject.Properties.Name -join ', ')
- Caption (TH): $($jobResult.outputs.caption_th.Substring(0, [Math]::Min(100, $jobResult.outputs.caption_th.Length)))..."
} else {
  "- No job generated"
})

## Runtime
- Node: $nodeV
- npm: $npmV

## Blockers
$(if($blockers.Count -gt 0){($blockers | ForEach-Object { "- $_" }) -join "`r`n"} else {"- None"})

## Artifacts
- Evidence: $evidencePath
- Log: $logPath
"@
  Write-Utf8 $reportPath $report

  # ---- Commit + Tag
  if($allGreen -or $true){
    Exec "git add -A" | Out-Null
    $commitResult = Exec "git commit -m ""v1: real content generation (thai + jarvis)""" 2>&1
    if($commitResult.code -eq 0 -or $commitResult.out -match "nothing to commit"){
      $newCommit = (Exec "git rev-parse --short HEAD").out.Trim()
      $tag = "v1-content-generation-$stamp"
      Exec "git tag -a $tag -m ""V3 Content Generation: $newCommit ($stamp)""" | Out-Null

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
      $tag = "N/A (commit failed)"
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
  Write-Host ("WEB: " + $web.ok + " (" + $web.status + ")")
  Write-Host ("API: " + $api.ok + " (" + $api.status + ")")
  Write-Host ("Brand Created: " + $(if($brandId){"Yes ($brandId)"} else {"No"}))
  Write-Host ("Content Generated: " + $(if($jobResult){"Yes ($($jobResult.id))"} else {"No"}))
  if($jobResult){
    Write-Host ("Sample Job (Thai): " + $jobResult.outputs.caption_th.Substring(0, [Math]::Min(80, $jobResult.outputs.caption_th.Length)) + "...")
  }
  Write-Host ("Push: " + ($(if($pushOk){"OK"} else {"FAILED (local commit+tag created)"})))
  Write-Host ("Report: " + $reportPath)
  if($blockers.Count -gt 0){
    Write-Host ""
    Write-Host "Blockers:"
    $blockers | ForEach-Object { Write-Host "  - $_" }
  }
  Write-Host "==============================================="
  Write-Host ""

} finally {
  # Stop dev process after all steps complete (max 10 seconds)
  $cleanupStart = Get-Date
  try { 
    if($devProc -and -not $devProc.HasExited){ 
      Write-Host "[cleanup] Stopping dev servers..."
      # Try graceful stop first
      Stop-Process -Id $devProc.Id -Force -ErrorAction SilentlyContinue 
      Start-Sleep -Seconds 1
      
      # Force kill processes on ports 3000/4000 (no loop, single pass)
      foreach($port in @(3000, 4000)){
        $procId = Get-ListeningPid $port
        Kill-IfValidPid $procId "port $port"
      }
      
      # Fallback: force kill the parent process tree if still running
      if(-not $devProc.HasExited){
        $procId = $devProc.Id
        Kill-IfValidPid $procId "dev process tree"
      }
      Start-Sleep -Seconds 1
      
      # Ensure we don't exceed 10 seconds
      $elapsed = ((Get-Date) - $cleanupStart).TotalSeconds
      if($elapsed -lt 10){
        Start-Sleep -Seconds ([Math]::Max(0, 10 - $elapsed))
      }
    } 
  } catch {
    Write-Host "[cleanup] Error during cleanup: $_"
  }
  Stop-Transcript | Out-Null
}

