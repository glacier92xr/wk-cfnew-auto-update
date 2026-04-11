# step-kv.ps1 - Create KV Namespace and bind to Worker
# Usage: .\step-kv.ps1 <KVName>

param(
    [Parameter(Mandatory=$true)]
    [string]$KvName
)

$ErrorActionPreference = "Continue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$WranglerToml = Join-Path $ProjectDir "wrangler.toml"
$LogFile = Join-Path $ScriptDir "step-kv.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "[$timestamp] $Message"
    Write-Host $logMsg
    Add-Content -Path $LogFile -Value $logMsg -Encoding UTF8
}

function Write-Err {
    param([string]$Message)
    Write-Host "ERROR: $Message" -ForegroundColor Red
    Write-Log "ERROR: $Message"
}

function Generate-RandomSuffix {
    $chars = "0123456789abcdefghijklmnopqrstuvwxyz"
    $result = ""
    for ($i = 0; $i -lt 3; $i++) {
        $result += $chars[(Get-Random -Maximum $chars.Length)]
    }
    return $result
}

function Test-KvExists {
    param([string]$Name)
    try {
        $output = npx wrangler kv namespace list 2>&1 | Out-String
        if ($output -match "\[") {
            $json = $output | ConvertFrom-Json
            if ($json -is [Array]) {
                return ($null -ne ($json | Where-Object { $_.title -eq $Name }))
            } elseif ($null -ne $json) {
                return ($json.title -eq $Name)
            }
        }
        return $false
    } catch {
        Write-Log "Test-KvExists error: $_"
        return $false
    }
}

function New-KvNamespace {
    param([string]$Name)

    Write-Log "Creating KV namespace: $Name"

    $output = npx wrangler kv namespace create $Name --binding "C" --update-config 2>&1 | Out-String

    Write-Log "Wrangler output: $output"

    if ($output -match "id = `"(.*?)`"") {
        $kvId = $matches[1]
        Write-Log "Extracted KV ID: $kvId"
        return $kvId
    }

    Write-Err "Failed to extract KV ID from output"
    Write-Err "Output was: $output"
    return $null
}

function Update-WranglerToml {
    param([string]$KvId)

    Write-Log "Updating wrangler.toml with KV ID: $KvId"

    if (-not (Test-Path $WranglerToml)) {
        Write-Err "wrangler.toml not found"
        return $false
    }

    $content = Get-Content $WranglerToml -Raw -Encoding UTF8

    $newContent = $content.TrimEnd() + "`n`n[[kv_namespaces]]`n`nbinding = `"C`"`nid = `"$KvId`""

    Set-Content -Path $WranglerToml -Value $newContent -Encoding UTF8 -NoNewline

    Write-Log "wrangler.toml updated successfully"
    return $true
}

# Main
Write-Host ""
Write-Host "========== KV Creation Script ==========" -ForegroundColor Cyan
Write-Log "Starting KV creation for: $KvName"

Set-Location $ProjectDir

# Generate unique name
$finalName = $KvName
$maxAttempts = 10
$attempt = 0

while ($attempt -lt $maxAttempts) {
    if (-not (Test-KvExists -Name $finalName)) {
        break
    }
    Write-Log "KV '$finalName' exists, generating new name..."
    $suffix = Generate-RandomSuffix
    $finalName = "$KvName$suffix"
    $attempt++
}

if ($attempt -ge $maxAttempts) {
    Write-Err "Failed to generate unique name after $maxAttempts attempts"
    exit 1
}

Write-Host "Using KV name: $finalName" -ForegroundColor Yellow

# Create KV
$kvId = New-KvNamespace -Name $finalName

if ([string]::IsNullOrEmpty($kvId)) {
    Write-Err "Failed to create KV namespace"
    exit 1
}

Write-Host "KV created with ID: $kvId" -ForegroundColor Green

# Update wrangler.toml
$success = Update-WranglerToml -KvId $kvId

if (-not $success) {
    Write-Err "Failed to update wrangler.toml"
    exit 1
}

Write-Host ""
Write-Host "========== SUCCESS ==========" -ForegroundColor Green
Write-Host "KV Name: $finalName"
Write-Host "KV ID: $kvId"
Write-Host "wrangler.toml: Updated"
Write-Host ""
Write-Host "Next: run 'npm run deploy' to deploy Worker"
Write-Log "Script completed successfully"
