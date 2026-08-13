# Contributing

Changes use short-lived branches and pull requests into `develop`. `main` receives reviewed portfolio
releases from `develop`.

## Commit convention

Use Conventional Commit-style messages:

```text
<type>(<scope>): <imperative summary>
```

Common types are `feat`, `fix`, `test`, `docs`, `ci`, `build`, `refactor`, and `chore`.

Examples:

```text
feat(synapse): add typed sales view
test(metadata): enforce source row counts
ci(azure): add approved development plan
```

Keep one concern per commit. Do not include generated state, credentials, private evidence, personal
paths, or unrelated formatting changes.

## Local checks

```powershell
python -m pip install -e ".[dev,spark]"
python -m ruff check src tests tools
python -m pytest -q
python tools/validate_repository.py
terraform fmt -check -recursive infra
git diff --check
```

Also run the relevant local validator when changing a deployment surface:

```powershell
.\tools\Invoke-SynapseServing.ps1 `
  -Action Validate `
  -ServerEndpoint aw-syn-dev-ondemand.sql.azuresynapse.net `
  -DatabaseName adventureworks_dev `
  -StorageAccount awstdev0001 `
  -ReaderPrincipal data-readers@example.com
```

## Pull requests

Describe the problem, implementation boundary, verification, cost effect, security effect, and
rollback. Do not report Azure validation unless the referenced run actually completed. Redact
subscription IDs, resource IDs, workspace URLs, principal IDs, and user information from public
evidence.

Cloud changes require a reviewed Terraform plan. Databricks remains disabled in routine platform
deployment and may be enabled only for a short demonstration followed by the documented workspace,
managed resource-group, and NAT Gateway cleanup.
