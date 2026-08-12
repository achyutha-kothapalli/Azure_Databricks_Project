# Synapse Serverless SQL Serving Layer

The serving layer publishes eight typed star-schema views and two joined analytical views over the
silver Delta folders. Deployment uses Microsoft Entra authentication, the Synapse workspace managed
identity for ADLS access, and a least-privilege reader principal.

## Design

The ordered SQL files under `synapse/sql` create:

| File | Responsibility |
|---|---|
| `00_database.sql` | UTF-8 serving database and database master key |
| `10_external_access.sql` | `gold` schema, managed-identity credential, and silver data source |
| `20_gold_views.sql` | Six dimensions and two facts with explicit column types |
| `30_semantic_views.sql` | Joined sales and returns detail views with business measures |
| `40_permissions.sql` | Least-privilege reader access |
| `90_verify.sql` | Live object, row-count, and business-key checks |
| `99_destroy.sql` | Explicit removal of the serving database |

`CREATE OR ALTER VIEW` makes repeated deployment safe. The external data source is created once and
deployment fails if an existing object points at a different storage account.

## Delta compatibility boundary

Synapse serverless SQL reads Delta Lake through `OPENROWSET(FORMAT = 'DELTA')`, but its reader does
not support newer features such as deletion vectors, column mapping, or v2 checkpoints. The
Databricks job therefore creates reader-version 1, writer-version 2 tables and disables those
features. The pipeline inspects existing targets and fails before modifying an incompatible table.

This compatibility choice is intentional. If the project later needs newer Delta features, the
serving engine must change or the pipeline must publish a separate compatible serving projection.

Microsoft references:

- [Query Delta Lake with Synapse serverless SQL](https://learn.microsoft.com/azure/synapse-analytics/sql/query-delta-lake-format)
- [Create and use serverless SQL views](https://learn.microsoft.com/azure/synapse-analytics/sql/create-use-views)
- [Control serverless SQL storage access](https://learn.microsoft.com/azure/synapse-analytics/sql/develop-storage-files-storage-access-control)

## Prerequisites

- The Terraform development platform is deployed.
- The Databricks pipeline has successfully created all eight silver Delta folders.
- The Synapse workspace managed identity has `Storage Blob Data Contributor`; Terraform already
  defines this assignment.
- `sqlcmd` is installed and supports Microsoft Entra authentication with `-G`.
- The deploying identity can create databases and users in the workspace serverless SQL endpoint.
- The external reader user or group already exists in Microsoft Entra ID.

Get environment values from Terraform:

```powershell
$synapse = terraform -chdir=infra/platform output -json synapse_workspace |
  ConvertFrom-Json
$storage = terraform -chdir=infra/platform output -json data_lake_storage_account |
  ConvertFrom-Json

$serverEndpoint = "$($synapse.name)-ondemand.sql.azuresynapse.net"
$storageAccount = $storage.name
$databaseName = "adventureworks_dev"
$readerPrincipal = "aw-data-consumers-dev@example.com"
```

Use an Entra security group for `$readerPrincipal` where possible. A user principal is sufficient for
a short portfolio demonstration.

## Local validation

Validation does not contact Azure and does not require `sqlcmd`:

```powershell
.\tools\Invoke-SynapseServing.ps1 `
  -Action Validate `
  -ServerEndpoint $serverEndpoint `
  -DatabaseName $databaseName `
  -StorageAccount $storageAccount `
  -ReaderPrincipal $readerPrincipal
```

The command checks the number of Delta source views and gold views and rejects Parquet references,
legacy placeholders, or `SELECT *`.

## Deploy twice

Read the database master-key password as a secure value. Keep it in a password manager so the
database key can be recovered if required.

```powershell
$masterKeyPassword = Read-Host "Database master-key password" -AsSecureString

$common = @{
  ServerEndpoint = $serverEndpoint
  DatabaseName = $databaseName
  StorageAccount = $storageAccount
  ReaderPrincipal = $readerPrincipal
}

.\tools\Invoke-SynapseServing.ps1 @common `
  -Action Deploy `
  -MasterKeyPassword $masterKeyPassword `
  -ConfirmDeploy
```

Run the same deployment command a second time. Correct means both executions succeed, the database
is not recreated, the external data source remains unchanged, and all views are altered in place.
The secure password is substituted in memory and SQL is sent to `sqlcmd` through standard input; the
password is not placed on the process command line or written to an artifact.

## Live verification

```powershell
.\tools\Invoke-SynapseServing.ps1 @common -Action Verify
```

Verification fails unless all ten views exist, fact business keys are unique, and these row counts
match:

| View | Expected rows |
|---|---:|
| `gold.dim_date` | 912 |
| `gold.dim_customer` | 18,148 |
| `gold.dim_product_category` | 4 |
| `gold.dim_product_subcategory` | 37 |
| `gold.dim_product` | 293 |
| `gold.dim_territory` | 10 |
| `gold.fact_sales` | 56,046 |
| `gold.fact_returns` | 1,809 |

The two consumer views are:

- `gold.sales_detail`, including customer, product hierarchy, territory, quantity, price, and
  calculated sales amount
- `gold.returns_detail`, including product hierarchy, territory, quantity, cost, and calculated
  return cost

Raw verification output is written under `docs/evidence/private/synapse`, which Git ignores. Publish
only redacted screenshots or a short result summary.

Synapse serverless SQL has no provisioned SQL pool in this design. Queries are charged according to
data scanned, so avoid repeated broad scans outside the small verification dataset.

## Reader permissions

The external reader principal receives:

- `SELECT` on the `gold` schema
- `REFERENCES` on the managed-identity database credential
- An explicit denial of `ADMINISTER DATABASE BULK OPERATIONS`

The principal does not receive database control, object-definition permission, or unrestricted bulk
file access.

## Cleanup

The serving database does not create provisioned compute. Remove it when the demonstration database
is no longer required:

```powershell
.\tools\Invoke-SynapseServing.ps1 @common -Action Destroy -ConfirmDestroy
```

This command deletes only the serving database and its contained objects. Terraform remains the
owner of the Synapse workspace and removes it during the wider platform cleanup.
