"""Contracts for reproducible and credential-free Terraform deployment files."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENVIRONMENTS = ("dev", "test", "prod")


def read(relative_path: str) -> str:
    """Read a repository file as UTF-8 text."""
    return (ROOT / relative_path).read_text(encoding="utf-8")


def test_remote_state_bootstrap_security_controls() -> None:
    """State storage must use Azure AD, private access, and recovery controls."""
    provider = read("infra/bootstrap/providers.tf")
    bootstrap = read("infra/bootstrap/main.tf")

    assert "storage_use_azuread             = true" in provider
    assert "shared_access_key_enabled       = false" in bootstrap
    assert 'container_access_type = "private"' in bootstrap
    assert "versioning_enabled = true" in bootstrap
    assert 'role_definition_name = "Storage Blob Data Contributor"' in bootstrap
    assert "depends_on = [azurerm_role_assignment.state_contributor]" in bootstrap


def test_backend_examples_are_separate_and_credential_free() -> None:
    """Each environment must use a distinct state key without embedded credentials."""
    state_keys: set[str] = set()
    forbidden = re.compile(
        r"(?i)(access_key|client_secret|sas_token|tenant_id\s*=|subscription_id\s*=)"
    )

    for environment in ENVIRONMENTS:
        content = read(f"infra/environments/{environment}.backend.hcl.example")
        match = re.search(r'key\s*=\s*"([^"]+)"', content)

        assert match is not None
        assert f"/{environment}/" in match.group(1)
        assert match.group(1) not in state_keys
        assert "use_azuread_auth     = true" in content
        assert "use_cli              = true" in content
        assert forbidden.search(content) is None
        state_keys.add(match.group(1))


def test_local_deployment_values_are_ignored() -> None:
    """Real variable and backend files must stay outside version control."""
    gitignore = read(".gitignore").splitlines()

    assert "*.tfvars" in gitignore
    assert "!*.tfvars.example" in gitignore
    assert "*.backend.hcl" in gitignore
    assert "!*.backend.hcl.example" in gitignore


def test_deployment_workflow_requires_reviewed_plan() -> None:
    """Apply must consume the saved plan and verification must detect drift."""
    deployment = read("tools/Invoke-DevDeployment.ps1")

    assert "No reviewed dev.tfplan exists" in deployment
    assert "apply -input=false $planPath" in deployment
    assert "plan -input=false -detailed-exitcode" in deployment
    assert "plan -destroy" in deployment


def test_bootstrap_workflow_generates_azure_ad_backend() -> None:
    """The generated local backend must use CLI-based Azure AD authentication."""
    bootstrap = read("tools/Initialize-TerraformState.ps1")

    assert "use_azuread_auth     = true" in bootstrap
    assert "use_cli              = true" in bootstrap
    assert "access_key" not in bootstrap
    assert "client_secret" not in bootstrap


def test_databricks_is_disabled_by_default() -> None:
    """Routine platform deployments must not create chargeable Databricks networking."""
    variables = read("infra/platform/variables.tf")
    workspace = read("infra/platform/databricks.tf")
    monitoring = read("infra/platform/monitoring.tf")

    declaration = re.search(
        r'variable "deploy_databricks"\s*\{(?P<body>.*?)\n\}',
        variables,
        re.DOTALL,
    )
    assert declaration is not None
    assert "default     = false" in declaration.group("body")
    assert "count = var.deploy_databricks ? 1 : 0" in workspace
    assert "count = var.deploy_databricks ? 1 : 0" in monitoring

    for environment in ENVIRONMENTS:
        values = read(f"infra/environments/{environment}.tfvars.example")
        assert "deploy_databricks                  = false" in values


def test_databricks_cleanup_verifies_managed_network_removal() -> None:
    """Workspace cleanup must remove its managed group and prove no NAT Gateway remains."""
    cleanup = read("tools/Remove-DatabricksWorkspace.ps1")

    assert "-var='deploy_databricks=false'" in cleanup
    assert "Set deploy_databricks = false in the local dev tfvars file" in cleanup
    assert 'az group delete --name $managedResourceGroupName --yes --no-wait' in cleanup
    assert "az group wait --name $managedResourceGroupName --deleted" in cleanup
    assert "az network nat gateway list" in cleanup
    assert "NAT Gateway resources still exist" in cleanup
    assert "NAT Gateway verification passed" in cleanup
