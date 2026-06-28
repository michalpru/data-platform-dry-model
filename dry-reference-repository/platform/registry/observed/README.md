# Observed runtime objects

Observed objects are discovered from runtime systems rather than declared by artifact owners.

Examples:
- warehouse tables and views from catalog scans
- UDFs and stored procedures discovered from warehouse metadata
- dashboard metrics from BI metadata APIs
- query-log references to raw tables or shadow copies

Observed objects are used for bypass detection and duplication hotspot analysis. They are not automatically trusted reuse interfaces. If an observed object should become reusable, it must be promoted through normal lifecycle, manifest, compatibility, and registry gates.