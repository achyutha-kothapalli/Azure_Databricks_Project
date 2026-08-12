"""Contracts for the Databricks bundle and its cost-safe deployment workflow."""

from __future__ import annotations

from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]


def load_yaml(relative_path: str) -> dict:
    """Load a checked-in YAML document."""
    with (ROOT / relative_path).open(encoding="utf-8") as stream:
        return yaml.safe_load(stream)


def read(relative_path: str) -> str:
    """Read a repository file as UTF-8 text."""
    return (ROOT / relative_path).read_text(encoding="utf-8")


def test_bundle_has_promotable_targets_and_external_identity() -> None:
    """Targets must share one definition while identity and environment values stay external."""
    bundle = load_yaml("databricks/databricks.yml")

    assert set(bundle["targets"]) == {"dev", "test", "prod"}
    assert bundle["targets"]["dev"]["mode"] == "development"
    assert bundle["targets"]["test"]["mode"] == "production"
    assert bundle["targets"]["prod"]["mode"] == "production"
    assert bundle["run_as"]["service_principal_name"] == "${var.run_as_service_principal}"
    assert "host" not in bundle["workspace"]
    assert "storage_account" in bundle["variables"]
    assert "tenant_id" in bundle["variables"]
    assert "storage_client_id" in bundle["variables"]
    assert "operator_group" in bundle["variables"]


def test_job_uses_bounded_ephemeral_compute() -> None:
    """The portfolio job must not create persistent or unbounded Databricks compute."""
    job = load_yaml("databricks/resources/job.yml")["resources"]["jobs"]["silver_pipeline"]
    cluster = job["job_clusters"][0]["new_cluster"]
    task = job["tasks"][0]

    assert job["max_concurrent_runs"] == 1
    assert cluster["num_workers"] == 0
    assert cluster["spark_conf"]["spark.databricks.cluster.profile"] == "singleNode"
    assert cluster["custom_tags"]["ResourceClass"] == "SingleNode"
    assert "existing_cluster_id" not in task
    assert task["timeout_seconds"] <= 1800
    assert task["max_retries"] == 0
    assert task["retry_on_timeout"] is False
    assert cluster["spark_conf"]["spark.hadoop.fs.azure.account.auth.type"] == "OAuth"
    assert "{{secrets/" in cluster["spark_conf"][
        "spark.hadoop.fs.azure.account.oauth2.client.secret"
    ]


def test_job_executes_the_versioned_wheel_entry_point() -> None:
    """The deployed task must run packaged source code with explicit runtime parameters."""
    job = load_yaml("databricks/resources/job.yml")["resources"]["jobs"]["silver_pipeline"]
    task = job["tasks"][0]
    wheel_task = task["python_wheel_task"]
    pyproject = read("pyproject.toml")

    assert wheel_task["entry_point"] == "silver_pipeline"
    assert wheel_task["package_name"] == "adventure-works-azure-data-platform"
    assert "silver_pipeline = \"adventure_works.main:main\"" in pyproject
    assert task["libraries"] == [{"whl": "../dist/*.whl"}]
    assert "{{job.parameters.storage_account}}" in wheel_task["parameters"]
    assert "{{job.parameters.run_id}}" in wheel_task["parameters"]


def test_bundle_workflow_requires_cost_and_destroy_confirmation() -> None:
    """Live runs and destructive cleanup must require explicit operator confirmation."""
    workflow = read("tools/Invoke-DatabricksBundle.ps1")

    assert "[switch]$ConfirmCost" in workflow
    assert "[switch]$ConfirmDestroy" in workflow
    assert "Cost control is missing from the Databricks job" in workflow
    assert "Rerun with -ConfirmCost" in workflow
    assert "Rerun with -ConfirmDestroy" in workflow
    assert "'summary', '--force-pull', '-o', 'json'" in workflow
    assert "Idempotent deployment verified" in workflow
