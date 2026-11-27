# Order-to-Cash Revenue Assurance Monitor

SQL controls and a Power BI dashboard that find billing and collection errors in a simulated payments-industry services business.

> **Note:** all data in this project is simulated. The business is fictional.

## Why this project exists

Payments companies do more than move money. They also sell services, such as data insights, consulting and loyalty platforms, to banks, merchants and fintechs around the world. Every engagement follows the same path: an **order**, an **invoice** and a **payment**. At global scale, small errors add up: a service delivered but never billed, an invoice with the wrong rate, a duplicate invoice, or a customer who pays late.

**Revenue assurance** means making sure every service delivered is billed correctly and paid on time. This project builds a simple, repeatable way to do that.

## What it does

- Checks every order, invoice and payment against **five controls**.
- Logs each exception with a severity, an owner team and a status.
- Shows where the money is at risk, where exceptions concentrate and which team is resolving them.

## Dashboard preview

| The Story | Executive Summary |
|---|---|
| ![The Story](docs/screenshots/01_the_story.png) | ![Executive Summary](docs/screenshots/02_executive_summary.png) |

| Exceptions Analysis | Team Performance |
|---|---|
| ![Exceptions Analysis](docs/screenshots/03_exceptions_analysis.png) | ![Team Performance](docs/screenshots/04_team_performance.png) |

## Data model

Six tables in MySQL (`revenue_assurance` database), plus a control parameter table and an exceptions log.

| Table | Content |
|---|---|
| `customers` | 50 customers (banks, merchants and fintechs) in four regions |
| `contracts` | One contract per customer, with a service type and an agreed rate per unit |
| `orders` | 2,000 service orders (January to October 2026). Amount = units Ã— agreed rate |
| `invoices` | 1,956 invoices. Payment terms are 30 days |
| `payments` | Customer payments linked to invoices |
| `config` | Cut-off date and control thresholds, kept in one place |
| `exceptions_log` | One row per exception found by the controls |

## The five controls

Each control is a SQL view. All views return the same columns, so they can be stacked into one exceptions log.

| ID | Control | What it detects | Owner team |
|---|---|---|---|
| C1 | Unbilled revenue | An order with no invoice more than 30 days after the service date | Finance - Billing |
| C2 | Invoice vs contract amount mismatch | An invoice amount that differs from the order amount by more than $0.01 | Sales Operations |
| C3 | Duplicate invoice | The same order invoiced more than once (each extra invoice is flagged) | Controllership |
| C4 | Overdue receivable | An invoice past its due date with an unpaid balance, with aging buckets (1-30, 31-60, 61-90, 90+ days) | Finance - Collections |
| C5 | Late invoicing | An invoice issued more than 14 days after the service date | Finance - Billing |

**Amount at risk:** C1 = order amount, C2 = absolute difference, C3 = duplicated amount, C4 = unpaid balance, C5 = invoice amount.

**Severity:** High â‰¥ $2,500, Medium â‰¥ $500, Low below $500.

## How the controls were validated

Errors were seeded into the simulated data with fixed rules, so the results are reproducible and every control can be tested against a known answer.

| Seeded error | Rule | Expected | Found |
|---|---|---|---|
| Order never invoiced | `order_id MOD 31 = 0` | 64 orders | 64 orders (60 flagged by C1, because 4 are less than 30 days old) |
| Invoice amount Â±8% | `order_id MOD 47 = 0` | 41 invoices | 41 |
| Duplicate invoice | `order_id MOD 97 = 0` | 20 | 20 |

The setup script ends with a validation query that compares actual and expected counts.

## Key results (simulated data)

| Metric | Value |
|---|---|
| Total exceptions | 487 (C1: 60, C2: 41, C3: 20, C4: 234, C5: 132) |
| Open exceptions | 372 |
| Closed exceptions | 115 (closure rate 23.6%) |
| Open revenue at risk (C1-C4) | $863,385 |
| Overdue receivables share of open revenue at risk | 72% ($620K) |
| On-time invoicing | 93.2% |
| Average days to close | 10.9 |

## Dashboard pages

1. **The Story:** the business problem, explained in plain language.
2. **Executive Summary:** four KPI cards, exceptions by month and control, and open revenue at risk by control.
3. **Exceptions Analysis:** exceptions by control and severity, and open exceptions by region.
4. **Team Performance:** open and closed exceptions, closure rate and average days to close by owner team.

### Power BI measures

`Total Exceptions`, `Open Exceptions`, `Closed Exceptions`, `Closure Rate`, `Open Revenue at Risk (C1-C4)`, `On-Time Invoicing %` and `Avg Days to Close`. The full DAX code and the page layout are in [`powerbi/measures_and_layout.md`](powerbi/measures_and_layout.md).

## Tech stack

- **MySQL 8.0+** (tested on 8.0 and 9.7): tables, views, recursive CTEs, generated columns
- **Power BI Desktop:** data model, DAX measures, report design
- **MySQL Workbench:** running the scripts

## How to run it

**Requirements:** MySQL 8.0 or higher, MySQL Workbench (or the command line), Power BI Desktop (Windows) and MySQL Connector/NET.

1. Run `sql/01_setup_revenue_assurance.sql`. It creates the `revenue_assurance` database, the tables and the simulated data, and ends with a validation table.
   > **Warning:** the script drops and recreates a database called `revenue_assurance`.
2. Run `sql/02_controls_and_exceptions.sql`. It creates the five control views, the exceptions log and the reporting view.
3. Open `powerbi/revenue_assurance_monitor.pbix`. If Power BI asks for a connection, go to **Home > Transform data > Data source settings**, point it to your MySQL server and enter your credentials on the **Database** tab. Then refresh.
4. Check the result: **Total Exceptions = 487** and **Open Exceptions = 372**.

## Design decisions

- **Fixed cut-off date (2026-11-12)** stored in `config`, so results do not change over time.
- **Thresholds in one table** (30 days for unbilled revenue, 14 days for late invoicing), so they are easy to change.
- **One view per control**, so each rule is transparent and can be reviewed on its own.
- **An exceptions log with severity, owner and status**, designed like a work queue, not just a report.
- **Late invoicing (C5) is excluded from "revenue at risk".** It is a timing risk, not a loss, so it is tracked through the on-time invoicing KPI.

## Limitations

- All data is simulated, and the business is fictional.
- Exception status is simulated: about one in four exceptions is marked as closed by a fixed rule. The closure rate and the days to close show how the metrics work, not real team performance.
- Some groups are small. For example, Controllership has only 20 exceptions, so its closure rate is a signal to investigate, not a conclusion.
- The model is simplified: one contract per customer, one currency, fixed payment terms and no credit notes.

## Skills demonstrated

- **SQL:** joins, views, recursive CTEs, aggregations, data validation against known answers
- **Controls and assurance:** control design, thresholds, severity, ownership and follow-up of exceptions
- **Data modeling and DAX:** relationships, a calendar table, sort-by-column, KPI measures
- **Reporting:** a dashboard organized by the questions each page answers, with clear insights
- **Documentation:** a control matrix, a validation table and stated limitations

## Repository structure

```
revenue-assurance-monitor/
â”œâ”€â”€ README.md
â”œâ”€â”€ sql/
â”‚   â”œâ”€â”€ 01_setup_revenue_assurance.sql
â”‚   â””â”€â”€ 02_controls_and_exceptions.sql
â”œâ”€â”€ powerbi/
â”‚   â”œâ”€â”€ revenue_assurance_monitor.pbix
â”‚   â””â”€â”€ measures_and_layout.md
â””â”€â”€ docs/
    â””â”€â”€ screenshots/
```

## About the author


-- ============================================================
-- Order-to-Cash Revenue Assurance Monitor
-- Step 2: control views + exceptions log (MySQL 8.0+)
-- Run AFTER 01_setup_revenue_assurance.sql
-- ============================================================

USE revenue_assurance;

-- Clean re-run
DROP VIEW  IF EXISTS v_exceptions_detail;
DROP TABLE IF EXISTS exceptions_log;
DROP VIEW  IF EXISTS v_ctrl_c1_unbilled_revenue;
DROP VIEW  IF EXISTS v_ctrl_c2_amount_mismatch;
DROP VIEW  IF EXISTS v_ctrl_c3_duplicate_invoices;
DROP VIEW  IF EXISTS v_ctrl_c4_overdue_receivables;
DROP VIEW  IF EXISTS v_ctrl_c5_late_invoicing;
DROP TABLE IF EXISTS config;

-- ------------------------------------------------------------
-- 1. Control parameters (one place to change thresholds)
-- ------------------------------------------------------------
CREATE TABLE config (
    cutoff_date        DATE NOT NULL,   -- reporting date, fixed so results are reproducible
    unbilled_days      INT  NOT NULL,   -- C1: days after service before an order counts as unbilled
    late_invoice_days  INT  NOT NULL    -- C5: max days between service and invoice
);
INSERT INTO config VALUES ('2026-11-12', 30, 14);

-- ------------------------------------------------------------
-- 2. Controls. Every view returns the same columns so they can be stacked.
-- ------------------------------------------------------------

-- C1. Unbilled revenue: service delivered, no invoice after N days
CREATE VIEW v_ctrl_c1_unbilled_revenue AS
SELECT 'C1' AS control_id,
       'Unbilled revenue' AS control_name,
       o.order_id,
       CAST(NULL AS SIGNED) AS invoice_id,
       o.customer_id,
       DATE_ADD(o.service_date, INTERVAL cfg.unbilled_days + 1 DAY) AS detected_date,
       o.amount AS amount_at_risk,
       CONCAT('No invoice ', DATEDIFF(cfg.cutoff_date, o.service_date), ' days after service') AS detail
FROM orders o
CROSS JOIN config cfg
LEFT JOIN invoices i ON i.order_id = o.order_id
WHERE i.order_id IS NULL
  AND DATEDIFF(cfg.cutoff_date, o.service_date) > cfg.unbilled_days;

-- C2. Invoice amount differs from the contracted amount
CREATE VIEW v_ctrl_c2_amount_mismatch AS
SELECT 'C2' AS control_id,
       'Invoice vs contract amount mismatch' AS control_name,
       i.order_id,
       i.invoice_id,
       o.customer_id,
       i.invoice_date AS detected_date,
       ABS(i.amount - o.amount) AS amount_at_risk,
       CONCAT('Invoiced ', i.amount, ' vs contract ', o.amount) AS detail
FROM invoices i
JOIN orders o ON o.order_id = i.order_id
WHERE ABS(i.amount - o.amount) > 0.01;

-- C3. Duplicate invoices: the same order invoiced more than once
CREATE VIEW v_ctrl_c3_duplicate_invoices AS
SELECT 'C3' AS control_id,
       'Duplicate invoice' AS control_name,
       i.order_id,
       i.invoice_id,
       o.customer_id,
       i.invoice_date AS detected_date,
       i.amount AS amount_at_risk,
       CONCAT('Order invoiced ', d.invoice_count, ' times') AS detail
FROM invoices i
JOIN orders o ON o.order_id = i.order_id
JOIN (
    SELECT order_id, MIN(invoice_id) AS first_invoice_id, COUNT(*) AS invoice_count
    FROM invoices
    GROUP BY order_id
    HAVING COUNT(*) > 1
) d ON d.order_id = i.order_id
WHERE i.invoice_id <> d.first_invoice_id;      -- flag only the extra invoice(s)

-- C4. Overdue receivables with aging bucket
CREATE VIEW v_ctrl_c4_overdue_receivables AS
SELECT 'C4' AS control_id,
       'Overdue receivable' AS control_name,
       i.order_id,
       i.invoice_id,
       o.customer_id,
       DATE_ADD(i.due_date, INTERVAL 1 DAY) AS detected_date,
       i.amount - COALESCE(p.paid_amount, 0) AS amount_at_risk,
       CONCAT(DATEDIFF(cfg.cutoff_date, i.due_date), ' days overdue (aging ',
              CASE
                  WHEN DATEDIFF(cfg.cutoff_date, i.due_date) <= 30 THEN '1-30'
                  WHEN DATEDIFF(cfg.cutoff_date, i.due_date) <= 60 THEN '31-60'
                  WHEN DATEDIFF(cfg.cutoff_date, i.due_date) <= 90 THEN '61-90'
                  ELSE '90+'
              END, ')') AS detail
FROM invoices i
JOIN orders o ON o.order_id = i.order_id
CROSS JOIN config cfg
LEFT JOIN (
    SELECT invoice_id, SUM(amount) AS paid_amount
    FROM payments
    GROUP BY invoice_id
) p ON p.invoice_id = i.invoice_id
WHERE i.amount - COALESCE(p.paid_amount, 0) > 0.01
  AND i.due_date < cfg.cutoff_date;

-- C5. Late invoicing: invoice issued too long after the service date
CREATE VIEW v_ctrl_c5_late_invoicing AS
SELECT 'C5' AS control_id,
       'Late invoicing' AS control_name,
       i.order_id,
       i.invoice_id,
       o.customer_id,
       i.invoice_date AS detected_date,
       i.amount AS amount_at_risk,
       CONCAT('Invoiced ', DATEDIFF(i.invoice_date, o.service_date), ' days after service') AS detail
FROM invoices i
JOIN orders o ON o.order_id = i.order_id
CROSS JOIN config cfg
WHERE DATEDIFF(i.invoice_date, o.service_date) > cfg.late_invoice_days
  AND i.invoice_id = (SELECT MIN(x.invoice_id) FROM invoices x WHERE x.order_id = i.order_id);

-- ------------------------------------------------------------
-- 3. Exceptions log: one row per exception, with severity, owner and status
-- ------------------------------------------------------------
CREATE TABLE exceptions_log (
    exception_id   INT PRIMARY KEY AUTO_INCREMENT,
    control_id     VARCHAR(5)   NOT NULL,
    control_name   VARCHAR(60)  NOT NULL,
    order_id       INT          NOT NULL,
    invoice_id     INT          NULL,
    customer_id    INT          NOT NULL,
    detected_date  DATE         NOT NULL,
    amount_at_risk DECIMAL(12,2) NOT NULL,
    severity       VARCHAR(10)  NOT NULL,
    owner_team     VARCHAR(30)  NOT NULL,
    status         VARCHAR(10)  NOT NULL DEFAULT 'Open',
    closed_date    DATE         NULL,
    detail         VARCHAR(120) NULL
);

INSERT INTO exceptions_log
    (control_id, control_name, order_id, invoice_id, customer_id,
     detected_date, amount_at_risk, severity, owner_team, detail)
SELECT control_id, control_name, order_id, invoice_id, customer_id,
       detected_date, amount_at_risk,
       CASE WHEN amount_at_risk >= 2500 THEN 'High'
            WHEN amount_at_risk >=  500 THEN 'Medium'
            ELSE 'Low' END,
       CASE control_id
            WHEN 'C1' THEN 'Finance - Billing'
            WHEN 'C2' THEN 'Sales Operations'
            WHEN 'C3' THEN 'Controllership'
            WHEN 'C4' THEN 'Finance - Collections'
            ELSE 'Finance - Billing'
       END,
       detail
FROM (
    SELECT * FROM v_ctrl_c1_unbilled_revenue
    UNION ALL SELECT * FROM v_ctrl_c2_amount_mismatch
    UNION ALL SELECT * FROM v_ctrl_c3_duplicate_invoices
    UNION ALL SELECT * FROM v_ctrl_c4_overdue_receivables
    UNION ALL SELECT * FROM v_ctrl_c5_late_invoicing
) all_controls
ORDER BY detected_date, control_id, order_id;

-- Simulated remediation: about 1 in 4 exceptions has already been closed
UPDATE exceptions_log
SET status = 'Closed',
    closed_date = DATE_ADD(detected_date, INTERVAL 3 + (exception_id MOD 20) DAY)
WHERE exception_id MOD 4 = 0
  AND DATE_ADD(detected_date, INTERVAL 3 + (exception_id MOD 20) DAY) <= (SELECT cutoff_date FROM config);

-- ------------------------------------------------------------
-- 4. Reporting view for Power BI (exceptions + customer attributes)
-- ------------------------------------------------------------
CREATE VIEW v_exceptions_detail AS
SELECT e.exception_id, e.control_id, e.control_name, e.severity, e.owner_team,
       e.status, e.detected_date, e.closed_date, e.amount_at_risk, e.detail,
       e.order_id, e.invoice_id,
       c.customer_id, c.customer_name, c.region, c.segment
FROM exceptions_log e
JOIN customers c ON c.customer_id = e.customer_id;

-- ------------------------------------------------------------
-- 5. Validation: exceptions by control
-- ------------------------------------------------------------
SELECT control_id,
       control_name,
       COUNT(*)                                   AS exceptions,
       SUM(status = 'Closed')                     AS closed,
       ROUND(SUM(amount_at_risk), 2)              AS total_amount_at_risk
FROM exceptions_log
GROUP BY control_id, control_name
ORDER BY control_id;

**Carlos Alexander HernÃ¡ndez BolÃ­var** is an internal control and audit professional with more than 20 years of experience in financial control and measurement auditing, now moving into data analytics.

[LinkedIn](https://www.linkedin.com/in/YOUR-PROFILE)

This project was built with AI assistance (Claude) for design review and troubleshooting. All results were checked against the database.
