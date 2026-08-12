# Metadata-Driven ADF Ingestion

Azure Data Factory loads the ten Adventure Works CSV files from a commit-pinned GitHub revision into
the ADLS Gen2 bronze filesystem. The factory artifacts are defined in Terraform and require no
manual construction in ADF Studio.

## Design

`config/datasets.json` is the canonical ingestion manifest. Every entry defines:

- A lowercase logical dataset name
- A repository-relative source path
- A bronze folder and filename
- The expected source row count

The pipeline `pl_ingest_github_to_bronze` performs these activities:

1. `LookupDatasetManifest` reads the JSON manifest through anonymous HTTPS.
2. `ForEachDataset` iterates through all entries with a maximum parallel batch count of five.
3. `CopyDatasetToBronze` passes the source path and bronze destination into parameterized datasets.
4. `ValidateBronzeFile` reads metadata for the copied file.
5. `EnsureBronzeFileExists` raises `BRONZE_FILE_MISSING` when the exact sink object is unavailable.

The ADLS linked service uses the Data Factory system-assigned managed identity. No storage account
key, SAS token, service-principal secret, or GitHub credential is stored in Terraform or ADF JSON.
The role assignment in `infra/platform/role-assignments.tf` grants the factory the required data-plane
access.

## Reproducible source revision

`adf_source_base_url` must be a raw GitHub URL containing a full 40-character commit SHA. Branch URLs
such as `main` and `develop` are rejected by Terraform validation because their contents can change
between deployments.

When source data or the manifest changes, merge the change first and update all environment examples
to the new commit SHA in a reviewed commit.

## Deploy the artifacts

Complete the development platform deployment in `docs/deployment.md`. Keep Databricks disabled to
avoid its managed-networking cost:

```hcl
deploy_databricks = false
```

Copy any newly added example values into the ignored `infra/environments/dev.tfvars`, then review and
apply the platform change:

```powershell
$subscriptionId = "00000000-0000-0000-0000-000000000000"
.\tools\Invoke-DevDeployment.ps1 -SubscriptionId $subscriptionId -Action Plan
.\tools\Invoke-DevDeployment.ps1 -SubscriptionId $subscriptionId -Action Apply
.\tools\Invoke-DevDeployment.ps1 -SubscriptionId $subscriptionId -Action Verify
```

The plan should add the two linked services, three datasets, and one pipeline. It must not create a
Databricks workspace or NAT Gateway.

## Trigger and verify ingestion

```powershell
.\tools\Invoke-AdfIngestion.ps1 -SubscriptionId $subscriptionId
```

The command:

- Triggers `pl_ingest_github_to_bronze`.
- Waits for a terminal pipeline state.
- Requires pipeline status `Succeeded`.
- Requires exactly ten successful copy activity runs.
- Requires exactly ten successful bronze-file metadata checks.
- Compares the multiset of ADF `rowsCopied` values with the manifest row counts.
- Requires each metadata result to report that its file exists.
- Writes a compact run summary to `docs/evidence/private/adf-ingestion-run.json`.

Expected summary:

```text
ADF ingestion verification passed.
Copy iterations: 10
Bronze file checks: 10
Rows copied: 77259
```

The private evidence directory is ignored because the ADF run ID and Azure context should not be
published directly. A portfolio-safe evidence summary can include the successful status, activity
counts, total rows, and screenshots with subscription and resource identifiers obscured.

## Local validation

Local checks do not contact Azure or trigger ADF:

```powershell
terraform fmt -check -recursive infra
terraform -chdir=infra/platform init -backend=false
terraform -chdir=infra/platform validate
python tools/validate_repository.py
python -m pytest -q
```

Correct means Terraform validates, fourteen tests pass, and the repository contract reports ten
metadata entries, ten CSV files, and 77,259 rows.

## Failure handling

- Lookup failure stops the pipeline before the loop begins.
- A failed copy fails its iteration and the enclosing ForEach activity.
- The metadata check runs only after a successful copy, and an explicit If Condition and Fail
  activity stop the pipeline when its exact output file does not exist.
- Copy activities retry twice with a 30-second interval for transient HTTP or storage failures.
- The pipeline has concurrency one to avoid overlapping full-batch runs.

Rerunning the pipeline writes the same filenames in the same bronze folders. This makes bronze
ingestion deterministic for the current batch snapshot rather than creating timestamped duplicates.
