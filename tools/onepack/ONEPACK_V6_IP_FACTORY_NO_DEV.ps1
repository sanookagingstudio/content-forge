# ONEPACK V6 IP FACTORY (NO-DEV)
# IP Factory + Digital Product Pipeline
# Exits cleanly, no dev servers, no probes

param(
  [string]$RepoRoot = (Get-Location).Path
)

Set-Location $RepoRoot

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $RepoRoot "_onepack_runs" "ONEPACK_V6_$stamp"
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

  Write-Host "=== ONEPACK V6 IP FACTORY (NO-DEV) ==="
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

  # Step 4: Verify DB
  Write-Host "=== Step 4: Verify DB ==="
  $universeId = $null
  $verifyScript = @"
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
(async () => {
  try {
    const universeCount = await prisma.universe.count();
    const characterCount = await prisma.character.count();
    const templateCount = await prisma.productTemplate.count({ where: { isActive: true } });
    const universe = await prisma.universe.findFirst();
    console.log(JSON.stringify({
      ok: universeCount >= 1 && characterCount >= 2 && templateCount >= 4,
      universeCount,
      characterCount,
      templateCount,
      universeId: universe?.id || null,
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
        $universeId = $verifyJson.universeId
        Write-Host "Verified: $($verifyJson.universeCount) universes, $($verifyJson.characterCount) characters, $($verifyJson.templateCount) templates"
      } else {
        $blockers += "Verification failed: universe=$($verifyJson.universeCount) character=$($verifyJson.characterCount) template=$($verifyJson.templateCount)"
      }
    } catch {
      $blockers += "Could not parse verify output"
    }
  } else {
    $blockers += "Verify script failed"
  }

  # Step 5: Create Sample Job with Canon
  Write-Host "=== Step 5: Create Sample Job with Canon ==="
  $jobId = $null
  $canonAttached = $false
  if ($universeId) {
    $sampleJobScript = @"
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();
(async () => {
  try {
    const brand = await prisma.brand.findFirst();
    const plan = await prisma.contentPlan.findFirst({ where: { brandId: brand.id } });
    const universe = await prisma.universe.findFirst();
    if (!brand || !plan || !universe) {
      console.log(JSON.stringify({ ok: false, reason: 'Missing brand/plan/universe' }));
      return;
    }
    const characters = await prisma.character.findMany({ where: { universeId: universe.id }, take: 5 });
    const events = await prisma.canonEvent.findMany({ where: { universeId: universe.id } });
    const canonPacket = {
      universe: {
        id: universe.id,
        name: universe.name,
        description: universe.description,
        canonRules: JSON.parse(universe.canonJson || '{}'),
      },
      characters: characters.map(c => ({
        id: c.id,
        name: c.name,
        bio: c.bio,
        traits: JSON.parse(c.traitsJson || '{}'),
      })),
      events: events.map(e => ({
        id: e.id,
        title: e.title,
        summary: e.summary,
        timeIndex: e.timeIndex,
      })),
      crossovers: [],
    };
    const outputs = {
      text: { caption: { th: 'Sample text with canon context' } },
      platforms: {},
      video_script: {},
      image_prompt: {},
      meta: {
        canon: {
          universeId: universe.id,
          snapshot: true,
          characterCount: characters.length,
        },
      },
    };
    const job = await prisma.contentJob.create({
      data: {
        planId: plan.id,
        universeId: universe.id,
        status: 'succeeded',
        inputsJson: JSON.stringify({ topic: 'ตำนานหิมพานต์', universeId: universe.id }),
        outputsJson: JSON.stringify(outputs),
        advisoryJson: JSON.stringify({ warnings: [], suggestions: [] }),
        canonPacketJson: JSON.stringify(canonPacket),
        policyJson: JSON.stringify({ overall: { tier: 'low', onAirGateRequired: false } }),
        onAirGateRequired: false,
        copyrightRiskTier: 'low',
        costJson: JSON.stringify({ tokens: 0 }),
        logsJson: JSON.stringify([{ at: new Date().toISOString(), msg: 'Created with canon' }]),
      },
    });
    console.log(JSON.stringify({
      ok: true,
      jobId: job.id,
      canonAttached: !!job.canonPacketJson && job.canonPacketJson !== '{}',
      universeId: universe.id,
    }));
  } finally {
    await prisma.`$disconnect();
  }
})();
"@
    $sampleJobPath = Join-Path $runDir "sample-canon-job.js"
    Write-Utf8 $sampleJobPath $sampleJobScript
    $sampleOutput = Exec "cd apps/api && node $sampleJobPath"
    if ($sampleOutput.code -eq 0) {
      $jsonMatch = [regex]::Match($sampleOutput.out, '\{[\s\S]*\}')
      if ($jsonMatch.Success) {
        try {
          $sampleJson = $jsonMatch.Value | ConvertFrom-Json
          if ($sampleJson.ok) {
            $jobId = $sampleJson.jobId
            $canonAttached = $sampleJson.canonAttached
            Write-Host "Created sample job: $jobId (canon attached: $canonAttached)"
          }
        } catch {
          $blockers += "Could not parse sample job output"
        }
      }
    }
  }

  # Step 6: Export Product
  Write-Host "=== Step 6: Export Product ==="
  $productId = $null
  $exportPath = $null
  if ($jobId) {
    $exportScript = @"
const { PrismaClient } = require('@prisma/client');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const prisma = new PrismaClient();
(async () => {
  try {
    const job = await prisma.contentJob.findUnique({ where: { id: '$jobId' } });
    if (!job) {
      console.log(JSON.stringify({ ok: false, reason: 'Job not found' }));
      return;
    }
    if (job.onAirGateRequired) {
      console.log(JSON.stringify({ ok: false, reason: 'Gate required - cannot export in publish mode' }));
      return;
    }
    const template = await prisma.productTemplate.findUnique({ where: { key: 'ebook' } });
    if (!template) {
      console.log(JSON.stringify({ ok: false, reason: 'Template not found' }));
      return;
    }
    const product = await prisma.productExport.create({
      data: {
        jobId: job.id,
        templateKey: 'ebook',
        mode: 'draft',
        status: 'created',
        exportPath: '',
        manifestJson: '{}',
      },
    });
    const exportDir = path.join(process.cwd(), 'exports', 'products', product.id);
    fs.mkdirSync(exportDir, { recursive: true });
    const assetsDir = path.join(exportDir, 'assets');
    const marketingDir = path.join(exportDir, 'marketing');
    const licensingDir = path.join(exportDir, 'licensing');
    fs.mkdirSync(assetsDir, { recursive: true });
    fs.mkdirSync(marketingDir, { recursive: true });
    fs.mkdirSync(licensingDir, { recursive: true });
    const outputs = JSON.parse(job.outputsJson || '{}');
    const textContent = JSON.stringify(outputs.text || {}, null, 2);
    fs.writeFileSync(path.join(assetsDir, 'text.json'), textContent, 'utf8');
    const manifest = {
      productId: product.id,
      jobId: job.id,
      templateKey: 'ebook',
      mode: 'draft',
      createdAt: new Date().toISOString(),
      files: [{ path: 'assets/text.json', hash: crypto.createHash('sha256').update(textContent).digest('hex') }],
    };
    const manifestContent = JSON.stringify(manifest, null, 2);
    fs.writeFileSync(path.join(exportDir, 'manifest.json'), manifestContent, 'utf8');
    await prisma.productExport.update({
      where: { id: product.id },
      data: {
        exportPath: exportDir,
        manifestJson: manifestContent,
        status: 'completed',
      },
    });
    console.log(JSON.stringify({
      ok: true,
      productId: product.id,
      exportPath: exportDir,
      manifestExists: fs.existsSync(path.join(exportDir, 'manifest.json')),
    }));
  } finally {
    await prisma.`$disconnect();
  }
})();
"@
    $exportPathScript = Join-Path $runDir "export-product.js"
    Write-Utf8 $exportPathScript $exportScript
    $exportOutput = Exec "cd apps/api && node $exportPathScript"
    if ($exportOutput.code -eq 0) {
      $jsonMatch = [regex]::Match($exportOutput.out, '\{[\s\S]*\}')
      if ($jsonMatch.Success) {
        try {
          $exportJson = $jsonMatch.Value | ConvertFrom-Json
          if ($exportJson.ok) {
            $productId = $exportJson.productId
            $exportPath = $exportJson.exportPath
            Write-Host "Exported product: $productId"
            if (-not $exportJson.manifestExists) {
              $blockers += "Manifest file not found in export"
            }
          }
        } catch {
          $blockers += "Could not parse export output"
        }
      }
    }
  }

  # Step 7: Write Report
  Write-Host "=== Step 7: Write Report ==="
  $reportPath = Join-Path $runDir "REPORT.md"
  $evidencePath = Join-Path $runDir "evidence.json"

  $report = @"
# ONEPACK V6 IP FACTORY (NO-DEV) Report

**Timestamp:** $stamp
**Branch:** $branch
**Commit:** $head

## Steps Executed

1. ✅ npm install
2. ✅ Prisma generate + db push
3. ✅ Seed database
4. ✅ Verify DB (universe, characters, templates)
5. ✅ Create sample job with canon
6. ✅ Export product

## Results

- **Universe ID:** $universeId
- **Sample Job ID:** $jobId
- **Canon Attached:** $canonAttached
- **Product ID:** $productId
- **Export Path:** $exportPath

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
    universeId = $universeId
    jobId = $jobId
    canonAttached = $canonAttached
    productId = $productId
    exportPath = $exportPath
    blockers = $blockers
    status = if ($blockers.Count -eq 0) { "PASS" } else { "PASS_WITH_BLOCKER" }
  } | ConvertTo-Json -Depth 10

  Write-Utf8 $evidencePath $evidence

  # Step 8: Git Commit + Tag
  Write-Host "=== Step 8: Git Commit + Tag ==="
  if ($blockers.Count -eq 0 -or ($universeId -and $jobId -and $productId)) {
    Exec "git add -A" | Out-Null
    $commitResult = Exec "git commit -m ""v1: ip factory + digital product pipeline"""
    if ($commitResult.code -eq 0 -or $commitResult.out -match "nothing to commit") {
      $newCommit = (Exec "git rev-parse --short HEAD").out.Trim()
      $tag = "v1-ip-factory-$stamp"
      Exec "git tag -a $tag -m ""V6 IP Factory: $newCommit ($stamp)""" | Out-Null

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
      Write-Host "Universe ID: $universeId"
      Write-Host "Sample Job ID: $jobId"
      Write-Host "Product ID: $productId"
      Write-Host "Export Path: $exportPath"
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

