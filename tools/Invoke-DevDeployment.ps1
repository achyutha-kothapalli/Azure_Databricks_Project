[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId,

    [ValidateSet('Plan', 'Apply', 'Verify', 'DestroyPlan')]
    [string]$Action = 'Plan',

    [string]$VariableFile = 'infra/environments/dev.tfvars',

    [string]$BackendFile = 'infra/environments/dev.backend.hcl'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$platformRoot = Join-Path $repositoryRoot 'infra/platform'
$variablePath = Join-Path $repositoryRoot $VariableFile
$backendPath = Join-Path $repositoryRoot $BackendFile
$evidenceRoot = Join-Path $repositoryRoot 'docs/evidence/private'
$planPath = Join-Path $platformRoot 'dev.tfplan'
$destroyPlanPath = Join-Path $platformRoot 'dev-destroy.tfplan'

foreach ($command in @('az', 'terraform')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command is not available: $command"
    }
}

foreach ($path in @($variablePath, $backendPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required local configuration file not found: $path"
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

terraform -chdir=$platformRoot validate
if ($LASTEXITCODE -ne 0) {
    throw 'Terraform platform validation failed.'
}

switch ($Action) {
    'Plan' {
        terraform -chdir=$platformRoot plan -input=false -var-file=$variablePath -out=$planPath
        if ($LASTEXITCODE -ne 0) {
            throw 'Terraform development plan failed.'
        }
        terraform -chdir=$platformRoot show -no-color $planPath
        if ($LASTEXITCODE -ne 0) {
            throw 'Unable to display the development plan.'
        }
    }
    'Apply' {
        if (-not (Test-Path -LiteralPath $planPath)) {
            throw 'No reviewed dev.tfplan exists. Run the Plan action first.'
        }
        terraform -chdir=$platformRoot apply -input=false $planPath
        if ($LASTEXITCODE -ne 0) {
            throw 'Terraform development apply failed.'
        }
    }
    'Verify' {
        terraform -chdir=$platformRoot plan -input=false -detailed-exitcode -var-file=$variablePath
        $planExitCode = $LASTEXITCODE
        if ($planExitCode -eq 2) {
            throw 'The deployed environment has configuration drift or unapplied changes.'
        }
        if ($planExitCode -ne 0) {
            throw 'Terraform idempotence check failed.'
        }

        $resourceGroup = terraform -chdir=$platformRoot output -json resource_group | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) {
            throw 'Unable to read the deployed resource group output.'
        }

        New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
        $resourceEvidence = Join-Path $evidenceRoot 'dev-resources.json'
        az resource list --resource-group $resourceGroup.name --output json |
            Set-Content -LiteralPath $resourceEvidence -Encoding utf8
        if ($LASTEXITCODE -ne 0) {
            throw 'Unable to capture the development resource listing.'
        }

        Write-Host "Deployment is idempotent. Private evidence written to $resourceEvidence."
    }
    'DestroyPlan' {
        terraform -chdir=$platformRoot plan -destroy -input=false -var-file=$variablePath -out=$destroyPlanPath
        if ($LASTEXITCODE -ne 0) {
            throw 'Terraform destroy plan failed.'
        }
        terraform -chdir=$platformRoot show -no-color $destroyPlanPath
        if ($LASTEXITCODE -ne 0) {
            throw 'Unable to display the destroy plan.'
        }
    }
}
