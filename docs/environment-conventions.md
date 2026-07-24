# Environment and Naming Conventions

## Environments

The repository supports three logical environments through the same modules and code:

| Environment | Purpose | Deployment expectation |
|---|---|---|
| `dev` | Development and portfolio demonstration | Deployed and verified |
| `test` | Pre-production validation | Configuration-ready; deploy only when required |
| `prod` | Production target pattern | Configuration-ready; not deployed for this portfolio |

Environment-specific values belong in Terraform variables, Databricks Bundle targets, or CI/CD
environment configuration. Business logic must not be copied between environment folders.

## Azure naming

Use this pattern where Azure naming rules permit it:

```text
aw-<resource-type>-<environment>-<region-code>-<suffix>
```

Examples:

```text
aw-rg-dev-weu-demo
aw-adf-dev-weu-demo
aw-dbw-dev-weu-demo
aw-syn-dev-weu-demo
```

Storage accounts require lowercase alphanumeric names without separators. Terraform will derive a
compact globally unique name rather than depend on a manually selected value.

## Required tags

- `project = adventure-works-data-platform`
- `environment = dev|test|prod`
- `managed-by = terraform`
- `owner = <team-or-owner>`
- `purpose = portfolio`

Supply owner information through environment configuration rather than hard-coding a personal email
address in reusable modules.

## Configuration rules

- Do not commit subscription IDs, tenant IDs, client IDs, secrets, tokens, or storage keys.
- Commit example variable files, but ignore real `*.auto.tfvars` files.
- Do not hard-code Azure resource names in PySpark transformation functions.
- Use lowercase logical dataset names in new code; preserve legacy folder names until migration is
  verified.
- Pin ingestion to a Git commit SHA for reproducibility. Current `develop` branch paths remain
  temporarily for compatibility.

