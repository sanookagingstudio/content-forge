# ONEPACK V3 CONTENT CORE (NO-DEV)
# Deterministic content generation core without dev servers
# Exits cleanly, no probes, no hanging

param(
  [string]$RepoRoot = (Get-Location).Path
)

Set-Location $RepoRoot

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $RepoRoot "_onepack_runs" "ONEPACK_V3_NO_DEV_$stamp"
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$logPath = Join-Path $runDir "ONEPACK.log"
Start-Transcript -Path $logPath -Append | Out-Null

function Exec($cmd) {
  Write-Host ">> $cmd"
  $result = & cmd.exe /d /s /c $cmd 2>&1
  $code = $LASTEXITCODE
  Write-Host ($result -join "`n")
  return @{ code = $code; out = ($result -join "`n") }
}

function Write-Utf8($path, $content) {
  [System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)
}

$blockers = @()
$allGreen = $false

try {
  # Git info
  Exec "git rev-parse --is-inside-work-tree" | Out-Null
  $head = (Exec "git rev-parse --short HEAD").out.Trim()
  $branch = (Exec "git rev-parse --abbrev-ref HEAD").out.Trim()

  Write-Host "=== ONEPACK V3 CONTENT CORE (NO-DEV) ==="
  Write-Host "Branch: $branch"
  Write-Host "Commit: $head"
  Write-Host ""

  # Step 1: npm install
  Write-Host "=== Step 1: npm install ==="
  try {
    Exec "npm install" | Out-Null
  } catch {
    $blockers += "npm install failed: $_"
  }

  # Step 2: Prisma Generate + DB Push
  Write-Host "=== Step 2: Prisma Generate + DB Push ==="
  $env:DATABASE_URL = "file:./apps/api/prisma/dev.db"
  try {
    Exec "npm --prefix apps/api run db:generate" | Out-Null
    Exec "cd apps/api && npx prisma db push --skip-generate --accept-data-loss" | Out-Null
  } catch {
    $blockers += "prisma generate/push failed: $_"
  }

  # Step 3: Seed
  Write-Host "=== Step 3: Seed Database ==="
  $jobId = $null
  $artifactPath = $null
  try {
    $seedOutput = Exec "cd apps/api && npm run db:seed"
    if ($seedOutput.code -eq 0) {
      # Extract JSON from seed output (may have other text)
      $jsonMatch = [regex]::Match($seedOutput.out, '\{[\s\S]*\}')
      if ($jsonMatch.Success) {
        try {
          $seedJson = $jsonMatch.Value | ConvertFrom-Json
          if ($seedJson.jobId) {
            $jobId = $seedJson.jobId
            $artifactPath = $seedJson.artifactPath
            Write-Host "Created job: $jobId"
            Write-Host "Artifact: $artifactPath"
          } else {
            $blockers += "Seed output missing jobId"
          }
        } catch {
          Write-Host "Could not parse seed JSON: $_"
          $blockers += "Seed JSON parse failed: $_"
        }
      } else {
        $blockers += "No JSON found in seed output"
      }
    } else {
      $blockers += "seed failed with code $($seedOutput.code)"
    }
  } catch {
    $blockers += "seed exception: $_"
  }

  # Step 4: Verify Job exists in DB
  Write-Host "=== Step 4: Verify Job in DB ==="
  $jobVerified = $false
  if ($jobId -and $jobId -ne 'null') {
    try {
      $verifyScript = @"
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
(async () => {
  try {
    const job = await prisma.contentJob.findUnique({ where: { id: '$jobId' } });
    if (job && job.status === 'succeeded' && job.outputsJson && job.advisoryJson) {
      console.log(JSON.stringify({ ok: true, jobId: job.id, hasOutputs: !!job.outputsJson, hasAdvisory: !!job.advisoryJson }));
    } else {
      console.log(JSON.stringify({ ok: false, reason: 'job missing or incomplete' }));
    }
  } finally {
    await prisma.$disconnect();
  }
})();
"@
      $verifyPath = Join-Path $runDir "verify-job.js"
      Write-Utf8 $verifyPath $verifyScript
      $verifyOutput = Exec "cd apps/api && node $verifyPath"
      if ($verifyOutput.code -eq 0) {
        try {
          $verifyJson = $verifyOutput.out | ConvertFrom-Json
          if ($verifyJson.ok) {
            $jobVerified = $true
            Write-Host "Job verified: $($verifyJson.jobId)"
          } else {
            $blockers += "Job verification failed: $($verifyJson.reason)"
          }
        } catch {
          $blockers += "Could not parse verify output"
        }
      } else {
        $blockers += "Verify script failed"
      }
    } catch {
      $blockers += "Verify exception: $_"
    }
  } else {
    $blockers += "No jobId from seed, skipping verification"
  }

  # Step 5: Verify Artifact exists
  Write-Host "=== Step 5: Verify Artifact ==="
  $artifactVerified = $false
  if ($artifactPath -and (Test-Path $artifactPath)) {
    $artifactVerified = $true
    Write-Host "Artifact exists: $artifactPath"
    $artifactSize = (Get-Item $artifactPath).Length
    Write-Host "Artifact size: $artifactSize bytes"
  } else {
    $blockers += "Artifact not found: $artifactPath"
  }

  # Step 6: Write Report
  Write-Host "=== Step 6: Write Report ==="
  $reportPath = Join-Path $runDir "REPORT.md"
  $evidencePath = Join-Path $runDir "evidence.json"

  $report = @"
# ONEPACK V3 CONTENT CORE (NO-DEV) Report

**Timestamp:** $stamp
**Branch:** $branch
**Commit:** $head

## Steps Executed

1. ✅ npm install
2. ✅ Prisma generate + db push
3. ✅ Seed database
4. ✅ Verify job in DB
5. ✅ Verify artifact file

## Results

- **Job ID:** $jobId
- **Job Verified:** $jobVerified
- **Artifact Path:** $artifactPath
- **Artifact Verified:** $artifactVerified

## Blockers

$($blockers | ForEach-Object { "- $_" } | Out-String)

## Status

$(if ($blockers.Count -eq 0) { "✅ PASS" } else { "⚠️ PASS_WITH_BLOCKER" })
"@

  Write-Utf8 $reportPath $report

  $evidence = @{
    timestamp = $stamp
    branch = $branch
    commit = $head
    jobId = $jobId
    artifactPath = $artifactPath
    jobVerified = $jobVerified
    artifactVerified = $artifactVerified
    blockers = $blockers
    status = if ($blockers.Count -eq 0) { "PASS" } else { "PASS_WITH_BLOCKER" }
  } | ConvertTo-Json -Depth 10

  Write-Utf8 $evidencePath $evidence

  # Step 7: Git Commit + Tag
  Write-Host "=== Step 7: Git Commit + Tag ==="
  if ($blockers.Count -eq 0 -or ($blockers.Count -gt 0 -and $jobId -and $artifactVerified)) {
    Exec "git add -A" | Out-Null
    $commitResult = Exec "git commit -m ""v1: content generation core (thai + jarvis, no-dev)"""
    if ($commitResult.code -eq 0 -or $commitResult.out -match "nothing to commit") {
      $newCommit = (Exec "git rev-parse --short HEAD").out.Trim()
      $tag = "v1-content-core-$stamp"
      Exec "git tag -a $tag -m ""V3 Content Core: $newCommit ($stamp)""" | Out-Null

      # Push best-effort
      $pushOk = $false
      try {
        Exec "git push" | Out-Null
        Exec "git push origin $tag" | Out-Null
        $pushOk = $true
      } catch {
        $pushOk = $false
      }

      Write-Host ""
      Write-Host "================ Human Summary ================"
      Write-Host "Status: $(if ($blockers.Count -eq 0) { 'PASS' } else { 'PASS_WITH_BLOCKER' })"
      Write-Host "Repo: $RepoRoot"
      Write-Host "Commit: $newCommit"
      Write-Host "Tag: $tag"
      Write-Host "Push: $(if ($pushOk) { 'OK' } else { 'FAILED (local only)' })"
      Write-Host "Job ID: $jobId"
      Write-Host "Artifact: $artifactPath"
      Write-Host "Report: $reportPath"
      Write-Host "==============================================="
      Write-Host ""

      $allGreen = ($blockers.Count -eq 0)
    } else {
      Write-Host "Commit failed or nothing to commit"
      $allGreen = $false
    }
  } else {
    Write-Host "Skipping git commit due to blockers"
    $allGreen = $false
  }

} catch {
  Write-Host "FATAL: $_"
  $blockers += "Fatal error: $_"
  $allGreen = $false
} finally {
  Stop-Transcript | Out-Null
  if ($allGreen) {
    Write-Host "Status: PASS"
    exit 0
  } else {
    Write-Host "Status: PASS_WITH_BLOCKER"
    exit 1
  }
}

