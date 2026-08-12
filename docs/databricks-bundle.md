# Databricks Bundle Deployment

The Databricks workload is packaged as a Python wheel and deployed as a job through a Databricks
bundle. Development uses a single-node job cluster that terminates when the run finishes. Test and
production targets reuse the same definition but are configuration-only for this portfolio.

## Deployment design

The bundle defines:

- A wheel artifact built from `src/adventure_works`
- One parameterized bronze-to-silver job
- A short-lived single-node cluster with no all-purpose compute
- A 30-minute task timeout, no automatic retry, and one concurrent run
- A service-principal run identity and group-based job permissions
- Failure notification to an externally supplied operations mailbox
- OAuth access to ADLS using a secret reference, never a checked-in credential
- Separate `dev`, `test`, and `prod` targets

The workspace URL, tenant, storage account, application IDs, and group name are supplied at command
time. The client secret is stored in a Databricks-backed secret scope and is referenced by name from
the cluster configuration.

## Prerequisites

- The Terraform development platform is deployed with `deploy_databricks = true`.
- Azure CLI and Databricks CLI are installed and authenticated.
- The signed-in Azure identity is a Databricks workspace administrator for the one-time setup.
- Bronze ingestion has completed successfully.
- Python 3.11 has the project development dependencies installed.

Get the generated names without copying them into tracked files:

```powershell
$subscriptionId = "00000000-0000-0000-0000-000000000000"
az account set --subscription $subscriptionId

$workspace = terraform -chdir=infra/platform output -json databricks_workspace |
  ConvertFrom-Json
$storage = terraform -chdir=infra/platform output -json data_lake_storage_account |
  ConvertFrom-Json

$workspaceHost = "https://$($workspace.workspace_url)"
$storageAccount = $storage.name
$storageId = $storage.id
$tenantId = az account show --query tenantId -o tsv
$operatorGroup = "aw-data-platform-operators"
$alertEmail = "data-platform-alerts@example.com"
```

## One-time identity and secret setup

Create a development-only service principal with data-plane access to the lake. Capture its secret
only in the current PowerShell session:

```powershell
$credential = az ad sp create-for-rbac `
  --name "aw-dbx-job-dev" `
  --role "Storage Blob Data Contributor" `
  --scopes $storageId `
  --output json | ConvertFrom-Json

$applicationId = $credential.appId
```

Register that identity in the workspace, create the operator group, and add the service principal to
the group. If either object already exists, retrieve it with the corresponding `list --filter`
command instead of creating a duplicate.

```powershell
$env:DATABRICKS_HOST = $workspaceHost
$env:DATABRICKS_AUTH_TYPE = "azure-cli"

databricks service-principals create `
  --application-id $applicationId `
  --display-name "aw-dbx-job-dev"

$servicePrincipal = databricks service-principals list `
  --filter "applicationId eq '$applicationId'" `
  --output json | ConvertFrom-Json

databricks groups create --display-name $operatorGroup
$group = databricks groups list `
  --filter "displayName eq '$operatorGroup'" `
  --output json | ConvertFrom-Json

$membership = @{
  Operations = @(
    @{
      op = "add"
      path = "members"
      value = @(@{ value = $servicePrincipal.Resources[0].id })
    }
  )
} | ConvertTo-Json -Depth 6 -Compress

databricks groups patch $group.Resources[0].id --json $membership
```

Create the scope, store the credential without printing it, and grant the operator group read access:

```powershell
$secretScope = "adventure-works"
$secretKey = "storage-client-secret"

databricks secrets create-scope $secretScope
$credential.password | databricks secrets put-secret $secretScope $secretKey
databricks secrets put-acl $secretScope $operatorGroup READ
$credential.password = $null
```

Do not place the credential in a profile, script, variable file, screenshot, terminal transcript, or
GitHub secret. Delete the development service principal after the demonstration is removed.

## Validate and review

Install the local package and validate its wheel:

```powershell
python -m pip install -e ".[dev,spark]"
python -m build --wheel --no-isolation
```

Validate the bundle against the real workspace, then review the deployment plan:

```powershell
$common = @{
  WorkspaceHost = $workspaceHost
  StorageAccount = $storageAccount
  TenantId = $tenantId
  StorageClientId = $applicationId
  RunAsServicePrincipal = $applicationId
  OperatorGroup = $operatorGroup
  AlertEmail = $alertEmail
}

.\tools\Invoke-DatabricksBundle.ps1 @common -Action Validate
.\tools\Invoke-DatabricksBundle.ps1 @common -Action Plan
```

The plan must contain one job and its bundle files. It must not contain an all-purpose cluster or an
unrelated workspace resource.

## Deploy and verify

Deployment is deliberately blocked until the cost confirmation switch is present:

```powershell
.\tools\Invoke-DatabricksBundle.ps1 @common -Action Deploy -ConfirmCost
.\tools\Invoke-DatabricksBundle.ps1 @common -Action Verify
```

`Verify` deploys the unchanged bundle again and fails if the logical job resolves to a different job
ID. This proves that deployment updates the managed job rather than creating a duplicate.

Run the pipeline twice against the same bronze snapshot:

```powershell
.\tools\Invoke-DatabricksBundle.ps1 @common -Action RunTwice -ConfirmCost
```

Both runs must succeed and report the same row counts:

| Target | Run 1 | Run 2 |
|---|---:|---:|
| calendar | 912 | 912 |
| customers | 18,148 | 18,148 |
| product_categories | 4 | 4 |
| product_subcategories | 37 | 37 |
| products | 293 | 293 |
| returns | 1,809 | 1,809 |
| sales | 56,046 | 56,046 |
| territories | 10 | 10 |

The command stores raw run output under `docs/evidence/private/databricks`, which Git ignores. Check
that both job clusters terminate and that the second run does not add fact rows.

## Mandatory cleanup

Remove the bundle resources before removing the workspace:

```powershell
.\tools\Invoke-DatabricksBundle.ps1 @common -Action Destroy -ConfirmDestroy
```

Then set `deploy_databricks = false` in the ignored development tfvars file, review the dedicated
Terraform removal plan, and apply it:

```powershell
.\tools\Remove-DatabricksWorkspace.ps1 -SubscriptionId $subscriptionId
.\tools\Remove-DatabricksWorkspace.ps1 -SubscriptionId $subscriptionId -Apply
```

Cleanup is complete only when that command confirms all three conditions:

- The Databricks workspace is absent.
- The Databricks managed resource group is absent.
- No NAT Gateway remains in the managed resource group.

Finally remove the development-only application registration:

```powershell
az ad app delete --id $applicationId
```

Do not stop after terminating the job cluster. A NAT Gateway in the Databricks managed resource group
can continue billing until the workspace and managed resource group are removed.

## Local verification

Run before opening the pull request:

```powershell
python -m pytest -q tests/test_databricks_bundle_contract.py
python -m ruff check src tests tools
python tools/validate_repository.py
git diff --check
```
