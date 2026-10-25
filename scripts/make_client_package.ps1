# Builds dist\NFSTR_Client\ and dist\NFSTR_Client.zip: everything a player
# needs, nothing from the server.
#
# The launcher in the package has this server built in (nfsrun-server
# --stamp-launcher): address, certificate pin and the Redirector domain it
# patches into its own copy of the game. Players configure nothing and run no
# patch tools. The package has no nfsrun-launcher.ini or .key, so copying a
# newer package over a game folder never replaces a player's login.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$serverExe = Join-Path $root 'nfsrun-server.exe'
$name = 'NFSTR_Client'
$dist = Join-Path $root 'dist'
$out = Join-Path $dist $name
Remove-Item -LiteralPath $out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $out | Out-Null

foreach ($f in 'README.txt', 'THIRD_PARTY_NOTICES.txt') {
  Copy-Item -LiteralPath (Join-Path $root "launcher\$f") -Destination $out
}

$host_ = ''
$envFile = Join-Path $root 'config\server.env'
if (Test-Path $envFile) {
  foreach ($l in Get-Content $envFile) {
    if ($l -match '^\s*PUBLIC_HOST\s*=\s*(.+)$') { $host_ = $Matches[1].Trim() }
  }
}

$launcherOut = Join-Path $out 'nfsrun-launcher.exe'
if (-not (Test-Path $envFile) -or -not $host_ -or $host_ -eq '127.0.0.1') {
  throw 'Set PUBLIC_HOST in config\server.env (the address players use) before making the player package.'
}
Push-Location $root
try {
  $lines = & $serverExe --config 'config/server.env' --launcher-exe 'launcher/nfsrun-launcher.exe' --stamp-launcher $launcherOut
  if ($LASTEXITCODE -ne 0) { throw 'nfsrun-server --stamp-launcher failed (see the message above)' }
} finally { Pop-Location }
$built = @()
foreach ($l in $lines) {
  if ($l -match '^(SERVER_HTTP|SERVER_CERT_PIN|BASE_DOMAIN)=(.+)$') { $built += $l }
}
if (-not ($built -match '^BASE_DOMAIN=')) {
  Write-Warning 'No Redirector domain: set BASE_DOMAIN in config\server.env, or players must patch their game exe with tools\patch_client.bat.'
}

$how = @(
  'NFS The Run - player package',
  '',
  '1. Copy everything from this folder into your game folder,',
  '   next to "Need For Speed The Run.exe" (PC version 1.1.0.0).',
  '2. Start nfsrun-launcher.exe once. It creates nfsrun-launcher.ini;',
  '   set your name and the invite code from the server owner there:',
  '     PLAYER_NAME=YourName',
  '     INVITE_CODE=XXXXX-XXXXX',
  '3. Start nfsrun-launcher.exe again, allow its first-start steps and',
  '   press PLAY.',
  '',
  'Keep nfsrun-launcher.key: it is your login. Details: README.txt'
)
Set-Content -LiteralPath (Join-Path $out 'HOW_TO_PLAY.txt') -Value $how -Encoding ASCII
Set-Content -LiteralPath (Join-Path $out 'SERVER_INFO.txt') -Value (@('Built into nfsrun-launcher.exe:') + $built) -Encoding ASCII

$zip = Join-Path $dist "$name.zip"
Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host "Player package: dist\$name.zip"
