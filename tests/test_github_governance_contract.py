"""Contracts for code-defined GitHub repository governance."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GITHUB_TERRAFORM = ROOT / "infra" / "github"


def read(name: str) -> str:
    """Read a GitHub governance Terraform file as UTF-8 text."""
    return (GITHUB_TERRAFORM / name).read_text(encoding="utf-8")


def test_github_governance_uses_an_isolated_remote_state() -> None:
    """Repository controls must not share lifecycle or state with Azure resources."""
    backend = read("backend.tf")
    example = (ROOT / "infra/environments/github.backend.hcl.example").read_text(
        encoding="utf-8"
    )

    assert 'backend "azurerm"' in backend
    assert 'key                  = "adventure-works/github/governance.tfstate"' in example
    assert "use_azuread_auth     = true" in example


def test_develop_ruleset_is_active_explicit_and_imported() -> None:
    """Terraform must adopt the active ruleset and target only develop."""
    ruleset = read("rulesets.tf")

    assert 'name        = "develop_protect"' in ruleset
    assert 'target      = "branch"' in ruleset
    assert 'enforcement = "active"' in ruleset
    assert 'include = ["refs/heads/develop"]' in ruleset
    assert "~DEFAULT_BRANCH" not in ruleset
    assert "deletion         = true" in ruleset
    assert "non_fast_forward = true" in ruleset
    assert "pull_request {" in ruleset
    assert "required_approving_review_count   = 0" in ruleset
    assert "required_review_thread_resolution = true" in ruleset
    assert "required_status_checks {" in ruleset
    assert "strict_required_status_checks_policy = true" in ruleset
    assert 'context = "Python, data, and workload contracts"' in ruleset
    assert 'context = "Terraform formatting and validation"' in ruleset
    assert "to = github_repository_ruleset.develop" in ruleset
    assert 'id = "Azure_Databricks_Project:20793393"' in ruleset


def test_github_credentials_are_not_declared_as_terraform_variables() -> None:
    """Authentication must come from the process environment, not Terraform input."""
    terraform = "\n".join(
        path.read_text(encoding="utf-8") for path in GITHUB_TERRAFORM.glob("*.tf")
    )

    assert not re.search(r'variable\s+".*(?:token|secret|password).*"', terraform, re.IGNORECASE)
    assert "GITHUB_TOKEN" not in terraform
    assert "token =" not in terraform
