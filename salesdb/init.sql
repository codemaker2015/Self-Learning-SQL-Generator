-- ============================================================
--  Sales Database — intentionally tricky column naming
--  to stress-test LLM query generation
-- ============================================================

-- Drop if re-initialising
DROP TABLE IF EXISTS sales CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS sales_reps CASCADE;

-- ─── sales_reps ───────────────────────────────────────────────
-- "name" here means the rep's name.
-- Possible confusion: sales.name also exists (product name alias
-- stored on the transaction row for historical snapshot).
CREATE TABLE sales_reps (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,          -- rep full name  ← AMBIGUOUS: also in sales
    email           TEXT UNIQUE NOT NULL,
    region          TEXT NOT NULL,          -- APAC / EMEA / AMER / LATAM
    hire_date       DATE NOT NULL,
    commission_pct  NUMERIC(4,2) NOT NULL   -- e.g. 7.50 = 7.5%
);

-- ─── products ─────────────────────────────────────────────────
-- "name" = product name, "price_usd" = master price.
-- Possible confusion: sales also stores price_usd + price_inr
-- at the time of transaction (may differ from master price).
CREATE TABLE products (
    id              SERIAL PRIMARY KEY,
    product_name    TEXT NOT NULL,          -- canonical product name
    name            TEXT NOT NULL,          -- short/SKU name           ← AMBIGUOUS: also sales.name
    category        TEXT NOT NULL,
    price_usd       NUMERIC(10,2) NOT NULL, -- current list price USD    ← AMBIGUOUS: also in sales
    price_inr       NUMERIC(12,2) NOT NULL, -- current list price INR    ← AMBIGUOUS: also in sales
    stock_qty       INT NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE
);

-- ─── customers ────────────────────────────────────────────────
-- "customer_name" = the contracting company / person.
-- "end_customer"  = the actual end-user / beneficiary company —
--                   often different in reseller / distributor chains.
-- Possible confusion: who do you mean by "customer"?
CREATE TABLE customers (
    id              SERIAL PRIMARY KEY,
    customer_name   TEXT NOT NULL,          -- billing entity           ← vs end_customer
    end_customer    TEXT NOT NULL,          -- final recipient/user     ← vs customer_name
    country         TEXT NOT NULL,
    city            TEXT NOT NULL,
    account_tier    TEXT NOT NULL,          -- Gold / Silver / Bronze
    contact_email   TEXT UNIQUE NOT NULL,
    phone           TEXT
);

-- ─── sales ────────────────────────────────────────────────────
-- The main transaction table.  Many columns intentionally echo
-- names found elsewhere:
--
--   sales.name        → snapshot of products.name at sale time     ← vs products.product_name, sales_reps.name
--   sales.product_name→ snapshot of products.product_name          ← vs products.name
--   sales.price_usd   → actual price charged (may differ from list) ← vs products.price_usd
--   sales.price_inr   → INR equivalent at FX rate of transaction   ← vs products.price_inr
--   sales.customer_name → denormalised customer name               ← vs customers.customer_name
--   sales.end_customer  → denormalised end-customer                ← vs customers.end_customer
--
-- This mirrors real-world "wide" sales tables that capture point-in-time
-- snapshots so historical reports don't break when master data changes.
CREATE TABLE sales (
    id              SERIAL PRIMARY KEY,

    -- ── Snapshot columns (point-in-time, may differ from master) ──
    name            TEXT NOT NULL,          -- products.name at time of sale
    product_name    TEXT NOT NULL,          -- products.product_name at time of sale

    price_usd       NUMERIC(10,2) NOT NULL, -- actual charged price USD
    price_inr       NUMERIC(12,2) NOT NULL, -- actual charged price INR (FX at sale time)
    discount_pct    NUMERIC(4,2)  NOT NULL DEFAULT 0,  -- % discount applied
    quantity        INT           NOT NULL DEFAULT 1,
    total_usd       NUMERIC(12,2) GENERATED ALWAYS AS
                        (ROUND(price_usd * quantity * (1 - discount_pct/100), 2)) STORED,
    total_inr       NUMERIC(14,2) GENERATED ALWAYS AS
                        (ROUND(price_inr * quantity * (1 - discount_pct/100), 2)) STORED,

    customer_name   TEXT NOT NULL,          -- customers.customer_name snapshot
    end_customer    TEXT NOT NULL,          -- customers.end_customer snapshot

    -- ── Foreign keys (for JOINs) ──
    product_id      INT REFERENCES products(id),
    customer_id     INT REFERENCES customers(id),
    rep_id          INT REFERENCES sales_reps(id),

    -- ── Deal metadata ──
    deal_stage      TEXT NOT NULL,          -- Closed-Won / Closed-Lost / Refunded
    payment_method  TEXT NOT NULL,          -- Wire / Card / UPI / Crypto / Invoice
    invoice_number  TEXT UNIQUE NOT NULL,
    sale_date       DATE NOT NULL,
    delivery_date   DATE,
    notes           TEXT
);

-- ─── Indexes ──────────────────────────────────────────────────
CREATE INDEX idx_sales_sale_date    ON sales(sale_date);
CREATE INDEX idx_sales_customer_id  ON sales(customer_id);
CREATE INDEX idx_sales_product_id   ON sales(product_id);
CREATE INDEX idx_sales_rep_id       ON sales(rep_id);
CREATE INDEX idx_sales_deal_stage   ON sales(deal_stage);

-- =============================================================
--  SEED DATA
-- =============================================================

INSERT INTO sales_reps (name, email, region, hire_date, commission_pct) VALUES
('Arjun Mehta',       'arjun.mehta@salesco.com',      'APAC',  '2019-03-15', 8.00),
('Sofia Lindqvist',   'sofia.l@salesco.com',           'EMEA',  '2020-07-01', 7.50),
('Marcus Johnson',    'marcus.j@salesco.com',          'AMER',  '2018-11-20', 9.00),
('Priya Nair',        'priya.nair@salesco.com',        'APAC',  '2021-01-10', 7.00),
('Carlos Reyes',      'carlos.r@salesco.com',          'LATAM', '2022-05-03', 6.50),
('Yuki Tanaka',       'yuki.t@salesco.com',            'APAC',  '2020-09-14', 7.75),
('Amara Diallo',      'amara.d@salesco.com',           'EMEA',  '2023-02-28', 6.00),
('Liam O''Brien',     'liam.ob@salesco.com',           'AMER',  '2017-06-05', 9.50);

INSERT INTO products (product_name, name, category, price_usd, price_inr, stock_qty, is_active) VALUES
('Enterprise Analytics Suite',  'ENT-ANALYTICS',  'Software',  12000.00, 1000560.00, 50,  TRUE),
('CloudSync Pro',               'CLOUDSYNC-PRO',  'SaaS',       3500.00,  291410.00, 999, TRUE),
('DataVault 360',               'DV-360',         'Software',   8500.00,  707930.00, 30,  TRUE),
('SecureShield Endpoint',       'SS-ENDPOINT',    'Security',   2200.00,  183260.00, 200, TRUE),
('AI Insight Engine',           'AI-INSIGHT',     'AI/ML',     25000.00, 2082500.00, 20,  TRUE),
('Mobile Command Center',       'MOB-CMD',        'Mobile',     1800.00,  149940.00, 150, TRUE),
('Infrastructure Monitor Pro',  'INFRA-MON',      'DevOps',     4800.00,  399840.00, 75,  TRUE),
('Compliance Manager',          'COMP-MGR',       'Governance', 6600.00,  549780.00, 60,  TRUE),
('HR Nexus Platform',           'HR-NEXUS',       'HR Tech',    5200.00,  433160.00, 40,  TRUE),
('LogiTrack Enterprise',        'LOGI-ENT',       'Logistics',  9800.00,  816580.00, 25,  TRUE);

INSERT INTO customers (customer_name, end_customer, country, city, account_tier, contact_email, phone) VALUES
-- Reseller scenarios: customer_name ≠ end_customer
('TechBridge Solutions',   'Apex Manufacturing Ltd',     'India',     'Mumbai',    'Gold',   'deals@techbridge.in',       '+91-22-4001-5500'),
('GlobalEdge Partners',    'Northern Railways Corp',     'UK',        'London',    'Gold',   'procurement@globaledge.co.uk','+44-20-7946-0900'),
('Synapse Distributors',   'ClearPath Insurance',        'USA',       'Chicago',   'Silver', 'ops@synapsedist.com',        '+1-312-555-0180'),
('Nexus IT Group',         'Sunrise Hospital Network',   'India',     'Bengaluru', 'Gold',   'sales@nexusit.in',          '+91-80-4112-9900'),
('Pacific Rim Tech',       'Harbor Freight Logistics',   'Singapore', 'Singapore', 'Silver', 'info@pacificrimtech.sg',    '+65-6222-8800'),
('Meridian Consulting',    'Federal Transport Agency',   'USA',       'Dallas',    'Gold',   'enterprise@meridian.com',   '+1-214-555-0120'),
-- Direct customers: customer_name = end_customer
('Quantum Dynamics Ltd',   'Quantum Dynamics Ltd',       'Germany',   'Berlin',    'Gold',   'it@quantumdynamics.de',     '+49-30-2200-4400'),
('Atlas Retail Group',     'Atlas Retail Group',         'UAE',       'Dubai',     'Silver', 'tech@atlasretail.ae',       '+971-4-555-8800'),
('Orion Healthcare',       'Orion Healthcare',           'Australia', 'Sydney',    'Bronze', 'ops@orionhealth.com.au',    '+61-2-9988-1100'),
('Vertex Capital',         'Vertex Capital',             'USA',       'New York',  'Gold',   'systems@vertexcap.com',     '+1-212-555-0300'),
('BlueWave Media',         'BlueWave Media',             'France',    'Paris',     'Bronze', 'digital@bluewave.fr',       '+33-1-4200-5500'),
('IronClad Logistics',     'IronClad Logistics',         'Canada',    'Toronto',   'Silver', 'admin@ironclad.ca',         '+1-416-555-0800'),
-- Sub-reseller chain: 3-layer
('DataStream Resellers',   'Pinnacle Auto Industries',   'India',     'Chennai',   'Silver', 'b2b@datastream.in',         '+91-44-2200-6600'),
('SkyNet Solutions',       'Eastern Power Grid Co',      'Japan',     'Tokyo',     'Gold',   'enterprise@skynet.co.jp',   '+81-3-5555-1200'),
('Horizon IT Services',    'Blue Chip Pharma Ltd',       'India',     'Hyderabad', 'Gold',   'sales@horizonit.in',        '+91-40-6600-7700');

-- ─── 100 sales rows ───────────────────────────────────────────
-- FX rate used: 1 USD ≈ 83.30 INR (snapshot varies row to row
-- to simulate real fluctuation, making price_inr ≠ products.price_inr)

INSERT INTO sales (
    name, product_name,
    price_usd, price_inr, discount_pct, quantity,
    customer_name, end_customer,
    product_id, customer_id, rep_id,
    deal_stage, payment_method, invoice_number, sale_date, delivery_date, notes
) VALUES
('ENT-ANALYTICS','Enterprise Analytics Suite',  12000.00,  999600.00, 10.00, 1, 'TechBridge Solutions','Apex Manufacturing Ltd',          1,  1, 1, 'Closed-Won',  'Invoice',  'INV-2024-0001','2024-01-05','2024-01-12','Annual license, on-prem deployment'),
('CLOUDSYNC-PRO','CloudSync Pro',                3500.00,   291550.00,  5.00, 2, 'GlobalEdge Partners','Northern Railways Corp',          2,  2, 2, 'Closed-Won',  'Wire',     'INV-2024-0002','2024-01-08','2024-01-15','2 seats, 12-month SaaS'),
('AI-INSIGHT',  'AI Insight Engine',            25000.00,  2080000.00,  0.00, 1, 'Nexus IT Group','Sunrise Hospital Network',             5,  4, 1, 'Closed-Won',  'Invoice',  'INV-2024-0003','2024-01-11','2024-01-25','POC extended to full rollout'),
('SS-ENDPOINT', 'SecureShield Endpoint',         2200.00,   183260.00,  0.00, 5, 'Synapse Distributors','ClearPath Insurance',            4,  3, 3, 'Closed-Won',  'Card',     'INV-2024-0004','2024-01-14','2024-01-20','5 endpoint licenses'),
('DV-360',      'DataVault 360',                 8500.00,   707225.00, 15.00, 1, 'Pacific Rim Tech','Harbor Freight Logistics',           3,  5, 6, 'Closed-Won',  'Wire',     'INV-2024-0005','2024-01-18','2024-01-30','Negotiated discount for Q1 close'),
('INFRA-MON',   'Infrastructure Monitor Pro',    4800.00,   399360.00,  5.00, 1, 'Meridian Consulting','Federal Transport Agency',        7,  6, 3, 'Closed-Won',  'Invoice',  'INV-2024-0006','2024-01-22','2024-02-05','Gov contract, net-60 terms'),
('ENT-ANALYTICS','Enterprise Analytics Suite',  11000.00,   916300.00,  8.33, 1, 'Quantum Dynamics Ltd','Quantum Dynamics Ltd',           1,  7, 2, 'Closed-Won',  'Wire',     'INV-2024-0007','2024-01-25','2024-02-08','Direct deal, EUR invoice converted'),
('HR-NEXUS',    'HR Nexus Platform',             5200.00,   432900.00,  0.00, 1, 'Atlas Retail Group','Atlas Retail Group',               9,  8, 7, 'Closed-Won',  'Card',     'INV-2024-0008','2024-01-29','2024-02-12','UAE VAT applied separately'),
('CLOUDSYNC-PRO','CloudSync Pro',                3500.00,   290500.00, 10.00, 3, 'Orion Healthcare','Orion Healthcare',                   2,  9, 4, 'Closed-Won',  'Invoice',  'INV-2024-0009','2024-02-02','2024-02-16','Bundled with support plan'),
('LOGI-ENT',    'LogiTrack Enterprise',          9800.00,   815380.00,  0.00, 1, 'DataStream Resellers','Pinnacle Auto Industries',       10, 13, 1, 'Closed-Won',  'Wire',     'INV-2024-0010','2024-02-05','2024-02-20','Supply-chain integration module'),
('COMP-MGR',    'Compliance Manager',            6600.00,   549384.00,  0.00, 1, 'Vertex Capital','Vertex Capital',                      8, 10, 3, 'Closed-Won',  'Invoice',  'INV-2024-0011','2024-02-08','2024-02-22','SOX compliance package'),
('MOB-CMD',     'Mobile Command Center',         1800.00,   149760.00,  5.00, 4, 'SkyNet Solutions','Eastern Power Grid Co',              6, 14, 6, 'Closed-Won',  'Wire',     'INV-2024-0012','2024-02-12','2024-02-26','Field ops rollout'),
('ENT-ANALYTICS','Enterprise Analytics Suite',  12000.00,   998400.00,  0.00, 1, 'Horizon IT Services','Blue Chip Pharma Ltd',           1, 15, 4, 'Closed-Won',  'Invoice',  'INV-2024-0013','2024-02-15','2024-03-01','Pharma vertical template included'),
('SS-ENDPOINT', 'SecureShield Endpoint',         2200.00,   181500.00,  5.00, 8, 'TechBridge Solutions','Apex Manufacturing Ltd',        4,  1, 1, 'Closed-Won',  'Invoice',  'INV-2024-0014','2024-02-19','2024-03-05','Add-on to Jan deal, bulk pricing'),
('AI-INSIGHT',  'AI Insight Engine',            22000.00,  1831600.00, 12.00, 1, 'GlobalEdge Partners','Northern Railways Corp',          5,  2, 2, 'Closed-Won',  'Wire',     'INV-2024-0015','2024-02-22','2024-03-08','Renewal + upgrade'),
('DV-360',      'DataVault 360',                 8500.00,   706650.00,  0.00, 2, 'BlueWave Media','BlueWave Media',                      3, 11, 7, 'Closed-Won',  'Card',     'INV-2024-0016','2024-02-26','2024-03-12','Media asset management use case'),
('INFRA-MON',   'Infrastructure Monitor Pro',    4800.00,   398400.00,  0.00, 1, 'IronClad Logistics','IronClad Logistics',              7, 12, 3, 'Closed-Won',  'Invoice',  'INV-2024-0017','2024-03-01','2024-03-15','Canadian ops monitoring'),
('HR-NEXUS',    'HR Nexus Platform',             4680.00,   389700.00, 10.00, 1, 'Nexus IT Group','Sunrise Hospital Network',            9,  4, 1, 'Closed-Won',  'Invoice',  'INV-2024-0018','2024-03-05','2024-03-20','Hospital HR compliance module'),
('CLOUDSYNC-PRO','CloudSync Pro',                3500.00,   291850.00,  0.00, 1, 'Pacific Rim Tech','Harbor Freight Logistics',           2,  5, 6, 'Closed-Won',  'Wire',     'INV-2024-0019','2024-03-08','2024-03-22','Logistics cloud tier-up'),
('LOGI-ENT',    'LogiTrack Enterprise',          8820.00,   733905.00, 10.00, 1, 'Meridian Consulting','Federal Transport Agency',       10,  6, 3, 'Closed-Won',  'Invoice',  'INV-2024-0020','2024-03-12','2024-03-26','Gov renewal, 10% loyalty discount'),
('COMP-MGR',    'Compliance Manager',            6600.00,   550638.00,  0.00, 2, 'Synapse Distributors','ClearPath Insurance',           8,  3, 3, 'Closed-Won',  'Wire',     'INV-2024-0021','2024-03-15','2024-03-29','GDPR + HIPAA dual package'),
('MOB-CMD',     'Mobile Command Center',         1800.00,   149490.00,  0.00, 2, 'DataStream Resellers','Pinnacle Auto Industries',      6, 13, 1, 'Closed-Won',  'UPI',      'INV-2024-0022','2024-03-19','2024-04-02','Mobile-first factory floor'),
('AI-INSIGHT',  'AI Insight Engine',            25000.00,  2082500.00,  0.00, 1, 'Quantum Dynamics Ltd','Quantum Dynamics Ltd',          5,  7, 2, 'Closed-Won',  'Wire',     'INV-2024-0023','2024-03-22','2024-04-05','R&D analytics workload'),
('ENT-ANALYTICS','Enterprise Analytics Suite',  10800.00,   898560.00, 10.00, 1, 'SkyNet Solutions','Eastern Power Grid Co',            1, 14, 6, 'Closed-Won',  'Invoice',  'INV-2024-0024','2024-03-26','2024-04-09','Utility sector bundle'),
('SS-ENDPOINT', 'SecureShield Endpoint',         2200.00,   183700.00,  0.00, 3, 'Atlas Retail Group','Atlas Retail Group',             4,  8, 7, 'Closed-Won',  'Card',     'INV-2024-0025','2024-03-29','2024-04-12','Retail POS security'),
('DV-360',      'DataVault 360',                 7225.00,   601319.00, 15.00, 1, 'Horizon IT Services','Blue Chip Pharma Ltd',          3, 15, 4, 'Closed-Won',  'Invoice',  'INV-2024-0026','2024-04-02','2024-04-16','Pharma data vault, validated env'),
('INFRA-MON',   'Infrastructure Monitor Pro',    4800.00,   400320.00,  0.00, 2, 'Vertex Capital','Vertex Capital',                    7, 10, 3, 'Closed-Won',  'Invoice',  'INV-2024-0027','2024-04-05','2024-04-19','Two DC monitoring expansions'),
('CLOUDSYNC-PRO','CloudSync Pro',                3500.00,   292250.00,  0.00, 5, 'TechBridge Solutions','Apex Manufacturing Ltd',       2,  1, 1, 'Closed-Won',  'Invoice',  'INV-2024-0028','2024-04-09','2024-04-23','Dept expansion 5 seats'),
('HR-NEXUS',    'HR Nexus Platform',             5200.00,   433160.00,  0.00, 1, 'BlueWave Media','BlueWave Media',                    9, 11, 7, 'Closed-Won',  'Card',     'INV-2024-0029','2024-04-12','2024-04-26','Media HR onboarding module'),
('LOGI-ENT',    'LogiTrack Enterprise',          9800.00,   817740.00,  0.00, 1, 'IronClad Logistics','IronClad Logistics',            10, 12, 3, 'Closed-Won',  'Wire',     'INV-2024-0030','2024-04-16','2024-04-30','Cross-border shipment tracking'),
('MOB-CMD',     'Mobile Command Center',         1800.00,   149040.00,  0.00, 6, 'Nexus IT Group','Sunrise Hospital Network',           6,  4, 1, 'Closed-Won',  'UPI',      'INV-2024-0031','2024-04-19','2024-05-03','Nurse mobile stations'),
('AI-INSIGHT',  'AI Insight Engine',            25000.00,  2085000.00,  0.00, 1, 'GlobalEdge Partners','Northern Railways Corp',        5,  2, 2, 'Closed-Won',  'Wire',     'INV-2024-0032','2024-04-23','2024-05-07','Track predictive maintenance AI'),
('ENT-ANALYTICS','Enterprise Analytics Suite',  12000.00,   999600.00,  0.00, 1, 'Meridian Consulting','Federal Transport Agency',     1,  6, 3, 'Closed-Won',  'Invoice',  'INV-2024-0033','2024-04-26','2024-05-10','Year-2 renewal, no change'),
('SS-ENDPOINT', 'SecureShield Endpoint',         1980.00,   164835.00, 10.00,10, 'Pacific Rim Tech','Harbor Freight Logistics',         4,  5, 6, 'Closed-Won',  'Wire',     'INV-2024-0034','2024-04-30','2024-05-14','10-pack warehouse security'),
('COMP-MGR',    'Compliance Manager',            6600.00,   548460.00,  0.00, 1, 'Synapse Distributors','ClearPath Insurance',          8,  3, 3, 'Closed-Won',  'Invoice',  'INV-2024-0035','2024-05-03','2024-05-17','Insurance regulatory update'),
('DV-360',      'DataVault 360',                 8500.00,   707225.00,  0.00, 1, 'DataStream Resellers','Pinnacle Auto Industries',     3, 13, 1, 'Closed-Won',  'Wire',     'INV-2024-0036','2024-05-07','2024-05-21','Auto parts inventory vault'),
('INFRA-MON',   'Infrastructure Monitor Pro',    4560.00,   379224.00,  5.00, 1, 'Quantum Dynamics Ltd','Quantum Dynamics Ltd',         7,  7, 2, 'Closed-Won',  'Wire',     'INV-2024-0037','2024-05-10','2024-05-24','Berlin DC expansion'),
('CLOUDSYNC-PRO','CloudSync Pro',                3500.00,   291900.00,  0.00, 1, 'SkyNet Solutions','Eastern Power Grid Co',           2, 14, 6, 'Closed-Won',  'Invoice',  'INV-2024-0038','2024-05-14','2024-05-28','Grid ops team sync'),
('HR-NEXUS',    'HR Nexus Platform',             5200.00,   433160.00,  0.00, 1, 'Atlas Retail Group','Atlas Retail Group',            9,  8, 7, 'Closed-Lost', 'N/A',      'INV-2024-0039','2024-05-17',NULL,       'Lost to competitor on price'),
('AI-INSIGHT',  'AI Insight Engine',            20000.00,  1664000.00, 20.00, 1, 'Horizon IT Services','Blue Chip Pharma Ltd',         5, 15, 4, 'Closed-Won',  'Invoice',  'INV-2024-0040','2024-05-21','2024-06-04','Large discount to win pharma logo'),
('LOGI-ENT',    'LogiTrack Enterprise',          9800.00,   815716.00,  0.00, 1, 'Vertex Capital','Vertex Capital',                   10, 10, 3, 'Closed-Won',  'Invoice',  'INV-2024-0041','2024-05-24','2024-06-07','PE portfolio logistics unification'),
('MOB-CMD',     'Mobile Command Center',         1800.00,   149490.00,  0.00, 3, 'BlueWave Media','BlueWave Media',                   6, 11, 7, 'Closed-Lost', 'N/A',      'INV-2024-0042','2024-05-28',NULL,       'Budget frozen mid-Q2'),
('ENT-ANALYTICS','Enterprise Analytics Suite',  12000.00,   998800.00,  0.00, 1, 'IronClad Logistics','IronClad Logistics',           1, 12, 3, 'Closed-Won',  'Invoice',  'INV-2024-0043','2024-05-31','2024-06-14','Supply chain analytics expansion'),
('SS-ENDPOINT', 'SecureShield Endpoint',         2200.00,   183920.00,  0.00, 2, 'TechBridge Solutions','Apex Manufacturing Ltd',      4,  1, 1, 'Closed-Won',  'Invoice',  'INV-2024-0044','2024-06-04','2024-06-18','Plant floor endpoint refresh'),
('COMP-MGR',    'Compliance Manager',            6600.00,   549846.00,  0.00, 1, 'GlobalEdge Partners','Northern Railways Corp',       8,  2, 2, 'Closed-Won',  'Wire',     'INV-2024-0045','2024-06-07','2024-06-21','UK rail safety regulations pkg'),
('DV-360',      'DataVault 360',                 8500.00,   707650.00,  0.00, 1, 'Nexus IT Group','Sunrise Hospital Network',          3,  4, 1, 'Closed-Won',  'Invoice',  'INV-2024-0046','2024-06-11','2024-06-25','Patient data vault, HIPAA scope'),
('CLOUDSYNC-PRO','CloudSync Pro',                3325.00,   276759.00,  5.00, 4, 'Meridian Consulting','Federal Transport Agency',     2,  6, 3, 'Closed-Won',  'Invoice',  'INV-2024-0047','2024-06-14','2024-06-28','Dept-wide cloud migration'),
('INFRA-MON',   'Infrastructure Monitor Pro',    4800.00,   399360.00,  0.00, 1, 'Pacific Rim Tech','Harbor Freight Logistics',        7,  5, 6, 'Closed-Won',  'Wire',     'INV-2024-0048','2024-06-18','2024-07-02','Port facility monitoring'),
('AI-INSIGHT',  'AI Insight Engine',            25000.00,  2082500.00,  0.00, 1, 'Synapse Distributors','ClearPath Insurance',         5,  3, 3, 'Closed-Won',  'Invoice',  'INV-2024-0049','2024-06-21','2024-07-05','Fraud detection AI rollout'),
('HR-NEXUS',    'HR Nexus Platform',             5200.00,   433368.00,  0.00, 1, 'DataStream Resellers','Pinnacle Auto Industries',    9, 13, 1, 'Closed-Won',  'UPI',      'INV-2024-0050','2024-06-25','2024-07-09','Factory HR digital transformation'),
('LOGI-ENT',    'LogiTrack Enterprise',          9800.00,   816320.00,  0.00, 1, 'Quantum Dynamics Ltd','Quantum Dynamics Ltd',        10,  7, 2, 'Closed-Won',  'Wire',     'INV-2024-0051','2024-06-28','2024-07-12','German logistics subsidiary'),
('MOB-CMD',     'Mobile Command Center',         1800.00,   149400.00,  0.00, 5, 'SkyNet Solutions','Eastern Power Grid Co',           6, 14, 6, 'Closed-Won',  'Invoice',  'INV-2024-0052','2024-07-02','2024-07-16','Substation crew mobile kits'),
('ENT-ANALYTICS','Enterprise Analytics Suite',  12000.00,   999200.00,  0.00, 1, 'Atlas Retail Group','Atlas Retail Group',           1,  8, 7, 'Closed-Won',  'Card',     'INV-2024-0053','2024-07-05','2024-07-19','Retail BI dashboard'),
('SS-ENDPOINT', 'SecureShield Endpoint',         2200.00,   183040.00,  0.00, 6, 'Horizon IT Services','Blue Chip Pharma Ltd',         4, 15, 4, 'Closed-Won',  'Invoice',  'INV-2024-0054','2024-07-09','2024-07-23','Pharma lab endpoint security'),
('COMP-MGR',    'Compliance Manager',            6600.00,   549780.00,  0.00, 1, 'Vertex Capital','Vertex Capital',                   8, 10, 3, 'Closed-Won',  'Invoice',  'INV-2024-0055','2024-07-12','2024-07-26','Dodd-Frank compliance update'),
('DV-360',      'DataVault 360',                 8500.00,   707225.00,  0.00, 1, 'BlueWave Media','BlueWave Media',                   3, 11, 7, 'Closed-Won',  'Card',     'INV-2024-0056','2024-07-16','2024-07-30','Digital archive vault'),
('INFRA-MON',   'Infrastructure Monitor Pro',    4800.00,   399840.00,  0.00, 3, 'IronClad Logistics','IronClad Logistics',           7, 12, 3, 'Closed-Won',  'Wire',     'INV-2024-0057','2024-07-19','2024-08-02','3 depot monitoring expansions'),
('CLOUDSYNC-PRO','CloudSync Pro',                3500.00,   291200.00,  0.00, 2, 'TechBridge Solutions','Apex Manufacturing Ltd',      2,  1, 1, 'Closed-Won',  'Invoice',  'INV-2024-0058','2024-07-23','2024-08-06','New plant cloud nodes'),
('AI-INSIGHT',  'AI Insight Engine',            25000.00,  2082500.00,  0.00, 1, 'Nexus IT Group','Sunrise Hospital Network',          5,  4, 1, 'Closed-Won',  'Invoice',  'INV-2024-0059','2024-07-26','2024-08-09','ICU predictive monitoring AI'),
('HR-NEXUS',    'HR Nexus Platform',             5200.00,   432680.00,  0.00, 1, 'GlobalEdge Partners','Northern Railways Corp',       9,  2, 2, 'Closed-Won',  'Wire',     'INV-2024-0060','2024-07-30','2024-08-13','Rail workforce management'),
('LOGI-ENT',    'LogiTrack Enterprise',          8820.00,   734508.00, 10.00, 1, 'Meridian Consulting','Federal Transport Agency',    10,  6, 3, 'Closed-Won',  'Invoice',  'INV-2024-0061','2024-08-02','2024-08-16','Gov logistics year-2 renewal'),
('MOB-CMD',     'Mobile Command Center',         1800.00,   149490.00,  0.00, 2, 'Pacific Rim Tech','Harbor Freight Logistics',        6,  5, 6, 'Refunded',    'Wire',     'INV-2024-0062','2024-08-06','2024-08-20','Refunded — wrong SKU ordered'),
('ENT-ANALYTICS','Enterprise Analytics Suite',  12000.00,   999600.00,  0.00, 1, 'Synapse Distributors','ClearPath Insurance',        1,  3, 3, 'Closed-Won',  'Invoice',  'INV-2024-0063','2024-08-09','2024-08-23','InsureTech analytics expansion'),
('SS-ENDPOINT', 'SecureShield Endpoint',         2200.00,   183260.00,  0.00, 4, 'DataStream Resellers','Pinnacle Auto Industries',   4, 13, 1, 'Closed-Won',  'UPI',      'INV-2024-0064','2024-08-13','2024-08-27','Smart factory endpoint security'),
('COMP-MGR',    'Compliance Manager',            5940.00,   494604.00, 10.00, 1, 'Quantum Dynamics Ltd','Quantum Dynamics Ltd',        8,  7, 2, 'Closed-Won',  'Wire',     'INV-2024-0065','2024-08-16','2024-08-30','EU AI Act compliance prep'),
('DV-360',      'DataVault 360',                 8500.00,   707900.00,  0.00, 1, 'SkyNet Solutions','Eastern Power Grid Co',          3, 14, 6, 'Closed-Won',  'Invoice',  'INV-2024-0066','2024-08-20','2024-09-03','Smart-grid data vault'),
('CLOUDSYNC-PRO','CloudSync Pro',                3500.00,   291550.00,  0.00, 3, 'Atlas Retail Group','Atlas Retail Group',           2,  8, 7, 'Closed-Won',  'Card',     'INV-2024-0067','2024-08-23','2024-09-06','Omni-channel cloud sync'),
('INFRA-MON',   'Infrastructure Monitor Pro',    4800.00,   398880.00,  0.00, 1, 'Horizon IT Services','Blue Chip Pharma Ltd',        7, 15, 4, 'Closed-Won',  'Invoice',  'INV-2024-0068','2024-08-27','2024-09-10','Pharma cold-chain infra monitor'),
('AI-INSIGHT',  'AI Insight Engine',            25000.00,  2082500.00,  0.00, 1, 'Vertex Capital','Vertex Capital',                  5, 10, 3, 'Closed-Won',  'Invoice',  'INV-2024-0069','2024-08-30','2024-09-13','Portfolio risk AI engine'),
('HR-NEXUS',    'HR Nexus Platform',             5200.00,   433160.00,  0.00, 1, 'BlueWave Media','BlueWave Media',                  9, 11, 7, 'Closed-Won',  'Card',     'INV-2024-0070','2024-09-03','2024-09-17','Creative workforce platform'),
('LOGI-ENT',    'LogiTrack Enterprise',          9800.00,   815954.00,  0.00, 1, 'IronClad Logistics','IronClad Logistics',          10, 12, 3, 'Closed-Won',  'Wire',     'INV-2024-0071','2024-09-06','2024-09-20','Cross-dock logistics upgrade'),
('MOB-CMD',     'Mobile Command Center',         1800.00,   149580.00,  0.00, 8, 'TechBridge Solutions','Apex Manufacturing Ltd',     6,  1, 1, 'Closed-Won',  'UPI',      'INV-2024-0072','2024-09-10','2024-09-24','Field service mobile rollout'),
('ENT-ANALYTICS','Enterprise Analytics Suite',  12000.00,   998400.00,  0.00, 1, 'Nexus IT Group','Sunrise Hospital Network',        1,  4, 1, 'Closed-Won',  'Invoice',  'INV-2024-0073','2024-09-13','2024-09-27','Hospital group enterprise renewal'),
('SS-ENDPOINT', 'SecureShield Endpoint',         2200.00,   183480.00,  0.00, 7, 'GlobalEdge Partners','Northern Railways Corp',      4,  2, 2, 'Closed-Won',  'Wire',     'INV-2024-0074','2024-09-17','2024-10-01','Depot security endpoints'),
('DV-360',      'DataVault 360',                 7225.00,   601594.00, 15.00, 1, 'Meridian Consulting','Federal Transport Agency',    3,  6, 3, 'Closed-Won',  'Invoice',  'INV-2024-0075','2024-09-20','2024-10-04','Gov data archive vault'),
('COMP-MGR',    'Compliance Manager',            6600.00,   549780.00,  0.00, 1, 'Pacific Rim Tech','Harbor Freight Logistics',       8,  5, 6, 'Closed-Won',  'Wire',     'INV-2024-0076','2024-09-24','2024-10-08','Port customs compliance'),
('AI-INSIGHT',  'AI Insight Engine',            25000.00,  2082500.00,  0.00, 1, 'Synapse Distributors','ClearPath Insurance',        5,  3, 3, 'Closed-Won',  'Invoice',  'INV-2024-0077','2024-09-27','2024-10-11','Claims AI expansion'),
('CLOUDSYNC-PRO','CloudSync Pro',                3500.00,   291200.00,  0.00, 2, 'DataStream Resellers','Pinnacle Auto Industries',   2, 13, 1, 'Closed-Won',  'UPI',      'INV-2024-0078','2024-10-01','2024-10-15','ERP cloud connector'),
('INFRA-MON',   'Infrastructure Monitor Pro',    4800.00,   399840.00,  0.00, 1, 'Quantum Dynamics Ltd','Quantum Dynamics Ltd',       7,  7, 2, 'Closed-Won',  'Wire',     'INV-2024-0079','2024-10-04','2024-10-18','Q4 infra expansion Berlin'),
('HR-NEXUS',    'HR Nexus Platform',             5200.00,   433576.00,  0.00, 1, 'SkyNet Solutions','Eastern Power Grid Co',         9, 14, 6, 'Closed-Won',  'Invoice',  'INV-2024-0080','2024-10-08','2024-10-22','Energy sector HR platform'),
('MOB-CMD',     'Mobile Command Center',         1800.00,   149940.00,  0.00, 3, 'Atlas Retail Group','Atlas Retail Group',           6,  8, 7, 'Closed-Won',  'Card',     'INV-2024-0081','2024-10-11','2024-10-25','Store-manager mobile app'),
('LOGI-ENT',    'LogiTrack Enterprise',          9800.00,   817180.00,  0.00, 1, 'Horizon IT Services','Blue Chip Pharma Ltd',       10, 15, 4, 'Closed-Won',  'Invoice',  'INV-2024-0082','2024-10-15','2024-10-29','Cold-chain logistics track'),
('ENT-ANALYTICS','Enterprise Analytics Suite',  12000.00,   999200.00,  0.00, 1, 'Vertex Capital','Vertex Capital',                 1, 10, 3, 'Closed-Won',  'Invoice',  'INV-2024-0083','2024-10-18','2024-11-01','PE portfolio analytics'),
('SS-ENDPOINT', 'SecureShield Endpoint',         2200.00,   183700.00,  0.00, 5, 'BlueWave Media','BlueWave Media',                 4, 11, 7, 'Closed-Won',  'Card',     'INV-2024-0084','2024-10-22','2024-11-05','Broadcast studio endpoint sec'),
('COMP-MGR',    'Compliance Manager',            6600.00,   550638.00,  0.00, 1, 'IronClad Logistics','IronClad Logistics',          8, 12, 3, 'Closed-Won',  'Wire',     'INV-2024-0085','2024-10-25','2024-11-08','Transport safety compliance'),
('DV-360',      'DataVault 360',                 8500.00,   707900.00,  0.00, 1, 'TechBridge Solutions','Apex Manufacturing Ltd',    3,  1, 1, 'Closed-Won',  'Invoice',  'INV-2024-0086','2024-10-29','2024-11-12','Manufacturing data vault'),
('CLOUDSYNC-PRO','CloudSync Pro',                3500.00,   291550.00,  0.00, 4, 'Nexus IT Group','Sunrise Hospital Network',        2,  4, 1, 'Closed-Won',  'Invoice',  'INV-2024-0087','2024-11-01','2024-11-15','Hospital dept cloud migration'),
('AI-INSIGHT',  'AI Insight Engine',            25000.00,  2082500.00,  0.00, 1, 'GlobalEdge Partners','Northern Railways Corp',     5,  2, 2, 'Closed-Won',  'Wire',     'INV-2024-0088','2024-11-05','2024-11-19','Rail delay prediction AI'),
('INFRA-MON',   'Infrastructure Monitor Pro',    4800.00,   399360.00,  0.00, 1, 'Meridian Consulting','Federal Transport Agency',   7,  6, 3, 'Closed-Won',  'Invoice',  'INV-2024-0089','2024-11-08','2024-11-22','Gov DC consolidation monitor'),
('HR-NEXUS',    'HR Nexus Platform',             5200.00,   433160.00,  0.00, 1, 'Pacific Rim Tech','Harbor Freight Logistics',      9,  5, 6, 'Closed-Won',  'Wire',     'INV-2024-0090','2024-11-12','2024-11-26','Port HR digitalisation'),
('MOB-CMD',     'Mobile Command Center',         1800.00,   149490.00,  0.00, 4, 'Synapse Distributors','ClearPath Insurance',        6,  3, 3, 'Closed-Won',  'Invoice',  'INV-2024-0091','2024-11-15','2024-11-29','Field adjuster mobile kits'),
('LOGI-ENT',    'LogiTrack Enterprise',          9800.00,   816320.00,  0.00, 1, 'DataStream Resellers','Pinnacle Auto Industries',  10, 13, 1, 'Closed-Won',  'UPI',      'INV-2024-0092','2024-11-19','2024-12-03','Parts logistics upgrade'),
('ENT-ANALYTICS','Enterprise Analytics Suite',  12000.00,   998800.00,  0.00, 1, 'Quantum Dynamics Ltd','Quantum Dynamics Ltd',      1,  7, 2, 'Closed-Won',  'Wire',     'INV-2024-0093','2024-11-22','2024-12-06','Year-end group analytics'),
('SS-ENDPOINT', 'SecureShield Endpoint',         2200.00,   183260.00,  0.00, 9, 'SkyNet Solutions','Eastern Power Grid Co',         4, 14, 6, 'Closed-Won',  'Invoice',  'INV-2024-0094','2024-11-26','2024-12-10','Grid control-room security'),
('COMP-MGR',    'Compliance Manager',            6600.00,   549780.00,  0.00, 1, 'Atlas Retail Group','Atlas Retail Group',          8,  8, 7, 'Closed-Won',  'Card',     'INV-2024-0095','2024-11-29','2024-12-13','Retail PCI-DSS compliance'),
('DV-360',      'DataVault 360',                 8500.00,   708075.00,  0.00, 1, 'Horizon IT Services','Blue Chip Pharma Ltd',       3, 15, 4, 'Closed-Won',  'Invoice',  'INV-2024-0096','2024-12-03','2024-12-17','Year-end pharma vault refresh'),
('AI-INSIGHT',  'AI Insight Engine',            22500.00,  1873125.00, 10.00, 1, 'Vertex Capital','Vertex Capital',                 5, 10, 3, 'Closed-Won',  'Invoice',  'INV-2024-0097','2024-12-06','2024-12-20','Q4 strategic AI deal'),
('CLOUDSYNC-PRO','CloudSync Pro',                3500.00,   291550.00,  0.00, 6, 'BlueWave Media','BlueWave Media',                 2, 11, 7, 'Closed-Won',  'Card',     'INV-2024-0098','2024-12-10','2024-12-24','Media group cloud expansion'),
('INFRA-MON',   'Infrastructure Monitor Pro',    4800.00,   399840.00,  0.00, 1, 'IronClad Logistics','IronClad Logistics',         7, 12, 3, 'Closed-Won',  'Invoice',  'INV-2024-0099','2024-12-13','2024-12-27','Year-end capacity planning'),
('HR-NEXUS',    'HR Nexus Platform',             5200.00,   433160.00,  0.00, 1, 'TechBridge Solutions','Apex Manufacturing Ltd',   9,  1, 1, 'Closed-Won',  'UPI',      'INV-2024-0100','2024-12-17','2024-12-31','Year-end HR system renewal');

-- ─── Handy view for quick reporting ──────────────────────────
CREATE OR REPLACE VIEW sales_summary AS
SELECT
    s.id,
    s.invoice_number,
    s.sale_date,
    -- product columns (the confusing trio)
    s.name              AS product_sku,          -- sales.name  = SKU snapshot
    s.product_name      AS product_full_name,    -- sales.product_name = full name snapshot
    p.name              AS master_sku,           -- products.name = current master SKU
    p.product_name      AS master_product_name,  -- products.product_name = current master name
    -- price columns (snapshot vs master)
    s.price_usd         AS charged_price_usd,
    s.price_inr         AS charged_price_inr,
    p.price_usd         AS current_list_price_usd,
    p.price_inr         AS current_list_price_inr,
    s.discount_pct,
    s.quantity,
    s.total_usd,
    s.total_inr,
    -- customer columns (the other confusing pair)
    s.customer_name     AS billing_customer,     -- who pays
    s.end_customer      AS end_customer,         -- who uses
    c.customer_name     AS master_customer_name, -- master record
    c.end_customer      AS master_end_customer,
    c.country,
    c.city,
    c.account_tier,
    -- rep info
    r.name              AS rep_name,             -- sales_reps.name  ← also called "name"!
    r.region            AS rep_region,
    s.deal_stage,
    s.payment_method
FROM sales s
JOIN products p  ON p.id  = s.product_id
JOIN customers c ON c.id  = s.customer_id
JOIN sales_reps r ON r.id = s.rep_id;
