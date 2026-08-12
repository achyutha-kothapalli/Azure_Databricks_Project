[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId,

    [string]$VariableFile = 'infra/bootstrap/bootstrap.tfvars',

    [string]$BackendFile = 'infra/environments/dev.backend.hcl',

    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$bootstrapRoot = Join-Path $repositoryRoot 'infra/bootstrap'
$variablePath = Join-Path $repositoryRoot $VariableFile
$backendPath = Join-Path $repositoryRoot $BackendFile
$planPath = Join-Path $bootstrapRoot 'bootstrap.tfplan'

foreach ($command in @('az', 'terraform')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command is not available: $command"
    }
}

if (-not (Test-Path -LiteralPath $variablePath)) {
    throw "Bootstrap variable file not found: $VariableFile. Copy bootstrap.tfvars.example first."
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

terraform -chdir=$bootstrapRoot init -input=false
if ($LASTEXITCODE -ne 0) {
    throw 'Terraform bootstrap initialization failed.'
}

terraform -chdir=$bootstrapRoot validate
if ($LASTEXITCODE -ne 0) {
    throw 'Terraform bootstrap validation failed.'
}

terraform -chdir=$bootstrapRoot plan -input=false -var-file=$variablePath -out=$planPath
if ($LASTEXITCODE -ne 0) {
    throw 'Terraform bootstrap plan failed.'
}

terraform -chdir=$bootstrapRoot show -no-color $planPath
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to display the bootstrap plan.'
}

if (-not $Apply) {
    Write-Host 'Bootstrap plan completed. Review it, then rerun with -Apply.'
    exit 0
}

terraform -chdir=$bootstrapRoot apply -input=false $planPath
if ($LASTEXITCODE -ne 0) {
    throw 'Terraform state bootstrap apply failed.'
}

$backend = terraform -chdir=$bootstrapRoot output -json backend | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to read bootstrap outputs.'
}

$backendDirectory = Split-Path -Parent $backendPath
New-Item -ItemType Directory -Path $backendDirectory -Force | Out-Null

@"
resource_group_name  = "$($backend.resource_group_name)"
storage_account_name = "$($backend.storage_account_name)"
container_name       = "$($backend.container_name)"
key                  = "adventure-works/dev/platform.tfstate"
use_azuread_auth     = true
use_cli              = true
"@ | Set-Content -LiteralPath $backendPath -Encoding utf8

Write-Host "Remote state is ready. Backend configuration written to $BackendFile."
