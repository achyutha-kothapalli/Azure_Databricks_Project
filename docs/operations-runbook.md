# Operations Runbook

This runbook covers the development portfolio environment. Test and production are configuration
targets only and have no deployed resources.

## Ownership and operating model

| Component | Deployment owner | Runtime identity | Primary evidence |
|---|---|---|---|
| Azure platform | Terraform | GitHub OIDC identity or local Azure CLI user | Terraform plan and resource inventory |
| ADF ingestion | Terraform | Data Factory managed identity | Pipeline run and row-count checks |
| Databricks transformation | Databricks bundle | Development job service principal | Job output and Delta history |
| Synapse serving | Ordered SQL deployment | Synapse workspace managed identity | View-count and row-count checks |

Raw logs and resource identifiers belong under `docs/evidence/private`, which Git ignores. Only
redacted summaries are suitable for the public repository.

Azure Monitor sends an email through the environment action group whenever the ADF
`PipelineFailedRuns` metric is greater than zero. Databricks job failures use the externally supplied
bundle notification address. Alert receivers are environment configuration, not hard-coded values.

## Normal batch operation

Run the layers in this order:

1. Confirm platform health and remote-state access.
2. Run ADF ingestion and verify all ten bronze datasets.
3. Run the Databricks job and verify eight silver Delta targets.
4. Run Synapse serving verification.

Do not continue to the next layer after a failed verification. Downstream results would be stale or
incomplete.

### Platform check

```powershell
.\tools\Invoke-DevDeployment.ps1 `
  -SubscriptionId $subscriptionId `
  -Action Verify
```

### Ingestion

Follow `docs/adf-ingestion.md`. Confirm that the ADF run succeeds and observed row counts match the
source-data contract before starting Databricks.

### Transformation

Follow `docs/databricks-bundle.md`. Use `upsert` for a normal rerun. The job fails before writing if
source quality or Synapse Delta compatibility checks fail.

### Serving

```powershell
.\tools\Invoke-SynapseServing.ps1 @synapseCommon -Action Verify
```

## Incident triage

Use this order to avoid changing data before the cause is understood:

1. Record the UTC failure time, environment, layer, run ID, and last successful run.
2. Stop downstream execution.
3. Check whether the failure is configuration, authorization, source-data, compute, or quota related.
4. Preserve relevant private logs before retrying.
5. Apply the smallest reversible correction.
6. Rerun the failed layer and all downstream verification gates.
7. Record the cause, correction, evidence, and prevention action.

## Failure procedures

### ADF ingestion failure

Check:

- The commit-pinned source URL still resolves.
- The canonical metadata contains ten unique entries.
- Data Factory managed identity retains storage data-plane access.
- The failed activity identifies one dataset rather than a general linked-service failure.

Action:

- Correct metadata or authorization through code and a reviewed deployment.
- Do not edit the live pipeline in the portal.
- Rerun the metadata-driven pipeline and repeat row-count verification.

### Databricks job failure

Check:

- The job cluster terminated after failure.
- Failure is in wheel installation, ADLS OAuth, quality checks, Delta protocol checks, or write logic.
- The secret scope and service-principal RBAC remain valid.
- Bronze data is complete for the failed run.

Action:

- Do not bypass `DataQualityError` or the Delta compatibility guard.
- Fix and redeploy the bundle, then run in `upsert` mode.
- Confirm expected counts and Delta operations.
- If the workspace was enabled only for evidence, complete its cleanup even when the run failed.

### Synapse query failure

Check:

- The workspace managed identity retains storage access.
- `SilverDataSource` points at the expected account and filesystem.
- Every target contains `_delta_log`.
- The Delta protocol remains reader 1/writer 2 without deletion vectors or column mapping.
- The serving database and credential exist.

Action:

- Correct the producer or SQL deployment through code.
- Redeploy SQL twice, then run live verification.
- Do not replace typed schemas with inference or `SELECT *` to work around a mismatch.

### Terraform state lock or drift

Check:

- No other deployment is active.
- The GitHub concurrency group or local operator is not holding the lock.
- The plan represents intended code rather than a portal change.

Action:

- Never force-unlock an active deployment.
- For click-created drift, either encode the intended setting in Terraform or revert it in Azure.
- Review a new plan before applying reconciliation.

### Unexpected Azure cost

Check immediately:

- NAT Gateways and public IPs in the Databricks managed resource group
- Running Databricks clusters and jobs
- Synapse serverless query volume
- Log Analytics ingestion
- Resources outside the Terraform state

For a Databricks-related cost, stop active jobs, destroy bundle resources, set
`deploy_databricks = false`, and run the dedicated workspace cleanup. Completion requires explicit
confirmation that the workspace, managed resource group, and NAT Gateway are all absent.

## Recovery and rollback

### Code rollback

Revert the faulty commit in a new branch, rerun CI, and merge through a pull request. Avoid rewriting
shared branch history.

### Terraform rollback

Terraform rollback is a forward operation:

1. Restore the desired configuration in code.
2. Create a new plan.
3. Review replacement and deletion actions.
4. Apply the reviewed plan.
5. Verify a subsequent empty plan.

Never restore an old state blob over current state while resources are being changed.

### Data rollback

- Dimensions can be rebuilt with deliberate `overwrite` mode after the source snapshot is verified.
- Facts normally use MERGE and can be rerun with the same bronze snapshot.
- Use Delta history for investigation, but do not perform an unreviewed restore that would break the
  Synapse compatibility contract.
- Re-run Synapse verification after any silver recovery.

### SQL rollback

Redeploy the last known-good ordered SQL from a reviewed Git revision. `CREATE OR ALTER VIEW` updates
objects in place. Dropping the complete serving database is reserved for explicit environment
cleanup, not normal rollback.

## Environment cleanup

Cleanup order:

1. Capture and redact final evidence.
2. Remove Synapse serving database if no longer needed.
3. Destroy Databricks bundle resources.
4. Remove the Databricks workspace through Terraform.
5. Verify the Databricks managed resource group and NAT Gateway are absent.
6. Delete the development job application registration.
7. Review the wider platform destroy plan.
8. Apply the reviewed platform cleanup manually.
9. Retain remote state until deletion is confirmed and no recovery is required.

## Incident record template

```text
Title:
UTC start/end:
Environment:
Affected layer:
Run or deployment ID:
Customer/data impact:
Detection:
Root cause:
Correction:
Verification:
Cost impact:
Prevention action:
```
