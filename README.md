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

**Carlos Alexander HernÃ¡ndez BolÃ­var** is an internal control and audit professional with more than 20 years of experience in financial control and measurement auditing, now moving into data analytics.

[LinkedIn](https://www.linkedin.com/in/YOUR-PROFILE)

This project was built with AI assistance (Claude) for design review and troubleshooting. All results were checked against the database.
