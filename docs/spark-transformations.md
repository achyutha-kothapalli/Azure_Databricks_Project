# Tested Bronze-to-Silver PySpark Transformations

The production transformation path is implemented as Python modules under `src/adventure_works`.
The original `Scripts/silver_layer.ipynb` remains as migration evidence but is not the target runtime.

## Module design

| Module | Responsibility |
|---|---|
| `schemas.py` | Explicit `StructType` schemas for every bronze CSV |
| `transforms.py` | Pure DataFrame-to-DataFrame transformations and audit columns |
| `quality.py` | Fail-fast key, uniqueness, category, measure, and relationship rules |
| `pipeline.py` | Strict reads, quality orchestration, Delta overwrite/MERGE, row-count summary |
| `main.py` | Validated runtime arguments and job entry point |

I/O is isolated from transformation logic so small in-memory DataFrames can test business behavior
without accessing Azure storage.

## Corrected notebook behavior

The module implementation intentionally changes these proof-of-concept behaviors:

- Bronze CSV reads use explicit schemas and `FAILFAST`; the production path never uses
  `inferSchema`.
- Dates use the explicit source format `M/d/yyyy`.
- Customer `FullName` uses the correctly cased `LastName` column and normalizes whitespace.
- Complete product names and SKUs are preserved.
- Sales order numbers are preserved; `S` is not replaced with `T`.
- Product categories are written alongside subcategories.
- All silver targets use consistent lowercase names.
- Delta replaces append-mode Parquet.
- Every target contains `_ingested_at`, `_source_file`, and `_run_id`.

## Idempotent writes

Small dimensions are atomically overwritten as Delta using the existing target schema. Incompatible
schemas fail rather than being silently replaced.

Sales and returns use Delta MERGE:

| Dataset | MERGE key | Source validation |
|---|---|---|
| Sales | `OrderNumber`, `OrderLineItem` | 56,046 rows and 56,046 unique keys |
| Returns | `ReturnDate`, `TerritoryKey`, `ProductKey` | 1,809 rows and 1,809 unique keys |

The returns key is a project assumption based on the current source snapshot. The dependency-free
repository validator fails if this assumption stops being true.

`upsert` is the normal load mode. `overwrite` is available for a deliberate full rebuild and applies
to all targets.

## Data-quality contracts

Validation runs before the first silver write:

- Required business and dimension keys are non-null.
- Dimension and MERGE keys are unique.
- Sales and return quantities are positive.
- Product subcategories resolve to categories.
- Products resolve to subcategories.
- Sales and returns resolve to products and territories.
- Sales customer keys resolve to customers.
- Customer gender is one of `F`, `M`, or `NA`.
- Customer marital status is `M` or `S`.

Accepted categorical values are documented and validated without silently rewriting source values.

## Runtime interface

The entry point accepts:

```text
--environment dev|test|prod
--storage-account <lowercase Azure storage name>
--source-layer bronze
--target-layer silver
--load-mode upsert|overwrite
--run-id <optional orchestration run ID>
```

Example module invocation from a configured Spark environment:

```powershell
python -m adventure_works.main `
  --environment dev `
  --storage-account awstdevweu0001 `
  --source-layer bronze `
  --target-layer silver `
  --load-mode upsert `
  --run-id manual-validation-001
```

Storage access must be supplied by the Databricks execution identity. The production code contains
no client secret, storage key, SAS token, or tenant-specific credential configuration.

## Local verification

Install Java 17 and the optional project dependencies:

```powershell
python -m pip install -e ".[dev,spark]"
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.20.8-hotspot"
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
```

Run formatting-quality and test gates:

```powershell
python -m ruff check src tests tools
python -m pytest -q
python tools/validate_repository.py
```

The Spark unit suite covers calendar derivations, customer full name and income parsing, date
parsing, product value preservation, sales audit fields, duplicate MERGE keys, non-positive
quantities, unresolved foreign keys, and the explicit fact keys.

## Databricks verification gate

The Databricks Bundle and job are introduced in the next productionization step. Once deployed, run
the job twice with the same bronze snapshot and `load-mode=upsert`.

Capture these results after each run:

| Silver target | Expected first-run rows | Expected second-run rows |
|---|---:|---:|
| calendar | 912 | 912 |
| customers | 18,148 | 18,148 |
| product_categories | 4 | 4 |
| product_subcategories | 37 | 37 |
| products | 293 | 293 |
| returns | 1,809 | 1,809 |
| sales | 56,046 | 56,046 |
| territories | 10 | 10 |

Correct means:

- Both runs succeed.
- The second run does not increase any count.
- All eight lowercase Delta targets exist.
- Delta history records the overwrite or MERGE operations.
- Every target contains the three audit columns.
- A deliberately invalid fixture fails with `DataQualityError` before a silver write.

Keep raw job output, cluster IDs, storage paths, and run IDs under `docs/evidence/private`. Publish
only a redacted count comparison and screenshots with Azure identifiers obscured.

## Synapse compatibility

The silver targets also serve Synapse serverless SQL. New tables are constrained to Delta reader
version 1 and writer version 2, with deletion vectors disabled and classic checkpoints. Existing
targets are inspected before each write; column mapping, deletion vectors, v2 checkpoints, or newer
protocol versions fail the pipeline because Synapse could otherwise return incorrect results.

The [Synapse serving guide](./synapse-serving.md) documents this boundary and the typed gold views.
