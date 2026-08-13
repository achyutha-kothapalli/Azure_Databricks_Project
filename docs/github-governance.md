# GitHub Repository Governance

Repository rules are managed from the isolated Terraform root in `infra/github`. The configuration
adopts the existing `develop_protect` ruleset and protects `develop` from deletion, force-pushes,
direct updates, unresolved review conversations, and merges with incomplete CI.

## Managed ruleset

| Setting | Value |
|---|---|
| Repository | `achyutha-kothapalli/Azure_Databricks_Project` |
| Ruleset | `develop_protect` |
| Existing ruleset ID | `20793393` |
| Target | `refs/heads/develop` |
| Enforcement | Active |
| Required checks | `Python, data, and workload contracts`; `Terraform formatting and validation` |
| Reviews | Pull request required; unresolved conversations block merge |
| Approvals | No external approval required for this individually maintained repository |

The ruleset was initially created in GitHub settings. Its import block remains in `rulesets.tf` so a
new state adopts the existing object instead of attempting to create another ruleset.

## Authentication and state

Terraform uses the official GitHub provider. Supply a short-lived fine-grained personal access token
or GitHub App installation token through the `GITHUB_TOKEN` environment variable. The credential
needs repository Administration read/write permission. Do not put the token in a Terraform variable,
backend file, shell script, or committed file.

Governance uses a separate Azure Blob state key:

```text
adventure-works/github/governance.tfstate
```

Copy the example backend configuration and replace the placeholder state resource names:

```powershell
Copy-Item infra/environments/github.backend.hcl.example infra/environments/github.backend.hcl
```

The resulting `.backend.hcl` file is ignored. Authenticate to Azure with an identity that can read
and write blobs in the Terraform state container.

## Adoption procedure

Run these commands from the repository root:

```powershell
terraform -chdir=infra/github init `
  -reconfigure `
  -backend-config=../environments/github.backend.hcl

terraform -chdir=infra/github validate
terraform -chdir=infra/github plan -out=github-governance.tfplan
terraform -chdir=infra/github show -no-color github-governance.tfplan
```

The first plan should import `github_repository_ruleset.develop` and update that same resource in
place. Review these boundaries before applying:

- The import ID is `Azure_Databricks_Project:20793393`.
- No second `github_repository_ruleset` is created.
- The ruleset is not deleted or replaced.
- The condition changes from `~DEFAULT_BRANCH` to `refs/heads/develop`.
- Deletion and non-fast-forward protection remain enabled.
- Pull-request, conversation-resolution, and the two CI checks are added.
- No repository, branch, collaborator, secret, webhook, or Azure resource is changed.

Stop if the plan contains a create, replacement, or deletion. Confirm the repository name and
ruleset ID against GitHub settings before continuing.

Apply the reviewed plan:

```powershell
terraform -chdir=infra/github apply github-governance.tfplan
terraform -chdir=infra/github plan -detailed-exitcode
```

The second command should return exit code `0`. Exit code `2` means configuration drift or an
unapplied change; any other nonzero value indicates an execution error.

## GitHub verification

After apply, open **Settings > Rules > Rulesets > develop_protect** and verify:

1. Enforcement status is Active.
2. The target is explicitly `develop`.
3. Deletion and force-push blocking are enabled.
4. Changes require a pull request.
5. Review conversations must be resolved.
6. Both CI job names are required and branches must be current before merging.

Open a small pull request into `develop` and verify that GitHub blocks merge until both jobs succeed.
Do not test force-push or branch deletion against the shared branch.

## Changes and recovery

Update `infra/github/rulesets.tf`, run the local tests, and review a Terraform plan before applying a
governance change. Keep the import block while this ruleset remains the managed object.

If an incorrect rule blocks normal work, use an administrator account to change the ruleset to
Disabled in GitHub settings, correct the Terraform configuration, review a new plan, and apply it.
Return enforcement to Active through Terraform. Deleting the ruleset or removing it from state is
not part of routine recovery.
