[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Validate', 'Deploy', 'Verify', 'Destroy')]
    [string]$Action,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9-]+-ondemand\.sql\.azuresynapse\.net$')]
    [string]$ServerEndpoint,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z][a-z0-9_]{2,62}$')]
    [string]$DatabaseName,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$StorageAccount,

    [Security.SecureString]$MasterKeyPassword,

    [switch]$ConfirmDeploy,

    [switch]$ConfirmDestroy
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$sqlRoot = Join-Path $repositoryRoot 'synapse/sql'
$evidenceRoot = Join-Path $repositoryRoot 'docs/evidence/private/synapse'
$deploymentFiles = @(
    '00_database.sql',
    '10_external_access.sql',
    '20_gold_views.sql',
    '30_semantic_views.sql'
)
$requiredFiles = $deploymentFiles + @('90_verify.sql', '99_destroy.sql')

foreach ($file in $requiredFiles) {
    $path = Join-Path $sqlRoot $file
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required Synapse SQL file is missing: $path"
    }
}

$productionSql = $requiredFiles |
    ForEach-Object { Get-Content -LiteralPath (Join-Path $sqlRoot $_) -Raw }
$combinedSql = $productionSql -join [Environment]::NewLine

if ($combinedSql -match '<datalake_name>|FORMAT\s*=\s*''PARQUET''') {
    throw 'Production Synapse SQL contains a legacy placeholder or Parquet source.'
}
if ($combinedSql -match '(?im)SELECT\s+\*') {
    throw 'Production Synapse SQL must use explicit column projections.'
}
if (($combinedSql | Select-String -Pattern "FORMAT = 'DELTA'" -AllMatches).Matches.Count -ne 8) {
    throw 'Expected exactly eight typed Delta source views.'
}
if (($combinedSql | Select-String -Pattern 'CREATE OR ALTER VIEW \[gold\]' -AllMatches).Matches.Count -ne 10) {
    throw 'Expected exactly ten idempotent gold views.'
}

if ($Action -eq 'Validate') {
    Write-Host 'Synapse serving SQL validation passed.'
    Write-Host '  Typed Delta source views: 8'
    Write-Host '  Gold views: 10'
    Write-Host '  Legacy placeholders and SELECT *: absent'
    exit 0
}

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    throw 'Required command is not available: sqlcmd'
}

function Get-PlainText {
    param(
        [Parameter(Mandatory)]
        [Security.SecureString]$SecureValue
    )

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Invoke-SynapseSqlFile {
    param(
        [Parameter(Mandatory)]
        [string]$FileName,

        [Security.SecureString]$DatabaseMasterKey,

        [string]$EvidencePath
    )

    $path = Join-Path $sqlRoot $FileName
    $renderedSql = (Get-Content -LiteralPath $path -Raw).Replace(
        '$(DatabaseName)',
        $DatabaseName
    ).Replace(
        '$(StorageAccount)',
        $StorageAccount
    )

    if ($renderedSql.Contains('$(MasterKeyPassword)')) {
        if ($null -eq $DatabaseMasterKey) {
            throw 'MasterKeyPassword is required to initialize the serving database.'
        }
        $plainText = Get-PlainText -SecureValue $DatabaseMasterKey
        try {
            $renderedSql = $renderedSql.Replace(
                '$(MasterKeyPassword)',
                $plainText.Replace("'", "''")
            )
        }
        finally {
            $plainText = $null
        }
    }

    Write-Host "Executing Synapse SQL file: $FileName"
    $output = $renderedSql | & sqlcmd `
        -S $ServerEndpoint `
        -d master `
        -G `
        -b `
        -r 1 `
        -l 30 `
        -W `
        -w 65535 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Synapse SQL execution failed for ${FileName}:`n$($output -join [Environment]::NewLine)"
    }

    if ($EvidencePath) {
        Set-Content -LiteralPath $EvidencePath -Value $output -Encoding utf8
    }
    else {
        Write-Host ($output -join [Environment]::NewLine)
    }
}

switch ($Action) {
    'Deploy' {
        if (-not $ConfirmDeploy) {
            throw 'Rerun with -ConfirmDeploy after reviewing the ordered SQL files.'
        }
        if ($null -eq $MasterKeyPassword) {
            throw 'MasterKeyPassword is required for deployment. Supply a SecureString.'
        }
        foreach ($file in $deploymentFiles) {
            Invoke-SynapseSqlFile -FileName $file -DatabaseMasterKey $MasterKeyPassword
        }
        Write-Host "Synapse serving objects deployed to database: $DatabaseName"
    }
    'Verify' {
        New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $evidencePath = Join-Path $evidenceRoot "verification-$timestamp.txt"
        Invoke-SynapseSqlFile -FileName '90_verify.sql' -EvidencePath $evidencePath
        Write-Host "Synapse verification passed; private evidence: $evidencePath"
    }
    'Destroy' {
        if (-not $ConfirmDestroy) {
            throw 'Rerun with -ConfirmDestroy to remove the serving database and its objects.'
        }
        Invoke-SynapseSqlFile -FileName '99_destroy.sql'
        Write-Host "Synapse serving database removed: $DatabaseName"
    }
}
