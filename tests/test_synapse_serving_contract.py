"""Contracts for the Synapse serverless SQL serving layer."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_ROOT = ROOT / "synapse" / "sql"


def read(relative_path: str) -> str:
    """Read a repository file as UTF-8 text."""
    return (ROOT / relative_path).read_text(encoding="utf-8")


def production_sql() -> str:
    """Return only the replacement Synapse SQL, excluding the legacy script."""
    return "\n".join(path.read_text(encoding="utf-8") for path in sorted(SQL_ROOT.glob("*.sql")))


def test_database_bootstrap_uses_managed_identity_and_utf8() -> None:
    """The serving database must use UTF-8 and the workspace identity for ADLS."""
    database = read("synapse/sql/00_database.sql")
    access = read("synapse/sql/10_external_access.sql")

    assert "IF DB_ID(N'$(DatabaseName)') IS NULL" in database
    assert "Latin1_General_100_BIN2_UTF8" in database
    assert "##MS_DatabaseMasterKey##" in database
    assert "IF SCHEMA_ID(N'gold') IS NULL" in access
    assert "WITH IDENTITY = 'Managed Identity'" in access
    assert "https://$(StorageAccount).dfs.core.windows.net/silver" in access
    assert "SilverDataSource points to an unexpected storage location" in access


def test_gold_views_are_typed_idempotent_and_delta_backed() -> None:
    """Gold views must avoid inferred schemas, wildcards, and legacy Parquet paths."""
    sql = production_sql()
    source_views = read("synapse/sql/20_gold_views.sql")

    assert len(re.findall(r"CREATE OR ALTER VIEW \[gold\]", sql)) == 10
    assert source_views.count("FORMAT = 'DELTA'") == 8
    assert source_views.count("WITH (") == 8
    assert re.search(r"(?im)SELECT\s+\*", sql) is None
    assert "<datalake_name>" not in sql
    assert "FORMAT = 'PARQUET'" not in sql

    for folder in (
        "calendar",
        "customers",
        "product_categories",
        "product_subcategories",
        "products",
        "returns",
        "sales",
        "territories",
    ):
        assert f"BULK '{folder}'" in source_views


def test_semantic_views_publish_explicit_business_measures() -> None:
    """Consumer views must expose joined business context and calculated measures."""
    semantic = read("synapse/sql/30_semantic_views.sql")

    assert "CREATE OR ALTER VIEW [gold].[sales_detail]" in semantic
    assert "CREATE OR ALTER VIEW [gold].[returns_detail]" in semantic
    assert "AS [sales_amount]" in semantic
    assert "AS [return_cost]" in semantic
    assert "INNER JOIN [gold].[dim_product_category]" in semantic
    assert "INNER JOIN [gold].[dim_territory]" in semantic


def test_live_verification_checks_counts_and_business_keys() -> None:
    """The live gate must fail on missing rows, duplicate facts, or missing views."""
    verification = read("synapse/sql/90_verify.sql")

    expected_counts = {
        "dim_date": 912,
        "dim_customer": 18148,
        "dim_product_category": 4,
        "dim_product_subcategory": 37,
        "dim_product": 293,
        "dim_territory": 10,
        "fact_sales": 56046,
        "fact_returns": 1809,
    }
    for view, count in expected_counts.items():
        assert f"FROM [gold].[{view}]) <> {count}" in verification

    assert "Expected ten gold views" in verification
    assert "GROUP BY [order_number], [order_line_item]" in verification
    assert "GROUP BY [return_date], [territory_key], [product_key]" in verification


def test_reader_principal_receives_only_serving_permissions() -> None:
    """The consumer principal must read gold views without broad external-file privileges."""
    permissions = read("synapse/sql/40_permissions.sql")

    assert "CREATE USER [$(ReaderPrincipal)] FROM EXTERNAL PROVIDER" in permissions
    assert "GRANT SELECT ON SCHEMA::[gold]" in permissions
    assert "GRANT REFERENCES ON DATABASE SCOPED CREDENTIAL::[WorkspaceIdentity]" in permissions
    assert "DENY ADMINISTER DATABASE BULK OPERATIONS" in permissions


def test_deployment_workflow_keeps_master_key_password_off_command_line() -> None:
    """Deployment must use Entra auth and send the master-key password through standard input."""
    workflow = read("tools/Invoke-SynapseServing.ps1")

    assert "[Security.SecureString]$MasterKeyPassword" in workflow
    assert "[switch]$ConfirmDeploy" in workflow
    assert "[switch]$ConfirmDestroy" in workflow
    assert "'$(MasterKeyPassword)'" in workflow
    assert '$plainText.Replace("\'", "\'\'")' in workflow
    assert "$renderedSql | & sqlcmd" in workflow
    assert "-G" in workflow
    assert "-b" in workflow
    assert "-v MasterKeyPassword" not in workflow
    assert "docs/evidence/private/synapse" in workflow
