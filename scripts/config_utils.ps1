function Get-ProjectRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

function Read-EnvFile([string]$Path) {
    $result = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $result
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        $idx = $trimmed.IndexOf('=')
        if ($idx -lt 1) { continue }
        $key = $trimmed.Substring(0, $idx).Trim()
        $value = $trimmed.Substring($idx + 1)
        $result[$key] = $value
    }
    return $result
}

function Set-ProcessEnvFromFile([string]$Path) {
    $values = Read-EnvFile $Path
    foreach ($key in $values.Keys) {
        [Environment]::SetEnvironmentVariable($key, [string]$values[$key], 'Process')
    }
    return $values
}

function New-StrongPassword([int]$Length = 48) {
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789_-'
    $bytes = New-Object byte[] ($Length)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }

    $chars = New-Object System.Collections.Generic.List[char]
    foreach ($b in $bytes) {
        $chars.Add($alphabet[$b % $alphabet.Length])
    }
    return -join $chars
}

function Find-MariaDbExecutable([string]$BinDir, [string[]]$Names) {
    foreach ($name in $Names) {
        $candidate = Join-Path $BinDir $name
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return $null
}

function Test-TcpPort([string]$HostName, [int]$Port, [int]$TimeoutMs = 350) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }
        $client.EndConnect($async)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Wait-TcpPort([string]$HostName, [int]$Port, [int]$TimeoutSeconds = 30) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-TcpPort $HostName $Port 500) { return $true }
        Start-Sleep -Milliseconds 300
    }
    return $false
}

function Convert-ToIniPath([string]$Path) {
    return $Path.Replace('\\', '/').Replace('\', '/')
}
