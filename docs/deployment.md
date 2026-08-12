# Development Environment Deployment

This guide creates the shared Terraform state storage, produces a reviewable development plan,
applies that exact plan, and verifies that a second plan is empty. The workflow deploys only the
`dev` environment.

## Prerequisites

- Terraform 1.15.x
- Azure CLI
- An Azure subscription where the signed-in identity can create resource groups, resources, and
  role assignments
- PowerShell 7 or Windows PowerShell 5.1

Authenticate and select the intended subscription:

```powershell
az login
az account list -o table
$subscriptionId = "00000000-0000-0000-0000-000000000000"
az account set --subscription $subscriptionId
az account show --query "{name:name, id:id, tenantId:tenantId}" -o table
```

Do not put the real subscription ID in a tracked file.

## 1. Prepare local configuration

Create ignored working copies from the sanitized examples:

```powershell
Copy-Item infra/bootstrap/bootstrap.tfvars.example infra/bootstrap/bootstrap.tfvars
Copy-Item infra/environments/dev.tfvars.example infra/environments/dev.tfvars
```

Edit both local files:

- Replace `unique_suffix` with a stable lowercase alphanumeric value that makes storage names
  globally unique.
- Replace `owner` with the responsible person or team.
- Confirm the Azure region and region code.
- Keep `dev` on cost-conscious settings unless the demonstration requires otherwise.
- Keep `deploy_databricks = false` during the normal platform deployment. A Databricks workspace can
  create chargeable networking, including a NAT Gateway, in its managed resource group even when no
  cluster is running.

Confirm that Git ignores the real value files:

```powershell
git check-ignore infra/bootstrap/bootstrap.tfvars
git check-ignore infra/environments/dev.tfvars
```

Both paths must be printed. Never force-add these files.

## 2. Bootstrap remote state

First produce and review the bootstrap plan:

```powershell
.\tools\Initialize-TerraformState.ps1 -SubscriptionId $subscriptionId
```

The plan creates a small shared resource group, a private versioned storage account, a private state
container, and a data-plane role assignment for the signed-in identity. Shared-key access is
disabled; Terraform uses Azure CLI credentials through Microsoft Entra ID.

After reviewing the resources, create the state backend:

```powershell
.\tools\Initialize-TerraformState.ps1 -SubscriptionId $subscriptionId -Apply
```

The script writes `infra/environments/dev.backend.hcl`. This generated file contains resource names
and a state key but is ignored because backend configuration is environment-specific.

## 3. Plan the development platform

```powershell
.\tools\Invoke-DevDeployment.ps1 -SubscriptionId $subscriptionId -Action Plan
```

Review the complete plan. For a clean subscription, it should contain the development resource
group, ADLS Gen2 filesystems, Data Factory, Synapse, Log Analytics, diagnostics, and managed-identity
role assignments. Databricks must be absent while `deploy_databricks = false`. The plan must not
delete or replace unrelated resources.

The saved `infra/platform/dev.tfplan` is ignored by Git. Apply only this reviewed plan:

```powershell
.\tools\Invoke-DevDeployment.ps1 -SubscriptionId $subscriptionId -Action Apply
```

## 4. Verify the deployment

```powershell
.\tools\Invoke-DevDeployment.ps1 -SubscriptionId $subscriptionId -Action Verify
```

Verification is successful when:

- Terraform reports no changes using its detailed exit code.
- The expected Azure resources exist in the Terraform-created development resource group.
- Supported resources contain the common project, environment, owner, purpose, and management tags.
- `docs/evidence/private/dev-resources.json` contains the resource inventory.

The private evidence directory is ignored because Azure resource IDs and subscription context should
not be published. Add a short redacted summary or screenshots with identifiers obscured when
preparing the portfolio presentation.

## 5. Cost control and cleanup

### Databricks cleanup

Databricks is opt-in. Enable it only for the short period required to deploy and demonstrate the
Databricks workload:

```hcl
deploy_databricks = true
```

After capturing Databricks evidence, change the local dev value back to `false`. Then produce and
review the dedicated removal plan:

```powershell
.\tools\Remove-DatabricksWorkspace.ps1 -SubscriptionId $subscriptionId
```

Confirm that the plan removes the Databricks diagnostic setting and workspace without changing the
rest of the platform. Apply the saved removal plan and run the network cleanup checks:

```powershell
.\tools\Remove-DatabricksWorkspace.ps1 -SubscriptionId $subscriptionId -Apply
```

The command waits for workspace deletion, checks the deterministic Databricks managed resource
group, deletes that resource group if Azure left it behind, waits for deletion to finish, and queries
the subscription for any remaining NAT Gateway in that group. It fails unless the workspace,
managed resource group, and NAT Gateway are all absent.

Always complete this Databricks-specific cleanup before destroying the rest of the development
platform. Leaving the managed resource group behind can leave hourly networking charges running.

### Platform cleanup

Create and review a destroy plan before removing the demonstration platform:

```powershell
.\tools\Invoke-DevDeployment.ps1 -SubscriptionId $subscriptionId -Action DestroyPlan
```

The workflow intentionally does not automate destroy. Run the reviewed destroy plan manually only
after evidence has been captured. Keep the remote-state resources until the platform state is no
longer needed.

## Troubleshooting

- `Azure CLI is not authenticated`: run `az login`, verify the subscription, and retry.
- `AuthorizationFailed`: the signed-in identity lacks resource or role-assignment permissions.
- Storage name conflict: choose another stable `unique_suffix` in the local bootstrap and dev value
  files.
- Backend access failure immediately after bootstrap: Azure role assignments can take time to
  propagate; wait briefly and rerun the platform plan.
- Databricks managed resource-group deletion fails: inspect Azure deny assignments and wait for the
  workspace deletion to finish, then rerun the dedicated cleanup command. Do not treat cleanup as
  complete until its NAT Gateway verification passes.
- Provider registration failure: confirm the subscription permits registration of the namespaces
  declared in the Terraform provider configuration.
