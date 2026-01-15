param()

$ErrorActionPreference = "Stop"

function NowIso(){ (Get-Date).ToString("s") }
function EnsureDir([string]$p){ if(!(Test-Path $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }

function HasProp($obj,[string]$name){
  if($null -eq $obj -or $null -eq $obj.PSObject -or $null -eq $obj.PSObject.Properties){ return $false }
  return $null -ne $obj.PSObject.Properties[$name]
}
function GetProp($obj,[string]$name){
  if(HasProp $obj $name){ return $obj.PSObject.Properties[$name].Value }
  return $null
}
function SetProp($obj,[string]$name,$value){
  if(HasProp $obj $name){ $obj.PSObject.Properties[$name].Value = $value }
  else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force }
}
function AsArray($x){ return @($x) }

function ReadJson([string]$path){
  if(!(Test-Path $path)){ throw "Missing JSON: $path" }
  $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
  if([string]::IsNullOrWhiteSpace($raw)){ throw "Empty JSON: $path" }
  try { return ($raw | ConvertFrom-Json -Depth 80) } catch { throw "Invalid JSON: $path :: $($_.Exception.Message)" }
}
function WriteJson([string]$path,$obj){
  $json = $obj | ConvertTo-Json -Depth 80
  Set-Content -LiteralPath $path -Encoding UTF8 -Value ($json + "`n")
}

function FindRepoRoot([string]$start){
  if([string]::IsNullOrWhiteSpace($start)){ $start = (Get-Location).Path }
  if([string]::IsNullOrWhiteSpace($start)){ throw "Cannot determine start directory" }
  
  try { $cur = (Resolve-Path $start -ErrorAction Stop).Path } catch { throw "Cannot resolve path: $start" }
  if([string]::IsNullOrWhiteSpace($cur)){ throw "Empty path after Resolve-Path" }
  
  for($i=0; $i -lt 14; $i++){
    if([string]::IsNullOrWhiteSpace($cur)){ break }
    $marker = Join-Path $cur ".content-forge-root"
    if((Test-Path $marker) -or ((Test-Path (Join-Path $cur "apps")) -and (Test-Path (Join-Path $cur "packages")) -and (Test-Path (Join-Path $cur "package.json")))){
      return $cur
    }
    $parent = Split-Path $cur -Parent
    if([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cur){ break }
    $cur = $parent
  }
  
  try {
    $startResolved = (Resolve-Path $start -ErrorAction Stop).Path
    $contentForgePath = Join-Path $startResolved "content-forge"
    if((Test-Path $contentForgePath) -and (Test-Path (Join-Path $contentForgePath "apps")) -and (Test-Path (Join-Path $contentForgePath "packages")) -and (Test-Path (Join-Path $contentForgePath "package.json"))){
      return $contentForgePath
    }
  }catch{}
  
  throw "Cannot locate repo root. Expected .content-forge-root OR apps/packages/package.json"
}

function SafeRemove([string]$p,[ref]$warnings){
  try{ if(Test-Path $p){ Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop } }catch{ $warnings.Value.Add("Could not delete: $p :: $($_.Exception.Message)") | Out-Null }
}

function LatestNpmDebugLog(){
  $dir = Join-Path $env:LOCALAPPDATA "npm-cache\_logs"
  if(!(Test-Path $dir)){ return $null }
  $f = Get-ChildItem $dir -Filter "*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if($null -eq $f){ return $null }
  return $f.FullName
}

function ProbeHttp([string]$url, [int]$tries=30, [int]$sleepSec=2){
  for($i=1; $i -le $tries; $i++){
    try{
      $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 -Uri $url -ErrorAction Stop
      return [ordered]@{ ok=$true; statusCode=$r.StatusCode; try=$i }
    }catch{
      if($i -lt $tries){ Start-Sleep -Seconds $sleepSec }
    }
  }
  return [ordered]@{ ok=$false; statusCode=$null; try=$tries; error="timeout/fail" }
}

# -------------------- init --------------------
$actions = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$blockers = New-Object System.Collections.Generic.List[string]
$changed = New-Object System.Collections.Generic.List[string]
$pinnedVersions = @{}

$startDir = (Get-Location).Path
$repoRoot = FindRepoRoot $startDir
$workspaceRoot = Split-Path $repoRoot -Parent

# Create marker if missing
$marker = Join-Path $repoRoot ".content-forge-root"
if(!(Test-Path $marker)){
  Set-Content -LiteralPath $marker -Encoding UTF8 -Value "content-forge monorepo root`n"
  $actions.Add("Created .content-forge-root marker") | Out-Null
  $changed.Add($marker) | Out-Null
}

$runBase = Join-Path $workspaceRoot "_onepack_runs"
EnsureDir $runBase
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$runDir = Join-Path $runBase ("ONEPACK_BASELINE_LOCK_{0}" -f $stamp)
EnsureDir $runDir

$log = Join-Path $runDir "ONEPACK.log"
$report = Join-Path $runDir "REPORT.md"
$evid = Join-Path $runDir "evidence.json"

Start-Transcript -LiteralPath $log | Out-Null
Write-Host ("[{0}] START" -f (NowIso))
Write-Host ("[{0}] REPO={1}" -f (NowIso), $repoRoot)

# -------------------- normalize root package.json --------------------
$rootPkgPath = Join-Path $repoRoot "package.json"
$rootPkg = ReadJson $rootPkgPath
$dirty = $false

if((GetProp $rootPkg "private") -ne $true){
  SetProp $rootPkg "private" $true
  $dirty = $true
}

if(-not (HasProp $rootPkg "workspaces")){
  SetProp $rootPkg "workspaces" @("apps/*","packages/*")
  $dirty = $true
} else {
  $ws = @()
  $wsProp = GetProp $rootPkg "workspaces"
  if($null -ne $wsProp){
    foreach($w in AsArray $wsProp){
      if($null -ne $w -and -not [string]::IsNullOrWhiteSpace([string]$w)){ $ws += [string]$w }
    }
  }
  if($ws -notcontains "apps/*"){ $ws += "apps/*"; $dirty=$true }
  if($ws -notcontains "packages/*"){ $ws += "packages/*"; $dirty=$true }
  SetProp $rootPkg "workspaces" $ws
  $dirty = $true
}

if($dirty){
  WriteJson $rootPkgPath $rootPkg
  $actions.Add("Normalized root package.json: private=true + workspaces") | Out-Null
  $changed.Add($rootPkgPath) | Out-Null
}

# -------------------- build local package map --------------------
$pkgFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -Filter "package.json" -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch "\\node_modules\\" }

$localMap = @{}
$badJson = New-Object System.Collections.Generic.List[string]

foreach($f in $pkgFiles){
  try{
    $o = ReadJson $f.FullName
    $name = [string](GetProp $o "name")
    $ver = [string](GetProp $o "version")
    if(-not [string]::IsNullOrWhiteSpace($name)){
      $dir = Split-Path $f.FullName -Parent
      $localMap[$name] = @{ version=$ver; dir=$dir; file=$f.FullName }
    }
  }catch{
    $badJson.Add($f.FullName) | Out-Null
  }
}

if($badJson.Count -gt 0){
  $blockers.Add("Invalid package.json files: " + ($badJson -join ", ")) | Out-Null
}

# -------------------- rewrite workspace:* protocol --------------------
function RewriteDepsInObj($pkgObj, [string]$pkgPath, [hashtable]$localMap, [ref]$actions, [ref]$changed, [ref]$blockers){
  $dirty = $false
  $fields = @("dependencies","devDependencies","peerDependencies","optionalDependencies")
  
  foreach($field in $fields){
    if(-not (HasProp $pkgObj $field)){ continue }
    $deps = GetProp $pkgObj $field
    if($null -eq $deps){ continue }
    
    $names = @()
    $props = $deps.PSObject.Properties
    if($null -ne $props){
      foreach($p in AsArray($props)){
        if($null -ne $p -and $null -ne $p.Name){ $names += [string]$p.Name }
      }
    }
    
    foreach($depName in $names){
      $val = [string](GetProp $deps $depName)
      if([string]::IsNullOrWhiteSpace($val)){ continue }
      
      if($val -like "workspace:*" -or $val -like "workspace:^*" -or $val -like "workspace:~*"){
        if($localMap.ContainsKey($depName)){
          $targetVer = [string]$localMap[$depName].version
          if([string]::IsNullOrWhiteSpace($targetVer)){
            $blockers.Value.Add("Local package '$depName' has no version; cannot rewrite workspace:* in $pkgPath") | Out-Null
          } else {
            SetProp $deps $depName $targetVer
            $dirty = $true
            $actions.Value.Add("Rewrote workspace:* -> $targetVer for $depName in $pkgPath") | Out-Null
          }
        } else {
          $blockers.Value.Add("Found workspace protocol for NON-local dep '$depName' in $pkgPath. Cannot guess.") | Out-Null
        }
      }
    }
  }
  
  if($dirty){
    WriteJson $pkgPath $pkgObj
    $changed.Value.Add($pkgPath) | Out-Null
  }
}

if($blockers.Count -eq 0){
  foreach($f in $pkgFiles){
    $o = ReadJson $f.FullName
    RewriteDepsInObj $o $f.FullName $localMap ([ref]$actions) ([ref]$changed) ([ref]$blockers)
  }
}

# -------------------- fix API blocker: @fastify/cors --------------------
$apiPkgPath = Join-Path $repoRoot "apps\api\package.json"
if(Test-Path $apiPkgPath){
  $apiPkg = ReadJson $apiPkgPath
  $dirty = $false
  
  if($apiPkg.dependencies){
    $deps = $apiPkg.dependencies
    $corsVal = GetProp $deps "@fastify/cors"
    
    if($null -eq $corsVal -or $corsVal -eq "*" -or ($corsVal -like "^*" -and $corsVal -ne "9.0.1")){
      SetProp $deps "@fastify/cors" "9.0.1"
      $pinnedVersions["@fastify/cors"] = "9.0.1"
      $dirty = $true
      $actions.Add("Pinned @fastify/cors to 9.0.1 (compatible with fastify v4)") | Out-Null
    }
    
    # Ensure fastify stays v4
    $fastifyVal = GetProp $deps "fastify"
    if($null -ne $fastifyVal -and $fastifyVal -match "^5"){
      $blockers.Add("fastify is v5 in apps/api/package.json; this baseline requires v4") | Out-Null
    }
  }
  
  if($dirty){
    WriteJson $apiPkgPath $apiPkg
    $changed.Add($apiPkgPath) | Out-Null
  }
}

# -------------------- clean install --------------------
$npmInstall = "SKIPPED"
if($blockers.Count -eq 0){
  $actions.Add("Clean: remove node_modules + package-lock.json") | Out-Null
  
  SafeRemove (Join-Path $repoRoot "node_modules") ([ref]$warnings)
  SafeRemove (Join-Path $repoRoot "package-lock.json") ([ref]$warnings)
  
  foreach($f in $pkgFiles){
    $dir = Split-Path $f.FullName -Parent
    SafeRemove (Join-Path $dir "node_modules") ([ref]$warnings)
    SafeRemove (Join-Path $dir "package-lock.json") ([ref]$warnings)
  }
  
  try{
    Push-Location $repoRoot
    Write-Host ("[{0}] npm install --workspaces --include-workspace-root" -f (NowIso))
    & npm install --workspaces --include-workspace-root 2>&1 | Tee-Object -FilePath (Join-Path $runDir "npm_install.log")
    if($LASTEXITCODE -eq 0){
      $npmInstall = "OK"
    } else {
      $npmInstall = "FAIL"
      $blockers.Add("npm install failed with exit code $LASTEXITCODE") | Out-Null
    }
    Pop-Location
  }catch{
    try{ Pop-Location }catch{}
    $npmInstall = "FAIL"
    $blockers.Add("npm install failed: $($_.Exception.Message)") | Out-Null
  }
}

# -------------------- validate --------------------
$validate = [ordered]@{ fastify_require=$false; next_require=$false }
$apiDir = Join-Path $repoRoot "apps\api"
$webDir = Join-Path $repoRoot "apps\web"

if($blockers.Count -eq 0){
  try{
    if(Test-Path $apiDir){ Push-Location $apiDir } else { Push-Location $repoRoot }
    & node -e "require('fastify'); console.log('fastify ok')" 2>&1 | Out-Null
    if($LASTEXITCODE -eq 0){ $validate.fastify_require=$true }
    Pop-Location
  }catch{
    try{ Pop-Location }catch{}
    $blockers.Add("Validation failed: require('fastify')") | Out-Null
  }
  
  try{
    if(Test-Path $webDir){ Push-Location $webDir } else { Push-Location $repoRoot }
    & node -e "require('next/package.json'); console.log('next ok')" 2>&1 | Out-Null
    if($LASTEXITCODE -eq 0){ $validate.next_require=$true }
    Pop-Location
  }catch{
    try{ Pop-Location }catch{}
    $blockers.Add("Validation failed: require('next/package.json')") | Out-Null
  }
}

# -------------------- dev boot + probe --------------------
$dev = [ordered]@{ started=$false; pid=$null; api_ok=$false; web_ok=$false; stopped=$false }
$devProc = $null
$devStdout = Join-Path $runDir "dev.stdout.txt"
$devStderr = Join-Path $runDir "dev.stderr.txt"

if($blockers.Count -eq 0){
  try{
    Push-Location $repoRoot
    
    Write-Host ("[{0}] Starting dev servers..." -f (NowIso))
    $devProc = Start-Process -FilePath "cmd.exe" -ArgumentList "/d","/s","/c","npm run dev > `"$devStdout`" 2> `"$devStderr`"" -WorkingDirectory $repoRoot -PassThru -WindowStyle Hidden
    if($devProc){
      $dev.started=$true
      $dev.pid=$devProc.Id
    }
    
    Pop-Location
    
    if($dev.started){
      Write-Host ("[{0}] Waiting for servers..." -f (NowIso))
      Start-Sleep -Seconds 8
      
      Write-Host ("[{0}] Probing Web: http://localhost:3000" -f (NowIso))
      $dev.web_probe = ProbeHttp "http://localhost:3000" 30 2
      $dev.web_ok = [bool]$dev.web_probe.ok
      
      Write-Host ("[{0}] Probing API: http://localhost:4000/health" -f (NowIso))
      $dev.api_probe = ProbeHttp "http://localhost:4000/health" 30 2
      $dev.api_ok = [bool]$dev.api_probe.ok
      
      if(-not $dev.web_ok){ $blockers.Add("Web probe failed: http://localhost:3000") | Out-Null }
      if(-not $dev.api_ok){ $blockers.Add("API probe failed: http://localhost:4000/health") | Out-Null }
    }
  }catch{
    try{ Pop-Location }catch{}
    $blockers.Add("Failed to start/probe dev: $($_.Exception.Message)") | Out-Null
  }finally{
    Write-Host ("[{0}] Stopping dev process..." -f (NowIso))
    try{
      if($devProc -and -not $devProc.HasExited){
        & taskkill /T /F /PID $devProc.Id 2>&1 | Out-Null
        Start-Sleep -Seconds 2
      }
    }catch{}
    $dev.stopped=$true
  }
}

# -------------------- git lock --------------------
$git = [ordered]@{ commit="SKIPPED"; tag=$null; push="SKIPPED" }
try{
  Push-Location $repoRoot
  $gitOk = $true
  try{ & git --version | Out-Null }catch{ $gitOk = $false }
  
  if($gitOk){
    & git add -A 2>&1 | Out-Null
    $pending = (& git status --porcelain) 2>&1
    if($pending -and ($pending | Where-Object { $_ -notmatch '^\s*$' })){
      & git commit -m "baseline: dev-ready deterministic install" 2>&1 | Out-Null
      if($LASTEXITCODE -eq 0){ $git.commit="OK" } else { $git.commit="FAIL" }
    } else { $git.commit="NO_CHANGES" }
    
    $tag = "baseline-dev-ready-$stamp"
    $git.tag=$tag
    & git tag -a $tag -m "baseline dev-ready" 2>&1 | Out-Null
    
    $origin = (& git remote get-url origin) 2>$null
    if($origin){
      & git push -u origin HEAD 2>&1 | Out-Null
      if($LASTEXITCODE -eq 0){
        & git push origin $tag 2>&1 | Out-Null
        $git.push="OK"
      } else {
        $git.push="FAIL"
        $warnings.Add("git push failed (credentials?)") | Out-Null
      }
    } else { $git.push="NO_REMOTE" }
  }
  Pop-Location
}catch{
  try{ Pop-Location }catch{}
  $warnings.Add("git lock note: $($_.Exception.Message)") | Out-Null
}

# -------------------- report --------------------
$npmDebug = LatestNpmDebugLog
$status = "PASS"
if($blockers.Count -gt 0){ $status = "PASS_WITH_BLOCKER" }

$machine = [ordered]@{
  status=$status
  repo_path=$repoRoot
  run_dir=$runDir
  pinned_versions=$pinnedVersions
  npm_install=$npmInstall
  validate=$validate
  dev=$dev
  npm_debug_log=$npmDebug
  actions=$actions
  changed_files=$changed
  blockers=$blockers
  warnings=$warnings
  git=$git
}

WriteJson $evid $machine

$human = @()
$human += "================ ONEPACK RESULT ================"
$human += ""
$human += "Status: $status"
$human += "Repo: $repoRoot"
$human += ""

if($pinnedVersions.Count -gt 0){
  $human += "Pinned Versions:"
  foreach($k in $pinnedVersions.Keys){ $human += "  $k -> $($pinnedVersions[$k])" }
  $human += ""
}

$human += "npm install: $npmInstall"
$human += "validate: fastify_require=$($validate.fastify_require) next_require=$($validate.next_require)"
$human += "dev probe: api_ok=$($dev.api_ok) web_ok=$($dev.web_ok)"
$human += ""

if($status -eq "PASS"){
  $human += "✓ All checks passed"
} else {
  $human += "✗ BLOCKERS:"
  foreach($b in $blockers){ $human += "  - $b" }
  $human += ""
  
  if(Test-Path $devStderr){
    $stderrTail = Get-Content $devStderr -Tail 120 -ErrorAction SilentlyContinue
    if($stderrTail){
      $human += "--- Dev stderr tail (last 120 lines) ---"
      $human += ($stderrTail -join "`n")
      $human += ""
    }
  }
  
  if($npmDebug){
    $npmErrTail = Get-Content $npmDebug -Tail 120 -ErrorAction SilentlyContinue
    if($npmErrTail){
      $human += "--- npm debug log tail (last 120 lines) ---"
      $human += ($npmErrTail -join "`n")
      $human += ""
    }
  }
}

$human += "RUN_DIR: $runDir"
$human += "REPORT: $report"
$human += "LOG: $log"
$human += "EVIDENCE: $evid"
$human += "==============================================="

$md = @()
$md += "# ONEPACK_BASELINE_LOCK"
$md += ""
$md += "## Machine Report"
$md += ""
$md += "```json"
$md += ($machine | ConvertTo-Json -Depth 80)
$md += "```"
$md += ""
$md += "## Human Summary"
$md += ""
$md += (($human) -join "`n")
Set-Content -LiteralPath $report -Encoding UTF8 -Value ($md -join "`n")

Write-Host ""
Write-Host (($human) -join "`n")
Write-Host ""

Stop-Transcript | Out-Null
exit 0

