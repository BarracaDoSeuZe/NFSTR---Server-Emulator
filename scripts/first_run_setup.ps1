$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config_utils.ps1')

$root = Get-ProjectRoot
$configDir = Join-Path $root 'config'
$logsDir = Join-Path $root 'logs'
$runDir = Join-Path $root 'run'
$mariaRoot = Join-Path $root 'mariadb'
$binDir = Join-Path $mariaRoot 'bin'
$dataDir = Join-Path $mariaRoot 'data'
$dbEnvFile = Join-Path $configDir 'database.env'
$serverEnvFile = Join-Path $configDir 'server.env'
$iniFile = Join-Path $configDir 'my.ini'
$markerFile = Join-Path $configDir '.initialized'
$rootKeyFile = Join-Path $configDir 'mariadb-root.key'
$serverExe = Join-Path $root 'nfsrun-server.exe'
$gatewayExe = Join-Path $root 'legacy_gateway\build\nfsrun-ssl-gateway.exe'
$gatewayConfig = Join-Path $configDir 'gateway.ini'
$schemaFile = Join-Path $PSScriptRoot 'schema.sql'

New-Item -ItemType Directory -Force -Path $configDir, $logsDir, $runDir, (Join-Path $root 'certs') | Out-Null
if (-not (Test-Path -LiteralPath $serverExe)) { throw 'nfsrun-server.exe is missing. Run Build_All.bat first.' }
if (-not (Test-Path -LiteralPath $gatewayExe)) { throw 'legacy gateway is missing. Run Build_All.bat first.' }
if (-not (Test-Path -LiteralPath $binDir)) { throw "MariaDB was not found. Copy your portable MariaDB distribution so this exists: $binDir" }
$mariaServer = Find-MariaDbExecutable $binDir @('mariadbd.exe','mysqld.exe')
$mariaInstaller = Find-MariaDbExecutable $binDir @('mariadb-install-db.exe','mysql_install_db.exe')
$mariaClient = Find-MariaDbExecutable $binDir @('mariadb.exe','mysql.exe')
if (-not $mariaServer -or -not $mariaInstaller -or -not $mariaClient) { throw 'MariaDB bin folder is incomplete (server, installer or client missing).' }

function Ask-Default([string]$Label,[string]$Default){$v=Read-Host "$Label [$Default]";if([string]::IsNullOrWhiteSpace($v)){return $Default};return $v.Trim()}
function Ask-Required([string]$Label){do{$v=Read-Host $Label}while([string]::IsNullOrWhiteSpace($v));return $v.Trim()}
function Normalize-Domain([string]$Value){$v=$Value.Trim().ToLowerInvariant();$v=$v -replace '^https?://','';$v=$v.TrimEnd('/');if($v.Contains('/')){$v=$v.Split('/')[0]};return $v}

Write-Host ''
Write-Host 'NFS The Run Private Server - First Run' -ForegroundColor Cyan
Write-Host 'This formats ONLY this package''s mariadb\data folder.' -ForegroundColor Yellow
Write-Host 'This setup creates local configuration, database data and certificates.' -ForegroundColor Yellow
Write-Host ''

$dbHost = Ask-Default 'DB Host' '127.0.0.1'
$dbPortText = Ask-Default 'DB Port' '1979'
$dbUser = Ask-Default 'DB User' 'NFSRunServer'
$dbPassword = Read-Host 'DB Password [leave blank to generate]'
$dbName = Ask-Default 'DB Name' 'NFSRun'
# The game folder comes first: the patched game exe names the domain the game
# connects to (redirector.<domain>, ...), and the certificate is made for it.
$dsGameDirInput = Read-Host 'Game folder with "Need For Speed The Run.exe" (dedicated race servers; a patched exe also gives the domain) [leave blank to disable]'
$dsEnabled = 'false'
$dsGameDir = ''
$exeDomain = ''
if(-not [string]::IsNullOrWhiteSpace($dsGameDirInput)){
    $candidate = $dsGameDirInput.Trim().Trim('"')
    $candidate = [IO.Path]::GetFullPath($candidate)
    $gameExe = Join-Path $candidate 'Need For Speed The Run.exe'
    if(-not (Test-Path -LiteralPath $gameExe)){throw "Game executable not found: $gameExe"}
    $dsEnabled = 'true'
    $dsGameDir = $candidate
    # stderr of a native exe is an error record under 'Stop' in Windows PowerShell
    $eap=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try{$exeOut = & $serverExe '--exe-domain' $gameExe 2>&1;$exeExit=$LASTEXITCODE}finally{$ErrorActionPreference=$eap}
    if($exeExit -eq 0){
        $exeDomain = (([string]($exeOut | Select-Object -First 1)).Trim()).ToLowerInvariant()
        Write-Host "Base domain read from the game exe: $exeDomain" -ForegroundColor Cyan
    }else{
        Write-Host "The game exe does not give a domain: $($exeOut -join ' ')" -ForegroundColor Yellow
    }
}
if($exeDomain){$baseDomain = $exeDomain}else{$baseDomain = Normalize-Domain (Ask-Required 'Base domain for this server (example: nfsrun.example.org)')}
$publicIP = Ask-Default 'Public IPv4 of this server' '127.0.0.1'
# Launcher API: HTTPS on :8443. Direct = self-signed certificate pinned by the
# player package. Behind Cloudflare = players use the proxied address.
$launcherUrl = Read-Host 'Launcher address behind Cloudflare, e.g. https://play.example.org:8443 [leave blank: direct HTTPS with a self-signed certificate]'
$launcherUrl = $launcherUrl.Trim().TrimEnd('/')
if($launcherUrl -and $launcherUrl -notmatch '^https://[A-Za-z0-9.-]+(:\d+)?$'){throw 'Launcher address must look like https://host[:port].'}
$trustedProxies = if($launcherUrl){'cloudflare'}else{''}

[int]$dbPort=0
if(-not [int]::TryParse($dbPortText,[ref]$dbPort) -or $dbPort -lt 1 -or $dbPort -gt 65535){throw 'DB Port must be 1..65535.'}
if($dbUser -notmatch '^[A-Za-z0-9_]+$' -or $dbName -notmatch '^[A-Za-z0-9_]+$'){throw 'DB user/name may contain only letters, numbers and underscore.'}
if($baseDomain -notmatch '^[a-z0-9.-]+\.[a-z]{2,}$'){throw 'Base domain does not look valid.'}
$redirectorHost = "redirector.$baseDomain"
$nfsHost = "nfs.$baseDomain"
$scertHost = "scert-nfs.$baseDomain"
$stestHost = "stest-nfs.$baseDomain"
$blazeHost = "blaze.$baseDomain"
if($nfsHost.Length -gt 20){throw "Shortest client Redirector slot is 20 characters, but $nfsHost has $($nfsHost.Length). Choose a shorter base domain."}
if($scertHost.Length -gt 26){throw "SCERT Redirector slot is 26 characters, but $scertHost has $($scertHost.Length)."}
if($stestHost.Length -gt 26){throw "STEST Redirector slot is 26 characters, but $stestHost has $($stestHost.Length)."}
if($redirectorHost.Length -gt 27){throw "ONLINE Redirector slot is 27 characters, but $redirectorHost has $($redirectorHost.Length)."}

if([string]::IsNullOrEmpty($dbPassword)){$dbPassword=New-StrongPassword 48;$generatedPassword=$true}else{$generatedPassword=$false}
$rootPassword=New-StrongPassword 56
if(Test-TcpPort $dbHost $dbPort 500){throw "Port $dbPort on $dbHost is already in use. Choose another DB port or stop the service using it."}

Write-Host '[1/7] Formatting portable MariaDB data...'
if(Test-Path -LiteralPath $dataDir){Remove-Item -LiteralPath $dataDir -Recurse -Force}
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
$basedirIni=Convert-ToIniPath $mariaRoot;$datadirIni=Convert-ToIniPath $dataDir;$logIni=Convert-ToIniPath (Join-Path $logsDir 'mariadb.log');$pidIni=Convert-ToIniPath (Join-Path $runDir 'mariadb.pid')
$bindAddress=if($dbHost -ieq 'localhost'){'127.0.0.1'}else{$dbHost}
$ini=@"
[mysqld]
basedir="$basedirIni"
datadir="$datadirIni"
port=$dbPort
bind-address=$bindAddress
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
max_connections=128
log-error="$logIni"
pid-file="$pidIni"

[client]
host=$dbHost
port=$dbPort
default-character-set=utf8mb4
"@
Set-Content -LiteralPath $iniFile -Value $ini -Encoding ASCII

Write-Host '[2/7] Initializing MariaDB system tables...'
Push-Location $mariaRoot
try { & $mariaInstaller "--datadir=$dataDir" "--password=$rootPassword" "--port=$dbPort"; $code=$LASTEXITCODE } finally { Pop-Location }
if($code -ne 0){throw "MariaDB initialization failed ($code)."}

Write-Host '[3/7] Starting temporary MariaDB...'
$defaultsArg='--defaults-file="'+$iniFile+'"'
$dbProcess=Start-Process -FilePath $mariaServer -ArgumentList @($defaultsArg,'--console') -WindowStyle Hidden -PassThru
if(-not (Wait-TcpPort $dbHost $dbPort 35)){if(-not $dbProcess.HasExited){Stop-Process -Id $dbProcess.Id -Force};throw 'MariaDB did not start. Check logs\mariadb.log.'}

Write-Host '[4/7] Creating NFSRun database, local account and schema...'
$bootstrap = @"
CREATE DATABASE IF NOT EXISTS ``$dbName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$dbUser'@'127.0.0.1' IDENTIFIED BY '$dbPassword';
CREATE USER IF NOT EXISTS '$dbUser'@'localhost' IDENTIFIED BY '$dbPassword';
ALTER USER '$dbUser'@'127.0.0.1' IDENTIFIED BY '$dbPassword';
ALTER USER '$dbUser'@'localhost' IDENTIFIED BY '$dbPassword';
GRANT ALL PRIVILEGES ON ``$dbName``.* TO '$dbUser'@'127.0.0.1';
GRANT ALL PRIVILEGES ON ``$dbName``.* TO '$dbUser'@'localhost';
FLUSH PRIVILEGES;
"@
$bootstrap | & $mariaClient '--protocol=tcp' "--host=$dbHost" "--port=$dbPort" '--user=root' "--password=$rootPassword"
if($LASTEXITCODE -ne 0){throw 'Database/user bootstrap failed.'}
Get-Content -LiteralPath $schemaFile -Raw | & $mariaClient '--protocol=tcp' "--host=$dbHost" "--port=$dbPort" "--user=$dbUser" "--password=$dbPassword" "--database=$dbName"
if($LASTEXITCODE -ne 0){throw 'Schema import failed.'}

Write-Host "[5/7] Saving configuration and generating the Old ProtoSSL OTG3 certificate (*.$baseDomain)..."
$dbText=@("DB_HOST=$dbHost","DB_PORT=$dbPort","DB_USER=$dbUser","DB_PASSWORD=$dbPassword","DB_NAME=$dbName") -join "`r`n"
Set-Content -LiteralPath $dbEnvFile -Value ($dbText+"`r`n") -Encoding ASCII
Set-Content -LiteralPath $rootKeyFile -Value ($rootPassword+"`r`n") -Encoding ASCII
$serverText=@(
"# NFS The Run private server. Every option and its default: docs\CONFIGURATION.md",
"",
"# Address players use (domain or IP) and this server's public IPv4.",
"PUBLIC_HOST=$redirectorHost",
"PUBLIC_IP=$publicIP",
"# Redirector domain (nfs., redirector.<domain>): the server and the launcher patch it into their game copies.",
"BASE_DOMAIN=$baseDomain",
"",
"# Launcher address behind Cloudflare (empty = direct, https://PUBLIC_HOST:8443).",
"LAUNCHER_URL=$launcherUrl",
"TRUSTED_PROXIES=$trustedProxies",
"",
"# invite = a new player needs a one-time code (server window: invite <name>)",
"# open   = anyone with the launcher may join",
"AUTH_MODE=invite",
"",
"# Race servers: this PC runs the game exe as dedicated servers.",
"DS_ENABLED=$dsEnabled",
"DS_GAME_DIR=$dsGameDir",
"DS_COUNT=1",
"DS_PUBLIC_IP="
) -join "`r`n"
Set-Content -LiteralPath $serverEnvFile -Value ($serverText+"`r`n") -Encoding ASCII
$gatewayText=@(
"[gateway]",
"cert_file=certs\protossl_redirector.crt",
"key_file=certs\protossl_redirector.key",
"cipher_list=RC4-SHA:RC4-MD5:AES128-SHA:AES256-SHA:DES-CBC3-SHA",
"log_file=logs\gateway.log",
"",
"[redirector]",
"enabled=1",
"name=REDIRECTOR",
"listen_host=127.0.0.1",
"listen_port=42129",
"backend_host=127.0.0.1",
"backend_port=42128",
"",
"[blaze]",
"enabled=1",
"name=WEBAUTOLOG",
"listen_host=0.0.0.0",
"listen_port=18443",
"backend_host=127.0.0.1",
"backend_port=18080"
) -join "`r`n"
Set-Content -LiteralPath $gatewayConfig -Value ($gatewayText+"`r`n") -Encoding ASCII
# Redirector certificate (OTG3 issuer, CN=*.<domain>), made by nfsrun-server.exe.
Push-Location $root
$eap=$ErrorActionPreference;$ErrorActionPreference='Continue'
try{& $serverExe '--config' 'config/server.env' '--make-cert';$certExit=$LASTEXITCODE}finally{Pop-Location;$ErrorActionPreference=$eap}
if($certExit -ne 0){throw 'Old ProtoSSL certificate generation failed.'}

Write-Host '[6/7] Stopping temporary MariaDB and finalizing...'
& $mariaClient '--protocol=tcp' "--host=$dbHost" "--port=$dbPort" '--user=root' "--password=$rootPassword" '-e' 'SHUTDOWN;'
$dbProcess.WaitForExit(10000) | Out-Null
if(-not $dbProcess.HasExited){Stop-Process -Id $dbProcess.Id -Force -ErrorAction SilentlyContinue}
$marker=@('NFS The Run private server initialized',"InitializedAt=$((Get-Date).ToString('o'))","DBPort=$dbPort","DBName=$dbName","BaseDomain=$baseDomain","RedirectorHost=$redirectorHost","LegacyNfsHost=$nfsHost","LegacyScertHost=$scertHost","LegacyStestHost=$stestHost","BlazeHost=$blazeHost") -join "`r`n"
Set-Content -LiteralPath $markerFile -Value ($marker+"`r`n") -Encoding ASCII

Write-Host '[7/7] Creating configured player package...'
$clientPackageScript = Join-Path $PSScriptRoot 'make_client_package.ps1'
if(Test-Path -LiteralPath $clientPackageScript){
    & powershell -NoProfile -ExecutionPolicy Bypass -File $clientPackageScript
    if($LASTEXITCODE -ne 0){Write-Warning 'Player package could not be created. Run scripts\make_client_package.ps1 later.'}
}

Write-Host ''
Write-Host 'Setup complete.' -ForegroundColor Green
Write-Host "Redirector DNS: $nfsHost / $scertHost / $stestHost / $redirectorHost"
Write-Host "Redirector: public Go :42127 -> local SSLv3 :42129 -> Go TDF :42128"
Write-Host "Blaze     : $redirectorHost`:10041 -> Go TDF plaintext :10042 (SSL gateway bypassed)"
Write-Host "Web Autolog: HTTPS $redirectorHost`:18443 -> local HTTP :18080"
if($launcherUrl){Write-Host "Launcher  : $launcherUrl (Cloudflare) -> HTTPS :8443"}else{Write-Host "Launcher  : https://$redirectorHost`:8443 (self-signed, pinned in the player package)"}
Write-Host "Open TCP  : 42127, 10041, 18080, 18443, 8443 (+ UDP for dedicated race servers)"
Write-Host "MariaDB   : $dbHost`:$dbPort / $dbName"
if($generatedPassword){Write-Host "Generated DB password is stored in config\database.env" -ForegroundColor Cyan}
if($dsEnabled -eq 'true'){Write-Host "Dedicated race servers: enabled ($dsGameDir)" -ForegroundColor Cyan}else{Write-Host "Dedicated race servers: disabled (can be enabled later in config\server.env)"}
Write-Host ''
