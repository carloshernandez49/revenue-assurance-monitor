-- ============================================================
-- Order-to-Cash Revenue Assurance Monitor
-- Step 1: data model + simulated data (MySQL 8.0+)
-- Errors are seeded with fixed rules (MOD) so results are
-- reproducible and every control can be validated.
-- ============================================================

DROP DATABASE IF EXISTS revenue_assurance;
CREATE DATABASE revenue_assurance;
USE revenue_assurance;

-- Required for the recursive CTEs that generate rows
SET SESSION cte_max_recursion_depth = 5000;

-- ------------------------------------------------------------
-- 1. Tables
-- ------------------------------------------------------------
CREATE TABLE customers (
    customer_id   INT PRIMARY KEY,
    customer_name VARCHAR(60) NOT NULL,
    region        VARCHAR(20) NOT NULL,
    segment       VARCHAR(20) NOT NULL
);

CREATE TABLE contracts (
    contract_id  INT PRIMARY KEY,
    customer_id  INT NOT NULL,
    service_type VARCHAR(30) NOT NULL,
    agreed_rate  DECIMAL(10,2) NOT NULL,   -- contracted rate per unit
    start_date   DATE NOT NULL,
    FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
);

CREATE TABLE orders (
    order_id     INT PRIMARY KEY,
    contract_id  INT NOT NULL,
    customer_id  INT NOT NULL,
    service_date DATE NOT NULL,
    units        INT NOT NULL,
    amount       DECIMAL(12,2) NOT NULL,   -- units * agreed_rate (amount that should be invoiced)
    FOREIGN KEY (contract_id) REFERENCES contracts (contract_id),
    FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
);

CREATE TABLE invoices (
    invoice_id   INT PRIMARY KEY AUTO_INCREMENT,
    order_id     INT NOT NULL,
    invoice_date DATE NOT NULL,
    amount       DECIMAL(12,2) NOT NULL,
    due_date     DATE AS (DATE_ADD(invoice_date, INTERVAL 30 DAY)) STORED,
    FOREIGN KEY (order_id) REFERENCES orders (order_id)
);

CREATE TABLE payments (
    payment_id   INT PRIMARY KEY AUTO_INCREMENT,
    invoice_id   INT NOT NULL,
    payment_date DATE NOT NULL,
    amount       DECIMAL(12,2) NOT NULL,
    FOREIGN KEY (invoice_id) REFERENCES invoices (invoice_id)
);

-- ------------------------------------------------------------
-- 2. Base data: 50 customers, 1 contract per customer
-- ------------------------------------------------------------
INSERT INTO customers
WITH RECURSIVE n AS (
    SELECT 1 AS i
    UNION ALL
    SELECT i + 1 FROM n WHERE i < 50
)
SELECT i,
       CONCAT('Customer ', LPAD(i, 3, '0')),
       ELT(1 + (i MOD 4), 'North America', 'LATAM', 'EMEA', 'APAC'),
       ELT(1 + (i MOD 3), 'Bank', 'Merchant', 'Fintech')
FROM n;

INSERT INTO contracts
SELECT customer_id,
       customer_id,
       ELT(1 + (customer_id MOD 3), 'Data Insights', 'Consulting', 'Loyalty Platform'),
       ROUND(80 + (customer_id MOD 7) * 15, 2),
       '2025-01-01'
FROM customers;

-- ------------------------------------------------------------
-- 3. 2,000 service orders (January to October 2026)
-- ------------------------------------------------------------
INSERT INTO orders
WITH RECURSIVE n AS (
    SELECT 1 AS i
    UNION ALL
    SELECT i + 1 FROM n WHERE i < 2000
),
o AS (
    SELECT i, 5 + (CRC32(CONCAT('u', i)) MOD 46) AS units
    FROM n
)
SELECT o.i,
       c.contract_id,
       c.customer_id,
       DATE_ADD('2026-01-01', INTERVAL (o.i MOD 300) DAY),
       o.units,
       o.units * c.agreed_rate
FROM o
JOIN contracts c ON c.contract_id = 1 + (o.i MOD 50);

-- ------------------------------------------------------------
-- 4. Invoices, with seeded errors
--    - order_id MOD 31 = 0  -> order is NOT invoiced (unbilled revenue)
--    - order_id MOD 47 = 0  -> invoice amount differs from contract (+8% or -8%)
-- ------------------------------------------------------------
INSERT INTO invoices (order_id, invoice_date, amount)
SELECT o.order_id,
       DATE_ADD(o.service_date, INTERVAL 1 + (CRC32(CONCAT('l', o.order_id)) MOD 15) DAY),
       ROUND(
           CASE
               WHEN o.order_id MOD 47 = 0
                   THEN o.amount * IF(o.order_id MOD 2 = 0, 1.08, 0.92)
               ELSE o.amount
           END, 2)
FROM orders o
WHERE o.order_id MOD 31 <> 0;

-- order_id MOD 97 = 0 -> duplicate invoice
INSERT INTO invoices (order_id, invoice_date, amount)
SELECT order_id, invoice_date, amount
FROM invoices
WHERE order_id MOD 97 = 0;

-- ------------------------------------------------------------
-- 5. Payments
--    - invoice_id MOD 8 = 0 -> never paid (overdue receivables)
--    - the rest pay 10 to 39 days after invoicing
--      (terms are 30 days, so some customers pay late)
--    - no payments dated after the 2026-11-12 cut-off date
-- ------------------------------------------------------------
INSERT INTO payments (invoice_id, payment_date, amount)
SELECT invoice_id, pay_date, amount
FROM (
    SELECT invoice_id,
           amount,
           DATE_ADD(invoice_date, INTERVAL 10 + (CRC32(CONCAT('p', invoice_id)) MOD 30) DAY) AS pay_date
    FROM invoices
    WHERE invoice_id MOD 8 <> 0
) p
WHERE pay_date <= '2026-11-12';

-- ------------------------------------------------------------
-- 6. Validation: actual counts must match expected counts
-- ------------------------------------------------------------
SELECT 'customers' AS check_name, COUNT(*) AS actual_rows, 50 AS expected_rows FROM customers
UNION ALL SELECT 'contracts',           COUNT(*), 50   FROM contracts
UNION ALL SELECT 'orders',              COUNT(*), 2000 FROM orders
UNION ALL SELECT 'invoices',            COUNT(*), 1956 FROM invoices          -- 1,936 + 20 duplicates
UNION ALL SELECT 'unbilled orders',     COUNT(*), 64
          FROM orders o LEFT JOIN invoices i ON i.order_id = o.order_id
          WHERE i.order_id IS NULL
UNION ALL SELECT 'invoices with amount mismatch', COUNT(*), 41
          FROM invoices i JOIN orders o ON o.order_id = i.order_id
          WHERE ABS(i.amount - o.amount) > 0.01
UNION ALL SELECT 'orders with duplicate invoice', COUNT(*), 20
          FROM (SELECT order_id FROM invoices GROUP BY order_id HAVING COUNT(*) > 1) d;

-- ------------------------------------------------------------
-- 7. Control 1: unbilled revenue (more than 30 days after service date)
--    A fixed cut-off date keeps the result reproducible over time.
-- ------------------------------------------------------------
SELECT o.order_id, o.customer_id, o.service_date, o.amount AS unbilled_amount
FROM orders o
LEFT JOIN invoices i ON i.order_id = o.order_id
WHERE i.order_id IS NULL
  AND DATEDIFF('2026-11-12', o.service_date) > 30
ORDER BY o.amount DESC;
