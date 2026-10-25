$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'config_utils.ps1')
$root=Get-ProjectRoot
$cfg=Read-EnvFile (Join-Path $root 'config\database.env')
$client=Find-MariaDbExecutable (Join-Path $root 'mariadb\bin') @('mariadb.exe','mysql.exe')
if(-not $client){throw 'MariaDB client not found in mariadb\bin.'}
if(-not (Test-TcpPort ([string]$cfg['DB_HOST']) ([int]$cfg['DB_PORT']) 500)){throw 'MariaDB is not running. Start the server first (start_server.bat), then run this in another window.'}
$sql=@'
SELECT p.name AS persona, l.board_key AS mode, l.event_id AS event,
       CONCAT(FLOOR(l.score/60000),':',LPAD(FLOOR(MOD(l.score,60000)/1000),2,'0'),'.',LPAD(MOD(l.score,1000),3,'0')) AS best_time,
       JSON_VALUE(l.metadata_json,'$.vehicleId') AS vehicle, l.updated_at
FROM leaderboards l JOIN personas p ON p.id=l.persona_id
ORDER BY l.board_key, l.event_id, l.score;
SELECT COUNT(*) AS stored_game_reports FROM game_reports;
'@
& $client '--protocol=tcp' "--host=$($cfg['DB_HOST'])" "--port=$($cfg['DB_PORT'])" "--user=$($cfg['DB_USER'])" "--password=$($cfg['DB_PASSWORD'])" "--database=$($cfg['DB_NAME'])" '--table' '-e' $sql
