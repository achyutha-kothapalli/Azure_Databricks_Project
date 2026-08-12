[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Validate', 'Plan', 'Deploy', 'Verify', 'RunTwice', 'Destroy')]
    [string]$Action,

    [Parameter(Mandatory)]
    [ValidatePattern('^https://adb-[0-9]+\.[0-9]+\.azuredatabricks\.net/?$')]
    [string]$WorkspaceHost,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$StorageAccount,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$RunAsServicePrincipal,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OperatorGroup,

    [ValidateSet('dev')]
    [string]$Target = 'dev',

    [string]$Profile,

    [switch]$ConfirmCost,

    [switch]$ConfirmDestroy
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$bundleRoot = Join-Path $repositoryRoot 'databricks'
$jobDefinition = Join-Path $bundleRoot 'resources/job.yml'
$evidenceRoot = Join-Path $repositoryRoot 'docs/evidence/private/databricks'

foreach ($command in @('databricks', 'python')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command is not available: $command"
    }
}

$jobContent = Get-Content -LiteralPath $jobDefinition -Raw
foreach ($requiredControl in @(
    'num_workers: 0',
    'spark.databricks.cluster.profile: singleNode',
    'max_concurrent_runs: 1',
    'timeout_seconds: 1800',
    'max_retries: 0'
)) {
    if (-not $jobContent.Contains($requiredControl)) {
        throw "Cost control is missing from the Databricks job: $requiredControl"
    }
}
if ($jobContent -match '(?m)^\s*existing_cluster_id:') {
    throw 'The bundle must use terminating job compute, not an existing all-purpose cluster.'
}

$env:DATABRICKS_HOST = $WorkspaceHost.TrimEnd('/')
if (-not $Profile) {
    $env:DATABRICKS_AUTH_TYPE = 'azure-cli'
}

$bundleVariables = @(
    '--var', "storage_account=$StorageAccount",
    '--var', "run_as_service_principal=$RunAsServicePrincipal",
    '--var', "operator_group=$OperatorGroup"
)
$profileArguments = if ($Profile) { @('--profile', $Profile) } else { @() }

function Invoke-BundleCommand {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [switch]$CaptureJson
    )

    $allArguments = @('bundle') + $Arguments + @('-t', $Target) + $bundleVariables + $profileArguments
    Write-Host "databricks $($allArguments -join ' ')"

    if ($CaptureJson) {
        $output = & databricks @allArguments 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Databricks command failed:`n$($output -join [Environment]::NewLine)"
        }
        return $output -join [Environment]::NewLine
    }

    & databricks @allArguments
    if ($LASTEXITCODE -ne 0) {
        throw 'Databricks command failed.'
    }
}

function Get-DeployedJobId {
    $summaryText = Invoke-BundleCommand -Arguments @('summary', '--force-pull', '-o', 'json') -CaptureJson
    $summary = $summaryText | ConvertFrom-Json
    $jobId = $summary.resources.jobs.silver_pipeline.id
    if (-not $jobId) {
        throw 'The deployed silver_pipeline job ID was not found in the bundle summary.'
    }
    return [string]$jobId
}

Push-Location $bundleRoot
try {
    switch ($Action) {
        'Validate' {
            Invoke-BundleCommand -Arguments @('validate', '--strict')
        }
        'Plan' {
            Invoke-BundleCommand -Arguments @('validate', '--strict')
            Invoke-BundleCommand -Arguments @('plan')
        }
        'Deploy' {
            if (-not $ConfirmCost) {
                throw 'Rerun with -ConfirmCost after reviewing the bundle plan and Azure cost controls.'
            }
            Invoke-BundleCommand -Arguments @('validate', '--strict')
            Invoke-BundleCommand -Arguments @('plan')
            Invoke-BundleCommand -Arguments @('deploy', '--fail-on-active-runs')
            Write-Host "Deployed Databricks job ID: $(Get-DeployedJobId)"
        }
        'Verify' {
            $jobIdBefore = Get-DeployedJobId
            Invoke-BundleCommand -Arguments @('deploy', '--fail-on-active-runs')
            $jobIdAfter = Get-DeployedJobId
            if ($jobIdBefore -ne $jobIdAfter) {
                throw "Bundle redeployment replaced the job: $jobIdBefore -> $jobIdAfter"
            }
            Write-Host "Idempotent deployment verified for job ID: $jobIdAfter"
        }
        'RunTwice' {
            if (-not $ConfirmCost) {
                throw 'Rerun with -ConfirmCost to start two short-lived Databricks job clusters.'
            }
            New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
            $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            foreach ($sequence in 1..2) {
                $runId = "portfolio-$timestamp-$sequence"
                $output = Invoke-BundleCommand `
                    -Arguments @(
                        'run', '-o', 'json', 'silver_pipeline',
                        '--params', "run_id=$runId"
                    ) `
                    -CaptureJson
                $outputPath = Join-Path $evidenceRoot "run-$timestamp-$sequence.json"
                Set-Content -LiteralPath $outputPath -Value $output -Encoding utf8
                Write-Host "Completed run $sequence; private evidence: $outputPath"
            }
            Write-Host 'Both runs succeeded. Compare silver row counts in the two saved outputs.'
        }
        'Destroy' {
            if (-not $ConfirmDestroy) {
                throw 'Rerun with -ConfirmDestroy to delete the deployed bundle job and workspace files.'
            }
            Invoke-BundleCommand -Arguments @('destroy', '--auto-approve')
            Write-Host 'Databricks bundle resources were removed.'
        }
    }
}
finally {
    Pop-Location
}
