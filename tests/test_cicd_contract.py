"""Security and quality contracts for GitHub Actions automation."""

from __future__ import annotations

import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    """Read a repository file as UTF-8 text."""
    return (ROOT / relative_path).read_text(encoding="utf-8")


def load_workflow(name: str) -> dict:
    """Load workflow YAML without YAML 1.1 coercion of the `on` key."""
    return yaml.load(  # noqa: S506 - BaseLoader does not construct Python objects
        read(f".github/workflows/{name}"),
        Loader=yaml.BaseLoader,
    )


def test_ci_is_credential_free_and_runs_complete_quality_gate() -> None:
    """Pull-request checks must be read-only and cover code, data, SQL, and Terraform."""
    workflow = load_workflow("ci.yml")
    content = read(".github/workflows/ci.yml")

    assert workflow["permissions"] == {"contents": "read"}
    assert "pull_request" in workflow["on"]
    assert "id-token: write" not in content
    assert "azure/login" not in content
    assert "python -m pytest -q" in content
    assert "python -m ruff check src tests tools" in content
    assert "python tools/validate_repository.py" in content
    assert "python -m build --wheel --no-isolation" in content
    assert "Invoke-SynapseServing.ps1" in content
    assert "terraform fmt -check -recursive infra" in content
    assert "terraform -chdir=infra/github init -backend=false -input=false" in content
    assert "terraform -chdir=infra/github validate" in content
    assert content.count("terraform -chdir=") >= 6


def test_deployment_is_manual_oidc_authenticated_and_cost_bounded() -> None:
    """Cloud mutation must require dispatch, OIDC, approval, and disabled Databricks."""
    workflow = load_workflow("deploy-dev.yml")
    content = read(".github/workflows/deploy-dev.yml")

    assert set(workflow["on"]) == {"workflow_dispatch"}
    assert workflow["permissions"] == {"contents": "read", "id-token": "write"}
    assert "pull_request" not in workflow["on"]
    assert "push" not in workflow["on"]
    assert "uses: azure/login@v3" in content
    assert "creds:" not in content
    assert "ARM_USE_OIDC: true" in content
    assert "ARM_USE_AZUREAD: true" in content
    assert "TF_VAR_deploy_databricks: false" in content
    assert "inputs.confirmation != 'APPLY_DEV'" in content
    assert workflow["jobs"]["plan"]["environment"] == "dev-plan"
    assert workflow["jobs"]["apply"]["environment"] == "dev"
    assert workflow["jobs"]["apply"]["needs"] == "plan"
    assert "Apply exact post-approval plan" in content
    assert "cancel-in-progress: false" in content


def test_actions_use_versioned_references_and_dependabot_maintains_them() -> None:
    """Third-party actions must use version tags and receive scheduled updates."""
    workflow_text = "\n".join(
        read(f".github/workflows/{name}") for name in ("ci.yml", "deploy-dev.yml")
    )
    action_refs = re.findall(r"uses:\s*([^\s]+)", workflow_text)

    assert action_refs
    assert all(re.search(r"@v\d+$", reference) for reference in action_refs)
    assert not any(
        reference.endswith("@main") or reference.endswith("@master")
        for reference in action_refs
    )

    dependabot = yaml.safe_load(read(".github/dependabot.yml"))
    ecosystems = {update["package-ecosystem"] for update in dependabot["updates"]}
    assert ecosystems == {"github-actions", "pip"}
    assert all(update["schedule"]["interval"] == "weekly" for update in dependabot["updates"])
