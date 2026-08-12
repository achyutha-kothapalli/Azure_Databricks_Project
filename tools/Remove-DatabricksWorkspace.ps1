[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId,

    [string]$VariableFile = 'infra/environments/dev.tfvars',

    [string]$BackendFile = 'infra/environments/dev.backend.hcl',

    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$platformRoot = Join-Path $repositoryRoot 'infra/platform'
$variablePath = Join-Path $repositoryRoot $VariableFile
$backendPath = Join-Path $repositoryRoot $BackendFile
$planPath = Join-Path $platformRoot 'databricks-removal.tfplan'

function Get-TerraformStringValue {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $match = [regex]::Match(
        $Content,
        "(?m)^\s*$([regex]::Escape($Name))\s*=\s*`"([^`"]+)`"\s*$"
    )
    if (-not $match.Success) {
        throw "Required Terraform value is missing from ${VariableFile}: $Name"
    }
    return $match.Groups[1].Value
}

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

$variableContent = Get-Content -LiteralPath $variablePath -Raw
$environment = Get-TerraformStringValue -Content $variableContent -Name 'environment'
$regionCode = Get-TerraformStringValue -Content $variableContent -Name 'region_code'
$uniqueSuffix = Get-TerraformStringValue -Content $variableContent -Name 'unique_suffix'

if ($environment -ne 'dev') {
    throw "This portfolio cleanup command is restricted to dev; found: $environment"
}

$nameSuffix = "$environment-$regionCode-$uniqueSuffix"
$resourceGroupName = "aw-rg-$nameSuffix"
$workspaceName = "aw-dbw-$nameSuffix"
$managedResourceGroupName = "aw-dbw-mrg-$nameSuffix"

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

terraform -chdir=$platformRoot plan `
    -input=false `
    -var-file=$variablePath `
    -var='deploy_databricks=false' `
    -out=$planPath
if ($LASTEXITCODE -ne 0) {
    throw 'Databricks removal plan failed.'
}

terraform -chdir=$platformRoot show -no-color $planPath
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to display the Databricks removal plan.'
}

if (-not $Apply) {
    Write-Host 'Review the plan and confirm that it removes Databricks resources only.'
    Write-Host 'Rerun this command with -Apply to execute the saved removal plan.'
    exit 0
}

terraform -chdir=$platformRoot apply -input=false $planPath
if ($LASTEXITCODE -ne 0) {
    throw 'Databricks workspace removal failed.'
}

$workspaceDeleted = $false
for ($attempt = 1; $attempt -le 120; $attempt++) {
    $workspaceId = az databricks workspace show `
        --resource-group $resourceGroupName `
        --name $workspaceName `
        --query id `
        --output tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $workspaceId) {
        $workspaceDeleted = $true
        break
    }
    Start-Sleep -Seconds 15
}
if (-not $workspaceDeleted) {
    throw "Timed out waiting for the Databricks workspace to be deleted: $workspaceName"
}

$managedGroupExists = az group exists --name $managedResourceGroupName --output tsv
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to check the Databricks managed resource group.'
}

if ($managedGroupExists -eq 'true') {
    Write-Host "Deleting orphaned Databricks managed resource group: $managedResourceGroupName"
    az group delete --name $managedResourceGroupName --yes --no-wait
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to start deletion of the Databricks managed resource group.'
    }

    az group wait --name $managedResourceGroupName --deleted --interval 15 --timeout 1800
    if ($LASTEXITCODE -ne 0) {
        throw 'Timed out waiting for the Databricks managed resource group to be deleted.'
    }
}

$managedGroupExists = az group exists --name $managedResourceGroupName --output tsv
if ($LASTEXITCODE -ne 0 -or $managedGroupExists -ne 'false') {
    throw "Databricks managed resource group still exists: $managedResourceGroupName"
}

$natGateways = az network nat gateway list `
    --query "[?resourceGroup=='$managedResourceGroupName'].id" `
    --output tsv
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to verify NAT Gateway removal.'
}
if ($natGateways) {
    throw "NAT Gateway resources still exist in ${managedResourceGroupName}: $natGateways"
}

Write-Host "Databricks workspace deleted: $workspaceName"
Write-Host "Managed resource group deleted: $managedResourceGroupName"
Write-Host 'NAT Gateway verification passed: no matching resources remain.'
