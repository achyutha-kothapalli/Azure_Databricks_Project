# CI/CD and GitHub Environment Setup

The repository separates credential-free validation from Azure deployment. Pull requests cannot
request an Azure token. Development deployment is manual, uses GitHub OpenID Connect, and pauses for
approval after the Terraform plan is visible.

## Workflows

### Continuous Integration

`.github/workflows/ci.yml` runs for pull requests into `develop` or `main` and pushes to `develop`.
It has only `contents: read` permission and performs:

- Python linting
- The complete unit and contract test suite with Java 17 and Spark 3.5
- Source-data and metadata validation
- Wheel packaging
- PowerShell parser validation
- Synapse SQL structural validation
- Terraform formatting and offline-backend validation

The workflow does not authenticate to Azure and cannot modify cloud resources.

### Development Platform Deployment

`.github/workflows/deploy-dev.yml` runs only through `workflow_dispatch`. It supports:

| Operation | Result |
|---|---|
| `plan` | Produces and displays a development Terraform plan |
| `apply` | Produces the plan, waits for protected-environment approval, recreates and applies an exact plan |
| `verify` | Fails when Terraform detects drift or unapplied changes |

The workflow always sets `deploy_databricks = false`. Databricks demonstrations use the dedicated
local workflow in `docs/databricks-bundle.md`, including mandatory NAT Gateway cleanup.

## GitHub repository configuration

Create these GitHub Environments under **Settings → Environments**:

| Environment | Purpose | Protection |
|---|---|---|
| `dev-plan` | Read-only Terraform plan and drift detection | Restrict deployment branches to `develop` and `main` |
| `dev` | Terraform apply | Required reviewer, prevent self-review, restrict branches to `develop` and `main` |

The apply job does not start until the `dev` protection rule is approved. Review the preceding plan
job before approving it. Public repositories support required reviewers on current GitHub plans.

Configure these non-secret repository variables:

| Variable | Example | Purpose |
|---|---|---|
| `AZURE_LOCATION` | `westeurope` | Azure region |
| `AZURE_REGION_CODE` | `weu` | Naming abbreviation |
| `AZURE_UNIQUE_SUFFIX` | `dev0001` | Stable globally unique suffix |
| `PLATFORM_OWNER` | `data-platform` | Resource ownership tag |
| `ALERT_EMAIL` | Operations mailbox | ADF failed-run alert receiver |
| `ADF_SOURCE_BASE_URL` | Commit-pinned raw GitHub URL | Reproducible ingestion source |
| `TF_STATE_RESOURCE_GROUP` | Bootstrap output | Remote-state resource group |
| `TF_STATE_STORAGE_ACCOUNT` | Bootstrap output | Remote-state storage account |
| `TF_STATE_CONTAINER` | `tfstate` | Private state container |

Configure these secrets in both `dev-plan` and `dev` environments:

```text
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
```

These values identify federated Azure principals; there is no client secret.

## Azure identities and federated credentials

Use separate Microsoft Entra applications or user-assigned managed identities for planning and
applying:

| GitHub environment | Azure access |
|---|---|
| `dev-plan` | Reader at the deployment scope; Storage Blob Data Contributor on the state container |
| `dev` | Contributor plus constrained Role Based Access Control Administrator at the deployment scope; Storage Blob Data Contributor on the state container |

The platform creates a resource group and storage role assignments. If the apply identity is scoped
at the subscription, constrain its RBAC-administrator assignment to the role definitions and
principal types used by this repository. Remove the federated identities when the portfolio
environment is retired.

Create one federated credential per GitHub environment. The subject values follow this pattern:

```text
repo:<github-owner>/<repository>:environment:dev-plan
repo:<github-owner>/<repository>:environment:dev
```

Use audience:

```text
api://AzureADTokenExchange
```

The workflow requests `id-token: write` only for the manual deployment workflow. Azure Login and the
Terraform Azure backend exchange the short-lived GitHub token through OIDC.

References:

- [GitHub OIDC with Azure](https://docs.github.com/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure)
- [GitHub deployment environments](https://docs.github.com/actions/reference/workflows-and-actions/deployments-and-environments)
- [Terraform Azure backend OIDC](https://developer.hashicorp.com/terraform/language/backend/azurerm)
- [Azure privileged RBAC roles](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#privileged)

## Repository governance

The `develop` ruleset is defined in `infra/github` and adopted through an import block. It requires
pull requests, resolved conversations, current branches, and both continuous-integration jobs while
blocking deletion and force-pushes. Follow the [GitHub governance guide](./github-governance.md) to
review and apply the ruleset without creating a duplicate.

`main` should receive an equivalent release ruleset before it becomes an active release branch.

## Branch policy

The managed `develop` ruleset enforces:

- Require pull requests before merging.
- Require the two CI jobs to pass.
- Require conversations to be resolved.
- Require the branch to be up to date before merging.
- Prevent force pushes and deletion.
- No minimum approval count, allowing individual maintenance while retaining the pull-request audit
  trail.

Do not add a second settings-based protection rule for `develop`. Extend the Terraform configuration
when `main` begins receiving releases.

Recommended branch flow:

```text
feature or prod/step branch → develop → main
```

`develop` is the integration branch. `main` represents the portfolio release. Tag a verified release
only after redacted Azure evidence is captured.

## Running the workflow

From the Actions page:

1. Select **Development Platform Deployment**.
2. Choose the `develop` or `main` revision.
3. Run `plan` and review every proposed action.
4. Run `apply` with confirmation `APPLY_DEV`.
5. Review the new plan job.
6. Approve the protected `dev` environment.
7. Run `verify` after apply.

The workflow does not automate destroy. Use the reviewed local cleanup procedures in
`docs/deployment.md`, especially the separate Databricks workspace and NAT Gateway checks.

## Dependency maintenance

Dependabot checks GitHub Actions and Python dependencies weekly. Dependency pull requests pass
through the same CI gate and should be merged only after release notes and compatibility are
reviewed. Major-version updates require an explicit maintenance decision.
