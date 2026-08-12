[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId,

    [string]$BackendFile = 'infra/environments/dev.backend.hcl',

    [ValidateRange(5, 60)]
    [int]$TimeoutMinutes = 30
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$platformRoot = Join-Path $repositoryRoot 'infra/platform'
$backendPath = Join-Path $repositoryRoot $BackendFile
$manifestPath = Join-Path $repositoryRoot 'config/datasets.json'
$evidenceRoot = Join-Path $repositoryRoot 'docs/evidence/private'
$pipelineName = 'pl_ingest_github_to_bronze'

foreach ($command in @('az', 'terraform')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command is not available: $command"
    }
}

foreach ($path in @($backendPath, $manifestPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required file not found: $path"
    }
}

az account show --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Azure CLI is not authenticated. Run az login and retry.'
}

az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to select the requested Azure subscription.'
}

$env:ARM_SUBSCRIPTION_ID = $SubscriptionId

terraform -chdir=$platformRoot init -input=false -reconfigure -backend-config=$backendPath
if ($LASTEXITCODE -ne 0) {
    throw 'Terraform platform initialization failed.'
}

$dataFactory = terraform -chdir=$platformRoot output -json data_factory | ConvertFrom-Json
$resourceGroup = terraform -chdir=$platformRoot output -json resource_group | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to read the deployed Data Factory and resource group outputs.'
}

$queryStart = (Get-Date).ToUniversalTime().AddMinutes(-2)
$runId = az datafactory pipeline create-run `
    --factory-name $dataFactory.name `
    --resource-group $resourceGroup.name `
    --name $pipelineName `
    --query runId `
    --output tsv
if ($LASTEXITCODE -ne 0 -or -not $runId) {
    throw 'Unable to trigger the ADF ingestion pipeline.'
}

Write-Host "ADF pipeline run started: $runId"
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$status = 'Queued'

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 15
    $status = az datafactory pipeline-run show `
        --factory-name $dataFactory.name `
        --resource-group $resourceGroup.name `
        --run-id $runId `
        --query status `
        --output tsv
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to read the ADF pipeline status.'
    }
    Write-Host "Pipeline status: $status"
    if ($status -in @('Succeeded', 'Failed', 'Cancelled')) {
        break
    }
}

if ($status -ne 'Succeeded') {
    throw "ADF pipeline did not succeed. Final status: $status"
}

$queryEnd = (Get-Date).ToUniversalTime().AddMinutes(2)
$activitiesJson = az datafactory activity-run query-by-pipeline-run `
    --factory-name $dataFactory.name `
    --resource-group $resourceGroup.name `
    --run-id $runId `
    --last-updated-after $queryStart.ToString('o') `
    --last-updated-before $queryEnd.ToString('o') `
    --output json
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to query ADF activity runs.'
}

$activities = $activitiesJson | ConvertFrom-Json
$copyRuns = @($activities | Where-Object { $_.activityName -eq 'CopyDatasetToBronze' })
$metadataRuns = @($activities | Where-Object { $_.activityName -eq 'ValidateBronzeFile' })

if ($copyRuns.Count -ne 10) {
    throw "Expected 10 copy activity runs, found $($copyRuns.Count)."
}
if (@($copyRuns | Where-Object { $_.status -ne 'Succeeded' }).Count -ne 0) {
    throw 'One or more copy activity runs did not succeed.'
}
if ($metadataRuns.Count -ne 10) {
    throw "Expected 10 bronze file checks, found $($metadataRuns.Count)."
}
if (@($metadataRuns | Where-Object { $_.status -ne 'Succeeded' }).Count -ne 0) {
    throw 'One or more bronze file checks did not succeed.'
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$expectedRows = @($manifest | ForEach-Object { [long]$_.expected_rows } | Sort-Object)
$actualRows = @(
    $copyRuns | ForEach-Object {
        $output = $_.output
        if ($output -is [string]) {
            $output = $output | ConvertFrom-Json
        }
        [long]$output.rowsCopied
    } | Sort-Object
)

if (($actualRows -join ',') -ne ($expectedRows -join ',')) {
    throw "Copied row counts do not match the manifest. Expected $expectedRows; found $actualRows."
}

foreach ($run in $metadataRuns) {
    $output = $run.output
    if ($output -is [string]) {
        $output = $output | ConvertFrom-Json
    }
    if ($output.exists -ne $true) {
        throw 'A bronze file metadata check reported that its file does not exist.'
    }
}

New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$evidence = [ordered]@{
    run_id                  = $runId
    pipeline_name           = $pipelineName
    status                  = $status
    copy_iterations         = $copyRuns.Count
    bronze_file_checks      = $metadataRuns.Count
    rows_copied             = ($actualRows | Measure-Object -Sum).Sum
    expected_manifest_rows  = ($expectedRows | Measure-Object -Sum).Sum
    verified_at_utc         = (Get-Date).ToUniversalTime().ToString('o')
}
$evidencePath = Join-Path $evidenceRoot 'adf-ingestion-run.json'
$evidence | ConvertTo-Json | Set-Content -LiteralPath $evidencePath -Encoding utf8

Write-Host 'ADF ingestion verification passed.'
Write-Host 'Copy iterations: 10'
Write-Host 'Bronze file checks: 10'
Write-Host "Rows copied: $($evidence.rows_copied)"
Write-Host "Private evidence: $evidencePath"
