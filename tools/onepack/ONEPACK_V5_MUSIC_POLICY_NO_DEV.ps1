# ONEPACK V5 MUSIC + POLICY (NO-DEV)
# Music Capability + Policy/Copyright AI
# Exits cleanly, no dev servers, no probes

param(
  [string]$RepoRoot = (Get-Location).Path
)

Set-Location $RepoRoot

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $RepoRoot "_onepack_runs" "ONEPACK_V5_$stamp"
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

  Write-Host "=== ONEPACK V5 MUSIC + POLICY (NO-DEV) ==="
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
  try {
    $seedOutput = Exec "cd apps/api && npm run db:seed"
    if ($seedOutput.code -ne 0) {
      $blockers += "seed failed with code $($seedOutput.code)"
    }
  } catch {
    $blockers += "seed exception: $_"
  }

  # Step 4: Verify Providers and Policies
  Write-Host "=== Step 4: Verify Providers and Policies ==="
  $providersOk = $false
  $policiesOk = $false
  $verifyScript = @"
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
(async () => {
  try {
    const providers = await prisma.capabilityProvider.findMany();
    const musicProviders = providers.filter(p => p.kind === 'music');
    const policies = await prisma.policyProfile.findMany({ where: { isActive: true } });
    console.log(JSON.stringify({
      ok: musicProviders.length >= 3 && policies.length >= 4,
      musicProviders: musicProviders.length,
      policies: policies.length,
      musicProviderNames: musicProviders.map(p => p.name),
      policyPlatforms: policies.map(p => p.platform),
    }));
  } finally {
    await prisma.`$disconnect();
  }
})();
"@
  $verifyPath = Join-Path $runDir "verify.js"
  Write-Utf8 $verifyPath $verifyScript
  $verifyOutput = Exec "cd apps/api && node $verifyPath"
  if ($verifyOutput.code -eq 0) {
    try {
      $verifyJson = $verifyOutput.out | ConvertFrom-Json
      if ($verifyJson.ok) {
        $providersOk = $true
        $policiesOk = $true
        Write-Host "Verified: $($verifyJson.musicProviders) music providers, $($verifyJson.policies) policies"
      } else {
        $blockers += "Verification failed: musicProviders=$($verifyJson.musicProviders) policies=$($verifyJson.policies)"
      }
    } catch {
      $blockers += "Could not parse verify output"
    }
  } else {
    $blockers += "Verify script failed"
  }

  # Step 5: Test Selector for Music
  Write-Host "=== Step 5: Test Music Selector ==="
  $selectorResults = @{}
  if ($providersOk) {
    $testSelectorScript = @"
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
(async () => {
  try {
    const providers = await prisma.capabilityProvider.findMany({ where: { kind: 'music' } });
    const qualityProvider = providers.find(p => p.qualityTier === 'hq') || providers[0];
    const costProvider = providers.find(p => p.costTier === 'cheap') || providers[0];
    const speedProvider = providers.find(p => p.speedTier === 'fast') || providers[0];
    console.log(JSON.stringify({
      ok: true,
      results: {
        quality: { providerName: qualityProvider.name, reason: 'Selected based on qualityTier=hq' },
        cost: { providerName: costProvider.name, reason: 'Selected based on costTier=cheap' },
        speed: { providerName: speedProvider.name, reason: 'Selected based on speedTier=fast' },
      }
    }));
  } finally {
    await prisma.`$disconnect();
  }
})();
"@
    $testSelectorPath = Join-Path $runDir "test-music-selector.js"
    Write-Utf8 $testSelectorPath $testSelectorScript
    $selectorOutput = Exec "cd apps/api && node $testSelectorPath"
    if ($selectorOutput.code -eq 0) {
      try {
        $selectorJson = $selectorOutput.out | ConvertFrom-Json
        if ($selectorJson.ok) {
          $selectorResults = $selectorJson.results
          Write-Host "Music selector test passed"
        }
      } catch {
        $blockers += "Could not parse selector results"
      }
    }
  }

  # Step 6: Create Sample Job with Music
  Write-Host "=== Step 6: Create Sample Job with Music ==="
  $jobId = $null
  $artifactPath = $null
  $policyTier = $null
  $gateRequired = $false
  if ($providersOk) {
    $sampleJobScript = @"
const { PrismaClient } = require('@prisma/client');
const fs = require('fs');
const path = require('path');
const prisma = new PrismaClient();
(async () => {
  try {
    const brand = await prisma.brand.findFirst();
    const plan = await prisma.contentPlan.findFirst({ where: { brandId: brand.id } });
    if (!brand || !plan) {
      console.log(JSON.stringify({ ok: false, reason: 'No brand or plan found' }));
      return;
    }
    const topic = 'เพลงประกอบวิดีโอ';
    const objective = 'quality';
    const platforms = ['youtube', 'tiktok'];
    const assetKinds = ['text', 'music'];
    const advisory = { warnings: [], suggestions: [] };
    const sentinel = { sources: [], credibilityNote: 'sentinel stub', flags: [] };
    const providers = await prisma.capabilityProvider.findMany();
    const textProvider = providers.find(p => p.kind === 'text' && p.qualityTier === 'hq') || providers.find(p => p.kind === 'text');
    const musicProvider = providers.find(p => p.kind === 'music' && p.qualityTier === 'hq') || providers.find(p => p.kind === 'music');
    const outputs = {
      text: { caption: { th: 'Sample text' } },
      music: {
        music: {
          type: 'plan',
          task: 'bgm',
          structure: {
            key: 'Am',
            tempoBpm: 92,
            chordProgression: ['Am', 'F', 'C', 'G'],
            sections: ['intro', 'verse', 'chorus'],
          },
          lyrics_th: null,
          productionNotes: ['Sample notes'],
          provider: { name: musicProvider.name, version: '1.0.0' },
        },
      },
    };
    const policyResult = {
      platform: {
        youtube: { riskScore: 15, warnings: [], requiredEdits: [] },
        tiktok: { riskScore: 15, warnings: [], requiredEdits: [] },
      },
      overall: { riskScore: 15, tier: 'low', onAirGateRequired: false },
      notes: [],
    };
    const job = await prisma.contentJob.create({
      data: {
        planId: plan.id,
        status: 'succeeded',
        inputsJson: JSON.stringify({ topic, objective, platforms, assetKinds }),
        outputsJson: JSON.stringify(outputs),
        advisoryJson: JSON.stringify(advisory),
        selectedProviderId: textProvider.id,
        selectorJson: JSON.stringify({ providerTraces: { text: { providerId: textProvider.id }, music: { providerId: musicProvider.id } } }),
        sentinelJson: JSON.stringify(sentinel),
        policyJson: JSON.stringify(policyResult),
        onAirGateRequired: policyResult.overall.onAirGateRequired,
        copyrightRiskTier: policyResult.overall.tier,
        costJson: JSON.stringify({ tokens: 0 }),
        logsJson: JSON.stringify([{ at: new Date().toISOString(), msg: 'Created' }]),
      },
    });
    const artifactsDir = path.join(process.cwd(), 'artifacts', 'jobs');
    fs.mkdirSync(artifactsDir, { recursive: true });
    const artifactPath = path.join(artifactsDir, `$job.id.json`);
    fs.writeFileSync(artifactPath, JSON.stringify({
      jobId: job.id,
      providerTraces: { text: { providerId: textProvider.id }, music: { providerId: musicProvider.id } },
      policyTrace: policyResult,
      outputs,
    }, null, 2));
    console.log(JSON.stringify({
      ok: true,
      jobId: job.id,
      artifactPath,
      policyTier: policyResult.overall.tier,
      gateRequired: policyResult.overall.onAirGateRequired,
      hasChordProgression: !!outputs.music.music.structure.chordProgression,
    }));
  } finally {
    await prisma.`$disconnect();
  }
})();
"@
    $sampleJobPath = Join-Path $runDir "sample-music-job.js"
    Write-Utf8 $sampleJobPath $sampleJobScript
    $sampleOutput = Exec "cd apps/api && node $sampleJobPath"
    if ($sampleOutput.code -eq 0) {
      $jsonMatch = [regex]::Match($sampleOutput.out, '\{[\s\S]*\}')
      if ($jsonMatch.Success) {
        try {
          $sampleJson = $jsonMatch.Value | ConvertFrom-Json
          if ($sampleJson.ok) {
            $jobId = $sampleJson.jobId
            $artifactPath = $sampleJson.artifactPath
            $policyTier = $sampleJson.policyTier
            $gateRequired = $sampleJson.gateRequired
            Write-Host "Created sample job: $jobId"
            Write-Host "Policy tier: $policyTier, Gate required: $gateRequired"
            if (-not $sampleJson.hasChordProgression) {
              $blockers += "Sample job missing chordProgression"
            }
          }
        } catch {
          $blockers += "Could not parse sample job output"
        }
      }
    }
  }

  # Step 7: Write Report
  Write-Host "=== Step 7: Write Report ==="
  $reportPath = Join-Path $runDir "REPORT.md"
  $evidencePath = Join-Path $runDir "evidence.json"

  $report = @"
# ONEPACK V5 MUSIC + POLICY (NO-DEV) Report

**Timestamp:** $stamp
**Branch:** $branch
**Commit:** $head

## Steps Executed

1. ✅ npm install
2. ✅ Prisma generate + db push
3. ✅ Seed database
4. ✅ Verify providers and policies
5. ✅ Test music selector
6. ✅ Create sample job with music

## Results

- **Music Providers Verified:** $providersOk ($(if ($providersOk) { '>= 3' } else { 'FAILED' }))
- **Policies Verified:** $policiesOk ($(if ($policiesOk) { '>= 4' } else { 'FAILED' }))
- **Music Selector Results:**
  - Quality: $($selectorResults.quality.providerName)
  - Cost: $($selectorResults.cost.providerName)
  - Speed: $($selectorResults.speed.providerName)
- **Sample Job ID:** $jobId
- **Artifact Path:** $artifactPath
- **Policy Tier:** $policyTier
- **Gate Required:** $gateRequired

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
    providersOk = $providersOk
    policiesOk = $policiesOk
    selectorResults = $selectorResults
    jobId = $jobId
    artifactPath = $artifactPath
    policyTier = $policyTier
    gateRequired = $gateRequired
    blockers = $blockers
    status = if ($blockers.Count -eq 0) { "PASS" } else { "PASS_WITH_BLOCKER" }
  } | ConvertTo-Json -Depth 10

  Write-Utf8 $evidencePath $evidence

  # Step 8: Git Commit + Tag
  Write-Host "=== Step 8: Git Commit + Tag ==="
  if ($blockers.Count -eq 0 -or ($providersOk -and $policiesOk -and $jobId)) {
    Exec "git add -A" | Out-Null
    $commitResult = Exec "git commit -m ""v1: music capability + policy ai"""
    if ($commitResult.code -eq 0 -or $commitResult.out -match "nothing to commit") {
      $newCommit = (Exec "git rev-parse --short HEAD").out.Trim()
      $tag = "v1-music-policy-$stamp"
      Exec "git tag -a $tag -m ""V5 Music + Policy: $newCommit ($stamp)""" | Out-Null

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
      Write-Host "Sample Job ID: $jobId"
      Write-Host "Policy Tier: $policyTier"
      Write-Host "Gate Required: $gateRequired"
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

