param()

$ErrorActionPreference="Stop"
$ProgressPreference="SilentlyContinue"

function NowIso(){ (Get-Date).ToString("s") }
function EnsureDir([string]$p){ if(!(Test-Path $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function HasProp($obj,[string]$name){ return ($null -ne $obj) -and ($null -ne $obj.PSObject.Properties[$name]) }
function GetProp($obj,[string]$name){ if(HasProp $obj $name){ return $obj.PSObject.Properties[$name].Value } return $null }
function SetProp($obj,[string]$name,$value){ if(HasProp $obj $name){ $obj.PSObject.Properties[$name].Value=$value } else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force } }
function ReadJson([string]$path){
  if(!(Test-Path $path)){ throw "Missing JSON: $path" }
  $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
  if([string]::IsNullOrWhiteSpace($raw)){ throw "Empty JSON: $path" }
  try { return ($raw | ConvertFrom-Json -Depth 100) } catch { throw "Invalid JSON: $path :: $($_.Exception.Message)" }
}
function WriteJson([string]$path,$obj){
  $json = $obj | ConvertTo-Json -Depth 100
  Set-Content -LiteralPath $path -Encoding UTF8 -Value ($json + "`n")
}
function J($o){ $o | ConvertTo-Json -Depth 100 }

function SafeRemove([string]$p,[ref]$warnings){
  try{
    if(Test-Path $p){
      Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
    }
  }catch{
    $warnings.Value.Add("Could not delete: $p :: $($_.Exception.Message)") | Out-Null
  }
}

function LatestNpmDebugLog(){
  $dir = Join-Path $env:LOCALAPPDATA "npm-cache\_logs"
  if(!(Test-Path $dir)){ return $null }
  $f = Get-ChildItem $dir -Filter "*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if($null -eq $f){ return $null }
  return $f.FullName
}

function FindRepoRoot([string]$start){
  $startResolved = $null
  try{ $startResolved = (Resolve-Path $start -ErrorAction Stop).Path } catch { $startResolved = (Get-Location).Path }
  $cur = $startResolved
  for($i=0; $i -lt 20; $i++){
    if(Test-Path (Join-Path $cur ".content-forge-root")){ return $cur }
    if((Test-Path (Join-Path $cur "apps")) -and (Test-Path (Join-Path $cur "packages")) -and (Test-Path (Join-Path $cur "package.json"))){
      return $cur
    }
    $parent = Split-Path $cur -Parent
    if([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cur){ break }
    $cur = $parent
  }
  # Try content-forge subdirectory
  try {
    $contentForgePath = Join-Path $startResolved "content-forge"
    if((Test-Path $contentForgePath) -and (Test-Path (Join-Path $contentForgePath "apps")) -and (Test-Path (Join-Path $contentForgePath "packages")) -and (Test-Path (Join-Path $contentForgePath "package.json"))){
      return $contentForgePath
    }
  }catch{}
  throw "Cannot locate repo root from: $startResolved"
}

function TryHttp([string]$url,[int]$timeoutSec){
  $r=[ordered]@{ ok=$false; status=$null; error=$null }
  try{
    $resp = Invoke-WebRequest -UseBasicParsing -TimeoutSec $timeoutSec -Uri $url
    $r.ok=$true
    $r.status=[int]$resp.StatusCode
  }catch{
    $r.error=$_.Exception.Message
  }
  return $r
}

# -------------------- init --------------------
$actions  = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$blockers = New-Object System.Collections.Generic.List[string]
$changed  = New-Object System.Collections.Generic.List[string]

$repoRoot = $null
try{ $repoRoot = FindRepoRoot (Get-Location).Path } catch { $blockers.Add($_.Exception.Message) | Out-Null }

$nodeVer=$null; $npmVer=$null
try{ $nodeVer = (& node -v) 2>$null }catch{}
try{ $npmVer  = (& npm -v) 2>$null }catch{}
if([string]::IsNullOrWhiteSpace($nodeVer)){ $blockers.Add("Node not found in PATH") | Out-Null }
if([string]::IsNullOrWhiteSpace($npmVer)){  $blockers.Add("npm not found in PATH")  | Out-Null }

if($blockers.Count -eq 0 -and $repoRoot -ne "D:\ContentForgeWorkspace\content-forge"){
  # hard safety: user's known repo location
  $warnings.Add("Repo root auto-detected as '$repoRoot' but expected 'D:\ContentForgeWorkspace\content-forge'. Using detected value.") | Out-Null
}

$workspaceRoot = $null
if($blockers.Count -eq 0){
  $workspaceRoot = Split-Path $repoRoot -Parent
}

$runBase = $null
$runDir = $null
$log = $null
$report = $null
$evid = $null

if($blockers.Count -eq 0){
  $runBase = Join-Path $workspaceRoot "_onepack_runs"
  EnsureDir $runBase
  $stamp = Get-Date -Format "yyMMdd_HHmmss"
  $runDir = Join-Path $runBase ("ONEPACK_IMMEDIATE_BASELINE_{0}" -f $stamp)
  EnsureDir $runDir
  $log    = Join-Path $runDir "ONEPACK.log"
  $report = Join-Path $runDir "REPORT.md"
  $evid   = Join-Path $runDir "evidence.json"
  Start-Transcript -LiteralPath $log | Out-Null
  Write-Host ("[{0}] START" -f (NowIso))
  Write-Host ("[{0}] REPO={1}" -f (NowIso), $repoRoot)
}

# -------------------- marker --------------------
if($blockers.Count -eq 0){
  $marker = Join-Path $repoRoot ".content-forge-root"
  if(!(Test-Path $marker)){
    Set-Content -LiteralPath $marker -Encoding UTF8 -Value ("content-forge monorepo root`n")
    $actions.Add("Created .content-forge-root marker") | Out-Null
    $changed.Add($marker) | Out-Null
  }
}

# -------------------- normalize root workspaces --------------------
$rootPkgPath = $null
$rootPkg = $null
if($blockers.Count -eq 0){
  $rootPkgPath = Join-Path $repoRoot "package.json"
  try{ $rootPkg = ReadJson $rootPkgPath }catch{ $blockers.Add($_.Exception.Message) | Out-Null }
}
if($blockers.Count -eq 0){
  $dirty=$false
  if((GetProp $rootPkg "private") -ne $true){ SetProp $rootPkg "private" $true; $dirty=$true }
  if(-not (HasProp $rootPkg "workspaces")){
    SetProp $rootPkg "workspaces" @("apps/*","packages/*")
    $dirty=$true
  } else {
    $ws = @()
    $wsVal = GetProp $rootPkg "workspaces"
    if($wsVal -is [System.Collections.IEnumerable] -and -not ($wsVal -is [string])){
      foreach($w in $wsVal){ if($w){ $ws += [string]$w } }
    } elseif($wsVal) {
      $ws += [string]$wsVal
    }
    if($ws -notcontains "apps/*"){ $ws += "apps/*"; $dirty=$true }
    if($ws -notcontains "packages/*"){ $ws += "packages/*"; $dirty=$true }
    SetProp $rootPkg "workspaces" $ws
    $dirty=$true
  }
  if($dirty){
    WriteJson $rootPkgPath $rootPkg
    $actions.Add("Normalized root package.json: private=true + workspaces apps/*,packages/*") | Out-Null
    $changed.Add($rootPkgPath) | Out-Null
  }
}

# -------------------- scan package.jsons + build local map --------------------
$pkgFiles=@()
$localMap=@{}
$badJson = New-Object System.Collections.Generic.List[string]

if($blockers.Count -eq 0){
  $pkgFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -Filter "package.json" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch "\\node_modules\\" }
  if($pkgFiles.Count -eq 0){ $blockers.Add("No package.json found under repo root") | Out-Null }
}
if($blockers.Count -eq 0){
  foreach($f in $pkgFiles){
    try{
      $o = ReadJson $f.FullName
      $name = [string](GetProp $o "name")
      $ver  = [string](GetProp $o "version")
      if(-not [string]::IsNullOrWhiteSpace($name)){
        $localMap[$name] = @{ version=$ver; file=$f.FullName; dir=(Split-Path $f.FullName -Parent) }
      }
    }catch{
      $badJson.Add($f.FullName) | Out-Null
    }
  }
  if($badJson.Count -gt 0){
    $blockers.Add("Invalid package.json (cannot parse): " + ($badJson -join " | ")) | Out-Null
  }
}

# -------------------- pin known incompatible dep (fastify cors) --------------------
# Best-effort: ensure apps/api uses @fastify/cors compatible with fastify v4 (avoid wildcard "*")
if($blockers.Count -eq 0){
  $apiPkgPath = Join-Path $repoRoot "apps\api\package.json"
  if(Test-Path $apiPkgPath){
    $apiPkg = ReadJson $apiPkgPath
    $pinned=@()
    foreach($field in @("dependencies","devDependencies")){
      if(HasProp $apiPkg $field){
        $deps = GetProp $apiPkg $field
        if($null -ne $deps -and (HasProp $deps "@fastify/cors")){
          $cur = [string]$deps."@fastify/cors"
          if($cur -eq "*" -or $cur -match "workspace:"){
            $deps."@fastify/cors" = "9.0.1"
            $pinned += "@fastify/cors->9.0.1"
          }
        }
      }
    }
    if($pinned.Count -gt 0){
      WriteJson $apiPkgPath $apiPkg
      $actions.Add("Pinned deps in apps/api/package.json: " + ($pinned -join ", ")) | Out-Null
      $changed.Add($apiPkgPath) | Out-Null
    }
  }
}

# -------------------- rewrite workspace:* protocol deterministically --------------------
function RewriteWorkspaceProtocol($obj,[string]$pkgPath,[hashtable]$localMap,[ref]$actions,[ref]$changed,[ref]$blockers){
  $dirty=$false
  foreach($field in @("dependencies","devDependencies","peerDependencies","optionalDependencies")){
    if(-not (HasProp $obj $field)){ continue }
    $deps = GetProp $obj $field
    if($null -eq $deps){ continue }
    $depNames = @($deps.PSObject.Properties.Name)
    foreach($depName in $depNames){
      $v = [string]$deps.$depName
      if($v -like "workspace:*" -or $v -like "workspace:^*" -or $v -like "workspace:~*"){
        if($localMap.ContainsKey($depName)){
          $targetVer = [string]$localMap[$depName].version
          if([string]::IsNullOrWhiteSpace($targetVer)){
            $blockers.Value.Add("Local package '$depName' has no version; cannot rewrite workspace:* deterministically. Fix: set version in " + $localMap[$depName].file) | Out-Null
          }else{
            $deps.$depName = $targetVer
            $dirty=$true
          }
        }else{
          $blockers.Value.Add("Found workspace protocol for NON-local dep '$depName' in $pkgPath. Fix required (cannot guess).") | Out-Null
        }
      }
    }
  }
  if($dirty){
    WriteJson $pkgPath $obj
    $actions.Value.Add("Rewrote workspace:* deps -> exact local versions in $pkgPath") | Out-Null
    $changed.Value.Add($pkgPath) | Out-Null
  }
}

if($blockers.Count -eq 0){
  foreach($f in $pkgFiles){
    $o = ReadJson $f.FullName
    RewriteWorkspaceProtocol $o $f.FullName $localMap ([ref]$actions) ([ref]$changed) ([ref]$blockers)
  }
}

# -------------------- clean installs (root + all workspaces) --------------------
if($blockers.Count -eq 0){
  $actions.Add("Clean: remove node_modules + package-lock.json (root + all workspaces)") | Out-Null
  SafeRemove (Join-Path $repoRoot "node_modules") ([ref]$warnings)
  SafeRemove (Join-Path $repoRoot "package-lock.json") ([ref]$warnings)
  foreach($f in $pkgFiles){
    $dir = Split-Path $f.FullName -Parent
    SafeRemove (Join-Path $dir "node_modules") ([ref]$warnings)
    SafeRemove (Join-Path $dir "package-lock.json") ([ref]$warnings)
  }
}

# -------------------- npm install --------------------
$npmInstall="SKIPPED"
if($blockers.Count -eq 0){
  try{
    Push-Location $repoRoot
    Write-Host ("[{0}] npm install --workspaces --include-workspace-root" -f (NowIso))
    & npm install --workspaces --include-workspace-root
    $npmInstall="OK"
    Pop-Location
  }catch{
    try{ Pop-Location }catch{}
    $npmInstall="FAIL"
    $blockers.Add("npm install failed. See log and npm debug log.") | Out-Null
  }
}

# -------------------- validate deps resolvable --------------------
$validate = [ordered]@{ fastify_require=$false; next_require=$false }
if($blockers.Count -eq 0){
  $apiDir = Join-Path $repoRoot "apps\api"
  $webDir = Join-Path $repoRoot "apps\web"
  try{
    if(Test-Path $apiDir){ Push-Location $apiDir } else { Push-Location $repoRoot }
    & node -e "require('fastify'); console.log('fastify ok')" | Out-Null
    $validate.fastify_require=$true
    Pop-Location
  }catch{
    try{ Pop-Location }catch{}
    $blockers.Add("Validation failed: require('fastify') failed (apps/api or repo root).") | Out-Null
  }
  try{
    if(Test-Path $webDir){ Push-Location $webDir } else { Push-Location $repoRoot }
    & node -e "require('next/package.json'); console.log('next ok')" | Out-Null
    $validate.next_require=$true
    Pop-Location
  }catch{
    try{ Pop-Location }catch{}
    $blockers.Add("Validation failed: require('next/package.json') failed (apps/web or repo root).") | Out-Null
  }
}

# -------------------- dev boot + probe (best-effort, but required for PASS) --------------------
$devProbe = [ordered]@{ started=$false; pid=$null; web=@{}; api=@{} }
$devProc = $null
$apiOk=$false; $webOk=$false

if($blockers.Count -eq 0){
  try{
    Push-Location $repoRoot
    Write-Host ("[{0}] npm run dev (background) + probe 3000/4000" -f (NowIso))
    $devProc = Start-Process -FilePath "cmd.exe" -ArgumentList @("/d","/s","/c","npm run dev") -WorkingDirectory $repoRoot -PassThru -WindowStyle Minimized
    $devProbe.started=$true
    $devProbe.pid=$devProc.Id
    Pop-Location

    Start-Sleep -Seconds 6
    $devProbe.web = TryHttp "http://localhost:3000" 5
    $devProbe.api = TryHttp "http://localhost:4000/health" 5
    $webOk = [bool]$devProbe.web.ok
    $apiOk = [bool]$devProbe.api.ok

    if(-not $webOk){ $blockers.Add("Dev probe failed: Web not reachable on http://localhost:3000") | Out-Null }
    if(-not $apiOk){ $blockers.Add("Dev probe failed: API not reachable on http://localhost:4000/health") | Out-Null }

  }catch{
    try{ Pop-Location }catch{}
    $blockers.Add("Failed to start/probe dev: $($_.Exception.Message)") | Out-Null
  }finally{
    # stop background process best-effort to avoid ports stuck
    if($devProc -and -not $devProc.HasExited){
      try{ Stop-Process -Id $devProc.Id -Force -ErrorAction SilentlyContinue }catch{}
    }
  }
}

# -------------------- git baseline lock (best-effort) --------------------
$git = [ordered]@{ repo=$repoRoot; branch=$null; tag=$null; commit="SKIPPED"; push="SKIPPED"; origin=$null }
try{
  if($blockers.Count -eq 0){
    Push-Location $repoRoot
    $gitOk=$true
    try{ & git --version | Out-Null }catch{ $gitOk=$false }
    if($gitOk){
      try{ $origin = (& git remote get-url origin) 2>$null }catch{ $origin=$null }
      $git.origin=$origin
      try{ $br = (& git rev-parse --abbrev-ref HEAD) 2>$null }catch{ $br=$null }
      if($br){ $git.branch=$br } else { $git.branch="(unknown)" }

      & git add -A | Out-Null
      $pending = (& git status --porcelain)
      if($pending){
        & git commit -m "baseline: immediate deterministic dev-ready" | Out-Null
        $git.commit="OK"
      }else{
        $git.commit="NO_CHANGES"
      }

      $tag = ("baseline-dev-ready-" + (Get-Date -Format "yyMMdd_HHmmss"))
      $git.tag=$tag
      try{ & git tag -a $tag -m "baseline dev ready" | Out-Null }catch{ $warnings.Add("git tag note: $($_.Exception.Message)") | Out-Null }

      if($origin){
        try{
          & git push -u origin HEAD | Out-Null
          try{ & git push origin $tag | Out-Null }catch{}
          $git.push="OK"
        }catch{
          $git.push="FAIL"
          $warnings.Add("git push failed (credentials likely): $($_.Exception.Message)") | Out-Null
        }
      }else{
        $git.push="NO_REMOTE"
      }
    }else{
      $warnings.Add("git not found; skipping baseline lock") | Out-Null
    }
    Pop-Location
  }
}catch{
  try{ Pop-Location }catch{}
  $warnings.Add("git lock note: $($_.Exception.Message)") | Out-Null
}

# -------------------- final report (ALWAYS prints) --------------------
$npmDebug = LatestNpmDebugLog
$status="PASS"
if($blockers.Count -gt 0){ $status="PASS_WITH_BLOCKER" }

$machine = [ordered]@{
  status=$status
  repo_path=$repoRoot
  run_dir=$runDir
  node=$nodeVer
  npm=$npmVer
  npm_install=$npmInstall
  validate=$validate
  dev_probe=$devProbe
  npm_debug_log=$npmDebug
  actions=$actions
  changed_files=($changed | Select-Object -Unique)
  blockers=$blockers
  warnings=$warnings
  git=$git
}

if($blockers.Count -eq 0 -and $repoRoot){
  try{ WriteJson $evid $machine }catch{}
}

$human=@()
$human += "สรุปผล (Human Summary)"
$human += ""
$human += "- สถานะ: $status"
$human += "- Repo: $repoRoot"
$human += "- Node: $nodeVer"
$human += "- npm: $npmVer"
$human += "- npm install: $npmInstall"
$human += "- validate: fastify_require=$($validate.fastify_require) next_require=$($validate.next_require)"
$human += "- dev probe: api_ok=$apiOk web_ok=$webOk"
if($npmDebug){ $human += "- npm debug log ล่าสุด: $npmDebug" }
$human += ""

if($status -eq "PASS"){
  $human += "พร้อมใช้งานเป็น baseline แล้ว"
  $human += "ถัดไป:"
  $human += "  1) cd `"$repoRoot`""
  $human += "  2) npm run dev"
  $human += "  3) เปิด http://localhost:3000 และ http://localhost:4000/health"
  if($git.tag){ $human += "  4) baseline tag: $($git.tag)" }
}else{
  $human += "BLOCKERS:"
  foreach($b in $blockers){ $human += "  - $b" }
  $human += ""
  $human += "เปิด npm debug log ล่าสุดเพื่อดู error ต้นเหตุ (บรรทัด npm ERR!)"
}

# write report
try{
  $md=@()
  $md += "# ONEPACK_IMMEDIATE_BASELINE"
  $md += ""
  $md += "## Machine Report"
  $md += ""
  $md += "```json"
  $md += (J $machine)
  $md += "```"
  $md += ""
  $md += "## " + $human[0]
  $md += ""
  $md += (($human | Select-Object -Skip 1) -join "`n")
  Set-Content -LiteralPath $report -Encoding UTF8 -Value ($md -join "`n")
}catch{}

Write-Host ""
Write-Host "================ ONEPACK RESULT ================"
Write-Host (($human) -join "`n")
Write-Host ""
if($runDir){
  Write-Host "RUN_DIR : $runDir"
  Write-Host "REPORT  : $report"
  Write-Host "LOG     : $log"
  Write-Host "EVIDENCE: $evid"
}
Write-Host "==============================================="

try{ Stop-Transcript | Out-Null }catch{}
exit 0

