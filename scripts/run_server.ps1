# Starts the portable MariaDB (unless it already runs), the SSLv3 gateway and
# nfsrun-server.exe in this window, and stops what it started when the server
# exits. Called by start_server.bat.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config_utils.ps1')

$root          = Get-ProjectRoot
$configDir     = Join-Path $root 'config'
$dbEnv         = Join-Path $configDir 'database.env'
$serverEnv     = Join-Path $configDir 'server.env'
$myIni         = Join-Path $configDir 'my.ini'
$marker        = Join-Path $configDir '.initialized'
$rootKey       = Join-Path $configDir 'mariadb-root.key'
$gatewayConfig = Join-Path $configDir 'gateway.ini'
$binDir        = Join-Path $root 'mariadb\bin'
$runDir        = Join-Path $root 'run'
$logsDir       = Join-Path $root 'logs'
$serverExe     = Join-Path $root 'nfsrun-server.exe'
$gatewayExe    = Join-Path $root 'legacy_gateway\build\nfsrun-ssl-gateway.exe'

function Write-Step([string]$Text) { Write-Host "  $Text" }
function Write-Note([string]$Text) { Write-Host "  $Text" -ForegroundColor Yellow }

if (-not (Test-Path $marker)) { throw 'Setup is not initialized. Run start_server.bat.' }
foreach ($p in @($dbEnv, $serverEnv, $myIni, $rootKey, $serverExe, $gatewayExe, $gatewayConfig)) {
    if (-not (Test-Path $p)) { throw "Missing required file: $p" }
}
New-Item -ItemType Directory -Force -Path $runDir, $logsDir | Out-Null

$mariaServer = Find-MariaDbExecutable $binDir @('mariadbd.exe', 'mysqld.exe')
$mariaClient = Find-MariaDbExecutable $binDir @('mariadb.exe', 'mysql.exe')
if (-not $mariaServer -or -not $mariaClient) { throw 'Portable MariaDB binaries are missing.' }

$db = Read-EnvFile $dbEnv
$dbHost = [string]$db['DB_HOST']
$dbPort = [int]$db['DB_PORT']
$serverCfg = Read-EnvFile $serverEnv

Write-Host ''
Write-Host "  NFS The Run Private Server" -ForegroundColor Cyan
Write-Host '  ----------------------------------------' -ForegroundColor Cyan

# --- database ---------------------------------------------------------------
function Test-ConfiguredDb {
    & $mariaClient '--protocol=tcp' "--host=$dbHost" "--port=$dbPort" "--user=$($db['DB_USER'])" `
        "--password=$($db['DB_PASSWORD'])" "--database=$($db['DB_NAME'])" '-N' '-e' 'SELECT 1;' *> $null
    return ($LASTEXITCODE -eq 0)
}
$startedDatabase = $false
$dbProcess = $null
if (Test-TcpPort $dbHost $dbPort 500) {
    if (-not (Test-ConfiguredDb)) { throw "Port $dbPort is in use but is not this package's MariaDB." }
    Write-Step "MariaDB already running on ${dbHost}:$dbPort"
} else {
    Write-Step "Starting MariaDB on ${dbHost}:$dbPort ..."
    $dbProcess = Start-Process -FilePath $mariaServer -ArgumentList @("--defaults-file=`"$myIni`"", '--console') -WindowStyle Hidden -PassThru
    $startedDatabase = $true
    Set-Content -LiteralPath (Join-Path $runDir 'mariadb-launcher.pid') -Value $dbProcess.Id -Encoding ASCII
    if (-not (Wait-TcpPort $dbHost $dbPort 35)) {
        if (-not $dbProcess.HasExited) { Stop-Process -Id $dbProcess.Id -Force }
        throw 'MariaDB did not start. Check logs\mariadb.log.'
    }
    if (-not (Test-ConfiguredDb)) { throw 'MariaDB started but the configured login failed.' }
}

# --- logs: keep the last 20 runs in logs\archive ------------------------------
$archiveRoot = Join-Path $logsDir 'archive'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
foreach ($n in @('server.log', 'gateway.log')) {
    $lp = Join-Path $logsDir $n
    if ((Test-Path -LiteralPath $lp) -and (Get-Item -LiteralPath $lp).Length -gt 0) {
        $dest = Join-Path $archiveRoot $stamp
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Move-Item -LiteralPath $lp -Destination (Join-Path $dest $n) -Force
    }
}
if (Test-Path -LiteralPath $archiveRoot) {
    Get-ChildItem -LiteralPath $archiveRoot -Directory | Sort-Object Name -Descending |
        Select-Object -Skip 20 | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# --- web Autolog: the gateway's [blaze] slot fronts HTTP 18080 with SSLv3 -------
# (skipped with WEB_AUTOLOG_HOST=off; the previous file is kept as gateway.ini.bak_web)
if ([string]$serverCfg['WEB_AUTOLOG_HOST'] -notmatch '^\s*off\s*$') {
    $gwText = Get-Content -LiteralPath $gatewayConfig -Raw
    if ($gwText -notmatch '(?ms)^\[blaze\][^\[]*name=WEBAUTOLOG' -or $gwText -notmatch '(?ms)^\[blaze\][^\[]*enabled=1') {
        Copy-Item -LiteralPath $gatewayConfig "$gatewayConfig.bak_web" -Force
        $want = [ordered]@{ enabled = '1'; name = 'WEBAUTOLOG'; listen_host = '0.0.0.0'; listen_port = '18443'; backend_host = '127.0.0.1'; backend_port = '18080' }
        $out = New-Object System.Collections.Generic.List[string]
        $inBlaze = $false
        $seen = $false
        foreach ($l in ($gwText -split "`r?`n")) {
            if ($l -match '^\s*\[(.+)\]\s*$') {
                if ($inBlaze) { foreach ($k in $want.Keys) { $out.Add("$k=$($want[$k])") } }
                $inBlaze = ($Matches[1] -eq 'blaze')
                if ($inBlaze) { $seen = $true }
                $out.Add($l)
                continue
            }
            if ($inBlaze -and $l -match '^\s*\w+\s*=') { continue }
            if ($l -ne '' -or -not $inBlaze) { $out.Add($l) }
        }
        if ($inBlaze) { foreach ($k in $want.Keys) { $out.Add("$k=$($want[$k])") } }
        if (-not $seen) { $out.Add('[blaze]'); foreach ($k in $want.Keys) { $out.Add("$k=$($want[$k])") } }
        Set-Content -LiteralPath $gatewayConfig -Value $out -Encoding ASCII
        Write-Note 'gateway.ini: web Autolog set to SSLv3 0.0.0.0:18443 -> HTTP 127.0.0.1:18080'
    }
}

# --- Redirector certificate: make a new one if the game would refuse it -------
Push-Location $root
$eap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'   # the exe writes notes to stderr
try {
    $certOut = & $serverExe '--config' 'config/server.env' '--check-cert' '--fix' 2>&1
    $certExit = $LASTEXITCODE
} finally {
    Pop-Location
    $ErrorActionPreference = $eap
}
if ($certExit -eq 3) { throw 'Could not write the Redirector certificate (certs\protossl_redirector.*).' }
if ($certExit -ne 0) {
    $certOut | ForEach-Object { Write-Note "$_" }
    Write-Note 'Redirector certificate not checked (see above).'
}

# --- gateway + server ----------------------------------------------------------
$exitCode = 0
$gatewayProcess = $null
try {
    Write-Step 'Starting the SSLv3 gateway ...'
    $gatewayProcess = Start-Process -FilePath $gatewayExe -ArgumentList @('config\gateway.ini') -WorkingDirectory $root -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 700
    if ($gatewayProcess.HasExited) { throw "The SSLv3 gateway exited with code $($gatewayProcess.ExitCode). Check logs\gateway.log." }
    Set-Content -LiteralPath (Join-Path $runDir 'legacy-gateway.pid') -Value $gatewayProcess.Id -Encoding ASCII

    Write-Step 'Starting nfsrun-server ...'
    Push-Location $root
    try {
        & $serverExe '--config' 'config/server.env'
        $exitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
} finally {
    Write-Host ''
    if ($gatewayProcess -and -not $gatewayProcess.HasExited) {
        Write-Step 'Stopping the SSLv3 gateway ...'
        Stop-Process -Id $gatewayProcess.Id -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath (Join-Path $runDir 'legacy-gateway.pid') -Force -ErrorAction SilentlyContinue
    if ($startedDatabase) {
        Write-Step 'Stopping MariaDB ...'
        $rp = (Get-Content -LiteralPath $rootKey -Raw).Trim()
        & $mariaClient '--protocol=tcp' "--host=$dbHost" "--port=$dbPort" '--user=root' "--password=$rp" '-e' 'SHUTDOWN;' *> $null
        if ($dbProcess -and -not $dbProcess.HasExited) { $dbProcess.WaitForExit(8000) | Out-Null }
        if ($dbProcess -and -not $dbProcess.HasExited) { Stop-Process -Id $dbProcess.Id -Force -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath (Join-Path $runDir 'mariadb-launcher.pid') -Force -ErrorAction SilentlyContinue
    }
    Write-Host '  Everything stopped.' -ForegroundColor Green
}
exit $exitCode
