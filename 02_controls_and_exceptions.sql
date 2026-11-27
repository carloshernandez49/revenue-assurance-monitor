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
