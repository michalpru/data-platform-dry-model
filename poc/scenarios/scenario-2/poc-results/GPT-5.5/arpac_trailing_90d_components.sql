-- Reusable components dataset for executive trailing-90-day ARPAC.
-- Preconditions:
-- 1. The active-customer binding below is the resolved certified Databricks view. If this
--    model runs outside Databricks, that binding must be reachable from the target engine.
-- 2. The recognized-revenue dbt macro source contract was not readable in this workspace;
--    identifiers labeled UNCONFIRMED must be reconciled with the registered source contract
--    before production promotion.

with active_customers as (
    select distinct
        customer_id, -- UNCONFIRMED: source contract could not be opened from sales/datasets/commercial_customer_status_90d.sql
        reporting_date
    from sales.datasets.commercial_customer_status_90d
    where reporting_date = {{ var('arpac_reporting_date_sql', 'current_date') }}
      and is_active_commercial_90d = true
),

recognized_revenue_90d as (
    select
        customer_id, -- UNCONFIRMED: macro output contract could not be opened from finance/logic/dbt/recognized_revenue_relation.sql
        net_recognized_revenue_usd -- UNCONFIRMED: macro output contract could not be opened from finance/logic/dbt/recognized_revenue_relation.sql
    from {{ dry_finance_macros.recognized_revenue_relation(
        start_date_sql=var('arpac_window_start_sql', "dateadd(day, -89, current_date)"),
        end_date_sql=var('arpac_reporting_date_sql', 'current_date')
    ) }}
),

active_customer_revenue_90d as (
    select
        active_customers.reporting_date,
        active_customers.customer_id,
        coalesce(sum(recognized_revenue_90d.net_recognized_revenue_usd), 0) as net_recognized_revenue_usd_90d
    from active_customers
    left join recognized_revenue_90d
      on recognized_revenue_90d.customer_id = active_customers.customer_id
    group by
        active_customers.reporting_date,
        active_customers.customer_id
)

select
    reporting_date,
    sum(net_recognized_revenue_usd_90d) as numerator_net_recognized_revenue_usd_90d,
    count(distinct customer_id) as denominator_active_customers,
    sum(net_recognized_revenue_usd_90d) / nullif(count(distinct customer_id), 0) as arpac_trailing_90d_usd
from active_customer_revenue_90d
group by reporting_date