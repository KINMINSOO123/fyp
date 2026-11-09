# Adapted demonstration sales import

This importer is for `Bakery_Sales_Recent_Dummy_Package.zip` only. Its README identifies the 240 rows as **adapted demonstration data**: the products, quantities, and dates were adapted for this FYP. The timeline is 30 consecutive dummy dates, 10 October through 8 November 2026, for each of eight existing bread categories. It is not evidence of actual bakery transactions on those dates. The importer verifies the reviewed CSV and README SHA-256 hashes before processing.

From the `backend` directory, build and review the database dry run:

```powershell
npm run build
node --env-file=.env dist/scripts/importAdaptedSales.js --zip "C:\Users\ASUS\Downloads\Bakery_Sales_Recent_Dummy_Package.zip" --dry-run
```

The dry run reads the existing bread catalogue, bakery timezone, and sales history. It shows the eight name-to-UUID mappings, active status, package and accepted/rejected/conflict counts, the date range, possible earlier demo rows, and distinct eligible history days before and after import. It makes no database changes. Resolve any reported conflict explicitly before importing; the importer never replaces or deletes records. In particular, do not use the earlier demo dataset alongside this package.

When the dry run says `Import permitted: YES`, the explicit import command is:

```powershell
node --env-file=.env dist/scripts/importAdaptedSales.js --zip "C:\Users\ASUS\Downloads\Bakery_Sales_Recent_Dummy_Package.zip" --apply
```

The apply command repeats the checks against current database rows. It inserts only missing records in one request, without upsert. Exact previously imported validated records are skipped; conflicting earlier demo, actual, simulated, or changed imported records block the whole import. Database uniqueness constraints also reject a duplicate that appears during the write. If any part of the bulk insert fails, PostgreSQL rejects that insert statement rather than partially applying it.

Accepted rows preserve `sales_date`, `units_sold`, and `external_source_reference`. They use `data_origin=IMPORTED_HISTORICAL`, `source_daily_result_id=null`, and `is_validated=true` after package, field, date, quantity, uniqueness, and category checks. `validation_notes` records `ADAPTED_DEMO`, `DUMMY_CONSECUTIVE_DATES`, the original source date and product, and the reviewed CSV hash. The CSV's `is_validated=false` is the pre-review state. Source metadata that has no matching database column is checked but is not stored as a separate column.

No historical weather, holiday, or monsoon values are created. Prediction uses the application's existing missing-context behavior. This command does not generate predictions, train candidates, evaluate models, or activate a model. The existing history selection still prefers validated actual transactions, then imported history, then simulation history per category and date. The model's training, evaluation, fingerprint, and activation rules are unchanged.
