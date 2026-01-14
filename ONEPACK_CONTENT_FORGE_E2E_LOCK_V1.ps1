param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function NowIso(){ (Get-Date).ToString("s") }
function EnsureDir([string]$p){ if(!(Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function HasProp($obj,[string]$name){ return ($null -ne $obj) -and ($null -ne $obj.PSObject.Properties[$name]) }
function GetProp($obj,[string]$name){ if(HasProp $obj $name){ return $obj.PSObject.Properties[$name].Value } return $null }
function SetProp($obj,[string]$name,$value){ if(HasProp $obj $name){ $obj.PSObject.Properties[$name].Value=$value } else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force } }

function ReadJson([string]$path){
  if(!(Test-Path -LiteralPath $path)){ throw "Missing JSON: $path" }
  $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
  if([string]::IsNullOrWhiteSpace($raw)){ throw "Empty JSON: $path" }
  try { return ($raw | ConvertFrom-Json -Depth 80) } catch { throw "Invalid JSON: $path :: $($_.Exception.Message)" }
}
function WriteJson([string]$path,$obj){
  $json = $obj | ConvertTo-Json -Depth 80
  Set-Content -LiteralPath $path -Encoding UTF8 -Value ($json + "`n")
}
function J($o){ $o | ConvertTo-Json -Depth 80 }

function FindRepoRoot([string]$start){
  $cur = (Resolve-Path $start).Path
  for($i=0; $i -lt 14; $i++){
    if(Test-Path -LiteralPath (Join-Path $cur ".content-forge-root")){ return $cur }
    if((Test-Path -LiteralPath (Join-Path $cur "apps")) -and (Test-Path -LiteralPath (Join-Path $cur "packages")) -and (Test-Path -LiteralPath (Join-Path $cur "package.json"))){
      return $cur
    }
    $parent = Split-Path $cur -Parent
    if($parent -eq $cur){ break }
    $cur = $parent
  }
  throw "Cannot locate repo root. cd into D:\ContentForgeWorkspace\content-forge then rerun."
}

function SafeRemove([string]$p,[ref]$warnings){
  try{
    if(Test-Path -LiteralPath $p){
      Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
    }
  }catch{
    $warnings.Value.Add("Could not delete: $p :: $($_.Exception.Message)") | Out-Null
  }
}

function LatestNpmDebugLog(){
  $dir = Join-Path $env:LOCALAPPDATA "npm-cache\_logs"
  if(!(Test-Path -LiteralPath $dir)){ return $null }
  $f = Get-ChildItem -LiteralPath $dir -Filter "*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if($null -eq $f){ return $null }
  return $f.FullName
}

function TailFile([string]$p,[int]$n){
  if(!(Test-Path -LiteralPath $p)){ return @() }
  try { return (Get-Content -LiteralPath $p -Tail $n -ErrorAction Stop) } catch { return @() }
}

function KillPort([int]$port,[ref]$actions,[ref]$warnings){
  try{
    $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if($null -eq $conns){ return }
    $pids = @()
    foreach($c in @($conns)){
      if($null -ne $c -and ($c.PSObject.Properties.Name -contains "OwningProcess")){
        if($c.OwningProcess -and ($pids -notcontains $c.OwningProcess)){ $pids += $c.OwningProcess }
      }
    }
    foreach($pid in $pids){
      try{
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        $name = if($proc){ $proc.ProcessName } else { "PID:$pid" }
        Stop-Process -Id $pid -Force -ErrorAction Stop
        $actions.Value.Add("Killed process on port $port ($name / $pid)") | Out-Null
      }catch{
        $warnings.Value.Add("Could not kill PID $pid on port $port :: $($_.Exception.Message)") | Out-Null
      }
    }
  }catch{
    $warnings.Value.Add("Port check/kill note for $port :: $($_.Exception.Message)") | Out-Null
  }
}

function RetryHttp([string]$url,[int]$seconds,[int]$intervalMs){
  $deadline = (Get-Date).AddSeconds($seconds)
  $lastErr = $null
  while((Get-Date) -lt $deadline){
    try{
      $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
      return [ordered]@{ ok=$true; status=[int]$r.StatusCode; error=$null }
    }catch{
      $lastErr = $_.Exception.Message
      Start-Sleep -Milliseconds $intervalMs
    }
  }
  return [ordered]@{ ok=$false; status=$null; error=$lastErr }
}

# -------------------- init --------------------
$actions  = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$blockers = New-Object System.Collections.Generic.List[string]
$changed  = New-Object System.Collections.Generic.List[string]

$startDir = (Get-Location).Path
$repoRoot = FindRepoRoot $startDir
$workspaceRoot = Split-Path $repoRoot -Parent

$runBase = Join-Path $workspaceRoot "_onepack_runs"
EnsureDir $runBase
$stamp = Get-Date -Format "yyMMdd_HHmmss"
$runDir = Join-Path $runBase ("ONEPACK_CONTENT_FORGE_E2E_LOCK_V1_{0}" -f $stamp)
EnsureDir $runDir

$log    = Join-Path $runDir "ONEPACK.log"
$report = Join-Path $runDir "REPORT.md"
$evid   = Join-Path $runDir "evidence.json"

$apiOut = Join-Path $runDir "api.stdout.log"
$apiErr = Join-Path $runDir "api.stderr.log"
$webOut = Join-Path $runDir "web.stdout.log"
$webErr = Join-Path $runDir "web.stderr.log"

Start-Transcript -LiteralPath $log | Out-Null
Write-Host ("[{0}] START" -f (NowIso))
Write-Host ("[{0}] REPO={1}" -f (NowIso), $repoRoot)

# -------------------- versions --------------------
$nodeVer = $null; $npmVer=$null
try{ $nodeVer = (& node -v) 2>$null }catch{}
try{ $npmVer  = (& npm -v) 2>$null }catch{}
if([string]::IsNullOrWhiteSpace($nodeVer)){ $blockers.Add("Node not found in PATH") | Out-Null }
if([string]::IsNullOrWhiteSpace($npmVer)){  $blockers.Add("npm not found in PATH")  | Out-Null }

# -------------------- marker --------------------
$marker = Join-Path $repoRoot ".content-forge-root"
if(!(Test-Path -LiteralPath $marker)){
  Set-Content -LiteralPath $marker -Encoding UTF8 -Value ("content-forge monorepo root`n")
  $actions.Add("Created .content-forge-root marker") | Out-Null
  $changed.Add($marker) | Out-Null
}

# -------------------- normalize root package.json --------------------
$rootPkgPath = Join-Path $repoRoot "package.json"
$rootPkg = $null
try{ $rootPkg = ReadJson $rootPkgPath }catch{ $blockers.Add($_.Exception.Message) | Out-Null }

if($blockers.Count -eq 0){
  $dirty=$false
  if((GetProp $rootPkg "private") -ne $true){ SetProp $rootPkg "private" $true; $dirty=$true }
  if(-not (HasProp $rootPkg "workspaces")){
    SetProp $rootPkg "workspaces" @("apps/*","packages/*"); $dirty=$true
  }else{
    $ws = @()
    foreach($w in @((GetProp $rootPkg "workspaces"))){ if($w){ $ws += [string]$w } }
    if($ws -notcontains "apps/*"){ $ws += "apps/*"; $dirty=$true }
    if($ws -notcontains "packages/*"){ $ws += "packages/*"; $dirty=$true }
    SetProp $rootPkg "workspaces" $ws
    $dirty=$true # normalize write
  }
  if($dirty){
    WriteJson $rootPkgPath $rootPkg
    $actions.Add("Normalized root package.json: private=true + workspaces apps/*,packages/*") | Out-Null
    $changed.Add($rootPkgPath) | Out-Null
  }
}

# -------------------- scan package.json (no node_modules) --------------------
$pkgFiles = @()
if($blockers.Count -eq 0){
  $pkgFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -Filter "package.json" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch "\\node_modules\\" }
  if(@($pkgFiles).Count -eq 0){ $blockers.Add("No package.json found under repo root") | Out-Null }
}

# -------------------- local package map + aliases --------------------
$localMap = @{}   # name -> {version, dir, file}
$aliasMap = @{}   # aliasName -> realName
$badJson = New-Object System.Collections.Generic.List[string]

if($blockers.Count -eq 0){
  foreach($f in $pkgFiles){
    try{
      $o = ReadJson $f.FullName
      $name = [string](GetProp $o "name")
      $ver  = [string](GetProp $o "version")
      if(-not [string]::IsNullOrWhiteSpace($name)){
        $dir = Split-Path $f.FullName -Parent
        $localMap[$name] = @{ version=$ver; dir=$dir; file=$f.FullName }
        # build deterministic aliases for @content-forge/<x> <-> content-forge-<x>
        if($name -match "^@content-forge/(.+)$"){
          $s = $Matches[1]
          $alt = "content-forge-$s"
          if(-not $aliasMap.ContainsKey($alt)){ $aliasMap[$alt] = $name }
        }
        if($name -match "^content-forge-(.+)$"){
          $s = $Matches[1]
          $alt = "@content-forge/$s"
          if(-not $aliasMap.ContainsKey($alt)){ $aliasMap[$alt] = $name }
        }
      }
    }catch{
      $badJson.Add($f.FullName) | Out-Null
    }
  }
  if($badJson.Count -gt 0){
    $blockers.Add("Invalid package.json (cannot parse): " + ($badJson -join " | ")) | Out-Null
  }
}

function ResolveLocalName([string]$depName,[hashtable]$localMap,[hashtable]$aliasMap){
  if($localMap.ContainsKey($depName)){ return $depName }
  if($aliasMap.ContainsKey($depName)){
    $real = [string]$aliasMap[$depName]
    if($localMap.ContainsKey($real)){ return $real }
  }
  # extra deterministic rule: @content-forge/x -> content-forge-x if exists
  if($depName -match "^@content-forge/(.+)$"){
    $alt = "content-forge-" + $Matches[1]
    if($localMap.ContainsKey($alt)){ return $alt }
  }
  return $null
}

# -------------------- rewrite deps: (1) rename scoped->real local (2) rewrite workspace:* -> exact local version --------------------
function RewriteDeps($obj,[string]$pkgPath,[hashtable]$localMap,[hashtable]$aliasMap,[ref]$actions,[ref]$changed,[ref]$blockers){
  $dirty=$false
  $fields=@("dependencies","devDependencies","peerDependencies","optionalDependencies")
  foreach($field in $fields){
    if(-not (HasProp $obj $field)){ continue }
    $deps = GetProp $obj $field
    if($null -eq $deps){ continue }
    # snapshot keys (avoid mutation during enumeration)
    $keys = @($deps.PSObject.Properties.Name)
    foreach($k in $keys){
      $v = [string]$deps.$k
      $realLocal = ResolveLocalName $k $localMap $aliasMap

      # if dep key is NOT local but has deterministic local alias -> rename key
      if(($null -ne $realLocal) -and ($realLocal -ne $k)){
        $deps | Add-Member -NotePropertyName $realLocal -NotePropertyValue $v -Force
        $deps.PSObject.Properties.Remove($k) | Out-Null
        $actions.Value.Add("Renamed dep key '$k' -> '$realLocal' in $pkgPath") | Out-Null
        $dirty=$true
        $k2 = $realLocal
      } else {
        $k2 = $k
      }

      $realLocal2 = ResolveLocalName $k2 $localMap $aliasMap

      # rewrite workspace protocol deterministically
      if($v -like "workspace:*" -or $v -like "workspace:^*" -or $v -like "workspace:~*"){
        if($null -ne $realLocal2){
          $targetVer = [string]$localMap[$realLocal2].version
          if([string]::IsNullOrWhiteSpace($targetVer)){
            $blockers.Value.Add("Local package '$realLocal2' has no version; cannot rewrite workspace:* (set version in " + $localMap[$realLocal2].file + ")") | Out-Null
          }else{
            $deps.$realLocal2 = $targetVer
            $actions.Value.Add("Rewrote workspace:* for '$realLocal2' -> '$targetVer' in $pkgPath") | Out-Null
            $dirty=$true
          }
        }else{
          $blockers.Value.Add("Found workspace protocol for NON-local dep '$k2' in $pkgPath. Fix required (cannot guess).") | Out-Null
        }
      }
    }
  }

  if($dirty){
    WriteJson $pkgPath $obj
    $changed.Value.Add($pkgPath) | Out-Null
  }
}

if($blockers.Count -eq 0){
  foreach($f in $pkgFiles){
    $o = ReadJson $f.FullName
    RewriteDeps $o $f.FullName $localMap $aliasMap ([ref]$actions) ([ref]$changed) ([ref]$blockers)
  }
}

# -------------------- deterministic clean --------------------
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
    $blockers.Add("npm install failed. See ONEPACK.log and npm debug log.") | Out-Null
  }
}

# -------------------- validate require --------------------
$validate = [ordered]@{ fastify_require=$false; next_require=$false; next_bin=$false }
$apiDir = Join-Path $repoRoot "apps\api"
$webDir = Join-Path $repoRoot "apps\web"

if($blockers.Count -eq 0){
  try{
    if(Test-Path -LiteralPath $apiDir){ Push-Location $apiDir } else { Push-Location $repoRoot }
    & node -e "require('fastify'); console.log('fastify ok')" | Out-Null
    $validate.fastify_require=$true
    Pop-Location
  }catch{
    try{ Pop-Location }catch{}
    $blockers.Add("Validation failed: require('fastify') failed (apps/api).") | Out-Null
  }

  try{
    if(Test-Path -LiteralPath $webDir){ Push-Location $webDir } else { Push-Location $repoRoot }
    & node -e "require('next/package.json'); console.log('next ok')" | Out-Null
    $validate.next_require=$true
    $validate.next_bin = (Test-Path -LiteralPath (Join-Path (Get-Location).Path "node_modules\.bin\next.cmd")) -or (Test-Path -LiteralPath (Join-Path (Get-Location).Path "node_modules\.bin\next"))
    Pop-Location
  }catch{
    try{ Pop-Location }catch{}
    $blockers.Add("Validation failed: require('next/package.json') failed (apps/web).") | Out-Null
  }
}

# -------------------- start dev (API+WEB separately) + probe --------------------
$dev = [ordered]@{ started=$false; api_started=$false; web_started=$false; api_ok=$false; web_ok=$false; api_pid=$null; web_pid=$null; api_url="http://localhost:4000/health"; web_url="http://localhost:3000"; api_probe=$null; web_probe=$null }

if($blockers.Count -eq 0){
  # ensure ports are free (deterministic)
  KillPort 4000 ([ref]$actions) ([ref]$warnings)
  KillPort 3000 ([ref]$actions) ([ref]$warnings)

  try{
    Push-Location $repoRoot
    $dev.started=$true

    # API
    if(Test-Path -LiteralPath $apiDir){
      $p1 = Start-Process -FilePath "cmd.exe" -ArgumentList @("/d","/s","/c", "npm --workspace apps/api run dev") -WorkingDirectory $repoRoot -PassThru -WindowStyle Minimized -RedirectStandardOutput $apiOut -RedirectStandardError $apiErr
      $dev.api_pid = $p1.Id
      $dev.api_started=$true
      $actions.Add("Started API dev (pid=$($p1.Id))") | Out-Null
    }else{
      $blockers.Add("apps/api not found; cannot start API") | Out-Null
    }

    # WEB
    if(Test-Path -LiteralPath $webDir){
      $p2 = Start-Process -FilePath "cmd.exe" -ArgumentList @("/d","/s","/c", "npm --workspace apps/web run dev") -WorkingDirectory $repoRoot -PassThru -WindowStyle Minimized -RedirectStandardOutput $webOut -RedirectStandardError $webErr
      $dev.web_pid = $p2.Id
      $dev.web_started=$true
      $actions.Add("Started WEB dev (pid=$($p2.Id))") | Out-Null
    }else{
      $blockers.Add("apps/web not found; cannot start WEB") | Out-Null
    }

    Pop-Location
  }catch{
    try{ Pop-Location }catch{}
    $blockers.Add("Failed to start dev processes: $($_.Exception.Message)") | Out-Null
  }

  if($blockers.Count -eq 0){
    # probe with warmup
    Start-Sleep -Seconds 3
    $dev.api_probe = RetryHttp $dev.api_url 60 800
    $dev.web_probe = RetryHttp $dev.web_url 60 800
    $dev.api_ok = [bool]$dev.api_probe.ok
    $dev.web_ok = [bool]$dev.web_probe.ok

    if(-not $dev.api_ok){
      $blockers.Add("Dev probe failed: API not reachable on $($dev.api_url)") | Out-Null
    }
    if(-not $dev.web_ok){
      $blockers.Add("Dev probe failed: WEB not reachable on $($dev.web_url)") | Out-Null
    }
  }

  # stop background procs (do not leave hanging)
  foreach($pid in @($dev.api_pid,$dev.web_pid)){
    if($pid){
      try{ Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue }catch{}
    }
  }
}

# -------------------- git lock (best effort; never blocks PASS) --------------------
$git = [ordered]@{ repo=$repoRoot; branch=$null; tag=$null; commit="SKIPPED"; push="SKIPPED"; origin=$null }
try{
  Push-Location $repoRoot
  $gitOk=$true
  try{ & git --version | Out-Null }catch{ $gitOk=$false }
  if($gitOk){
    try{ $origin = (& git remote get-url origin) 2>$null }catch{ $origin=$null }
    $git.origin = $origin
    try{ $br = (& git rev-parse --abbrev-ref HEAD) 2>$null }catch{ $br=$null }
    $git.branch = if($br){ $br } else { "(unknown)" }

    & git add -A | Out-Null
    $pending = (& git status --porcelain)
    if($pending){
      & git commit -m "baseline: e2e lock (deterministic workspaces + dev probe)" | Out-Null
      $git.commit="OK"
    }else{
      $git.commit="NO_CHANGES"
    }

    $tag = ("baseline-e2e-" + $stamp)
    $git.tag=$tag
    try{ & git tag -a $tag -m "baseline e2e lock" | Out-Null }catch{ $warnings.Add("git tag note: $($_.Exception.Message)") | Out-Null }

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
}catch{
  try{ Pop-Location }catch{}
  $warnings.Add("git lock note: $($_.Exception.Message)") | Out-Null
}

# -------------------- final report (always prints) --------------------
$npmDebug = LatestNpmDebugLog
$status="PASS"
if($blockers.Count -gt 0){ $status="PASS_WITH_BLOCKER" }

# Attach useful tail snippets if blocked
$apiErrTail = @()
$webErrTail = @()
if($status -ne "PASS"){
  $apiErrTail = TailFile $apiErr 80
  $webErrTail = TailFile $webErr 40
}

$machine = [ordered]@{
  status=$status
  repo_path=$repoRoot
  run_dir=$runDir
  node=$nodeVer
  npm=$npmVer
  npm_install=$npmInstall
  validate=$validate
  dev=$dev
  npm_debug_log=$npmDebug
  actions=$actions
  changed_files=($changed | Select-Object -Unique)
  blockers=$blockers
  warnings=$warnings
  api_err_tail=$apiErrTail
  web_err_tail=$webErrTail
  git=$git
}

WriteJson $evid $machine

$human=@()
$human += "สรุปผล (Human Summary)"
$human += ""
$human += "- สถานะ: $status"
$human += "- Repo: $repoRoot"
$human += "- Node: $nodeVer"
$human += "- npm: $npmVer"
$human += "- npm install: $npmInstall"
$human += "- validate: fastify_require=$($validate.fastify_require) next_require=$($validate.next_require) next_bin=$($validate.next_bin)"
$human += "- dev probe: api_ok=$($dev.api_ok) web_ok=$($dev.web_ok) api_pid=$($dev.api_pid) web_pid=$($dev.web_pid)"
if($npmDebug){ $human += "- npm debug log ล่าสุด: $npmDebug" }
$human += ""

if($status -eq "PASS"){
  $human += "ถัดไป:"
  $human += "  1) cd `"$repoRoot`""
  $human += "  2) npm run dev"
  $human += "  3) เปิด http://localhost:3000 และ http://localhost:4000/health"
}else{
  $human += "BLOCKERS:"
  foreach($b in $blockers){ $human += "  - $b" }
  $human += ""
  if(@($apiErrTail).Count -gt 0){
    $human += "API stderr (ท้ายไฟล์):"
    foreach($l in $apiErrTail){ $human += "  $l" }
    $human += ""
  }
  if(@($webErrTail).Count -gt 0){
    $human += "WEB stderr (ท้ายไฟล์):"
    foreach($l in $webErrTail){ $human += "  $l" }
    $human += ""
  }
  $human += "ให้ดู ONEPACK.log + npm debug log ล่าสุด เฉพาะบรรทัด npm ERR! และ stacktrace ข้างบน (มันถูกแปะมาแล้ว) เพื่อชี้จุดเดียวที่ทำให้ API ไม่ขึ้น"
}

$md=@()
$md += "# ONEPACK_CONTENT_FORGE_E2E_LOCK_V1"
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

Write-Host ""
Write-Host "================ ONEPACK RESULT ================"
Write-Host (($human) -join "`n")
Write-Host ""
Write-Host "RUN_DIR : $runDir"
Write-Host "REPORT  : $report"
Write-Host "LOG     : $log"
Write-Host "EVIDENCE: $evid"
Write-Host "==============================================="

Stop-Transcript | Out-Null
exit 0
