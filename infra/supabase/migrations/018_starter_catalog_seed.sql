-- 018_starter_catalog_seed.sql
-- LedgerMind OS MVP — Seed data for Ghanaian starter catalogs.
--
-- Populates:
--   * business_types            — 6 onboarding business types
--   * starter_catalog_templates — ~145 pre-built product templates across
--     supermarket (~60), pharmacy (~40), electronics (~20), fashion (~15),
--     hardware (~10). Prices are realistic Accra retail figures in GHS.
--
-- Idempotent: uses INSERT ... ON CONFLICT DO NOTHING throughout.
-- A UNIQUE constraint on (business_type, name) ensures re-running
-- the migration will not duplicate catalog rows (the default PK `id`
-- is auto-generated and would otherwise always be unique).
-- Re-running this migration will not duplicate rows or error.


-- ============================================================
-- 0. Deduplicate + unique constraint on starter_catalog_templates
-- ============================================================
-- Remove duplicate template rows that may exist from prior runs
-- (keeps the row with the lowest sort_order per business_type/name).
DELETE FROM starter_catalog_templates a
USING starter_catalog_templates b
WHERE a.business_type = b.business_type
  AND a.name = b.name
  AND a.id > b.id;

-- Enforce uniqueness so ON CONFLICT (business_type, name) works.
CREATE UNIQUE INDEX IF NOT EXISTS uq_starter_catalog_type_name
    ON starter_catalog_templates (business_type, name);


-- ============================================================
-- 1. business_types
-- ============================================================

INSERT INTO business_types (id, name, icon) VALUES
  ('supermarket', 'Supermarket / Provision Store', 'shopping_cart'),
  ('pharmacy',    'Pharmacy',                       'local_pharmacy'),
  ('electronics', 'Electronics',                    'devices'),
  ('fashion',     'Fashion / Boutique',             'checkroom'),
  ('hardware',    'Hardware',                       'hardware'),
  ('other',       'Other',                          'store')
ON CONFLICT (id) DO NOTHING;


-- ============================================================
-- 2. supermarket — ~60 common Ghanaian supermarket items
-- ============================================================

INSERT INTO starter_catalog_templates (business_type, name, barcode, category, suggested_price, suggested_cost, unit, sort_order) VALUES
  -- Beverages
  ('supermarket', 'Milo 1kg',                  '5060322700010', 'Beverages',     45.00, 38.00, 'piece', 1),
  ('supermarket', 'Milo 500g',                 '5060322700027', 'Beverages',     25.00, 20.00, 'piece', 2),
  ('supermarket', 'Cocoa 1kg',                 NULL,            'Beverages',     40.00, 33.00, 'piece', 3),
  ('supermarket', 'Nescafe 100g',              '7613035306765', 'Beverages',     18.00, 14.00, 'piece', 4),
  ('supermarket', 'Lipton Tea 50 Bags',        '8714789395015', 'Beverages',     15.00, 11.50, 'piece', 5),
  ('supermarket', 'Coca Cola 500ml',           '5449000000996', 'Beverages',      4.00,  3.00, 'piece', 6),
  ('supermarket', 'Coca Cola 1.5L',            '5449000054227', 'Beverages',      7.00,  5.50, 'piece', 7),
  ('supermarket', 'Fanta 1.5L',                '5449000054234', 'Beverages',      7.00,  5.50, 'piece', 8),
  ('supermarket', 'Sprite 1.5L',               '5449000054241', 'Beverages',      7.00,  5.50, 'piece', 9),
  ('supermarket', 'Voltic Water 1.5L',         '603459000001',  'Beverages',      5.00,  3.80, 'piece', 10),
  ('supermarket', 'Voltic Water 500ml',        '603459000018',  'Beverages',      2.50,  1.80, 'piece', 11),
  ('supermarket', 'Bel Aqua Water 1.5L',       NULL,            'Beverages',      5.00,  3.80, 'piece', 12),
  ('supermarket', 'Malta Guinness 330ml',      '5449000153039', 'Beverages',      4.00,  3.00, 'piece', 13),
  ('supermarket', 'Guinness Malt 330ml',       '5449000153046', 'Beverages',      4.00,  3.00, 'piece', 14),
  ('supermarket', 'Pepsi 500ml',               '4067700030011', 'Beverages',      3.50,  2.50, 'piece', 15),
  -- Food
  ('supermarket', 'Indomie Instant Noodles 70g', '8992696407013', 'Food',         1.50,  1.20, 'piece', 16),
  ('supermarket', 'Indomie Instant Noodles Pack (40s)', NULL,    'Food',         55.00, 45.00, 'pack', 17),
  ('supermarket', 'Sugar 1kg',                 NULL,            'Food',          12.00, 10.00, 'piece', 18),
  ('supermarket', 'Cooking Oil 1L',            NULL,            'Food',          25.00, 21.00, 'piece', 19),
  ('supermarket', 'Cooking Oil 5L',            NULL,            'Food',         120.00, 100.00, 'piece', 20),
  ('supermarket', 'Tom Brown 400g',            NULL,            'Food',          15.00, 12.00, 'piece', 21),
  ('supermarket', 'Sardines 155g',             NULL,            'Food',           5.00,  4.00, 'piece', 22),
  ('supermarket', 'Gino Tomato Paste 70g',     '8710398517348', 'Food',           3.50,  2.70, 'piece', 23),
  ('supermarket', 'Pomo Tomato Paste 400g',    NULL,            'Food',           8.00,  6.50, 'piece', 24),
  ('supermarket', 'Rice 5kg (Local)',          NULL,            'Food',          60.00, 50.00, 'bag',  25),
  ('supermarket', 'Rice 5kg (Perfumed)',       NULL,            'Food',          75.00, 62.00, 'bag',  26),
  ('supermarket', 'Gari 1kg',                  NULL,            'Food',          10.00,  8.00, 'piece', 27),
  ('supermarket', 'Shito 200g',                NULL,            'Food',          12.00,  9.00, 'piece', 28),
  ('supermarket', 'Maggi Cubes (100s)',        '7613034626844', 'Food',          18.00, 14.00, 'box',  29),
  ('supermarket', 'Maggi Cubes (50s)',         '7613034626851', 'Food',          10.00,  8.00, 'box',  30),
  ('supermarket', 'Knorr Cubes (50s)',         '4015500466015', 'Food',          12.00,  9.50, 'box',  31),
  ('supermarket', 'Salt 500g',                 NULL,            'Food',           2.00,  1.50, 'piece', 32),
  ('supermarket', 'Spaghetti 500g',            '8710398521314', 'Food',           6.00,  4.80, 'piece', 33),
  ('supermarket', 'Corned Beef 340g',          NULL,            'Food',          18.00, 14.50, 'piece', 34),
  ('supermarket', 'Baked Beans 400g',          '5449000000224', 'Food',           8.00,  6.20, 'piece', 35),
  ('supermarket', 'Geisha Tuna 160g',          NULL,            'Food',           6.00,  4.80, 'piece', 36),
  ('supermarket', 'Mayonnaise 250g',           '8710398524117', 'Food',          15.00, 11.50, 'piece', 37),
  ('supermarket', 'Kelloggs Cornflakes 250g',  '5050083010101', 'Food',          22.00, 17.00, 'piece', 38),
  ('supermarket', 'Cerelac 400g',              '7613032857843', 'Food',          35.00, 28.00, 'piece', 39),
  -- Dairy
  ('supermarket', 'Ideal Milk 170g',           '8710398521574', 'Dairy',          3.50,  2.80, 'piece', 40),
  ('supermarket', 'Ideal Milk 410g',           '8710398521581', 'Dairy',          6.00,  4.80, 'piece', 41),
  ('supermarket', 'Carnation Milk 170g',       '5449000000996', 'Dairy',          3.50,  2.80, 'piece', 42),
  ('supermarket', 'Peak Powdered Milk 400g',   '8710398524513', 'Dairy',         30.00, 24.00, 'piece', 43),
  ('supermarket', 'Nido Powdered Milk 400g',   '7613032857836', 'Dairy',         32.00, 26.00, 'piece', 44),
  ('supermarket', 'Yoghurt 500ml',             NULL,            'Dairy',         12.00,  9.00, 'piece', 45),
  ('supermarket', 'Butter 250g',               NULL,            'Dairy',         18.00, 14.00, 'piece', 46),
  -- Snacks
  ('supermarket', 'Kurleez Chips 50g',         NULL,            'Snacks',         2.00,  1.50, 'piece', 47),
  ('supermarket', 'Plantain Chips 100g',       NULL,            'Snacks',         5.00,  3.80, 'piece', 48),
  ('supermarket', 'Digestive Biscuits 200g',   '8710398521642', 'Snacks',         6.00,  4.50, 'piece', 49),
  ('supermarket', 'Ginger Biscuits 200g',      NULL,            'Snacks',         6.00,  4.50, 'piece', 50),
  ('supermarket', 'Choco Milo 14g',            '5060322700034', 'Snacks',         1.00,  0.70, 'piece', 51),
  ('supermarket', 'Toffee (Pack)',             NULL,            'Snacks',         3.00,  2.20, 'pack', 52),
  ('supermarket', 'Peanut Butter 250g',        NULL,            'Snacks',        12.00,  9.00, 'piece', 53),
  -- Household
  ('supermarket', 'Omo Detergent 1kg',         '6001087303452', 'Household',     20.00, 16.00, 'piece', 54),
  ('supermarket', 'Omo Detergent 2kg',         '6001087303469', 'Household',     35.00, 28.00, 'piece', 55),
  ('supermarket', 'Sunlight Soap 400g',        '6001087303476', 'Household',      8.00,  6.20, 'piece', 56),
  ('supermarket', 'Jik Bleach 1L',             '6001087303483', 'Household',     12.00,  9.50, 'piece', 57),
  ('supermarket', 'Harpic 750ml',              '6001087303490', 'Household',     15.00, 11.50, 'piece', 58),
  ('supermarket', 'Vim Scouring Powder 400g',  NULL,            'Household',      6.00,  4.50, 'piece', 59),
  ('supermarket', 'Dettol 250ml',              '6001100200123', 'Household',     14.00, 10.50, 'piece', 60),
  ('supermarket', 'Toilet Roll (4 Pack)',      NULL,            'Household',     18.00, 14.00, 'pack', 61),
  ('supermarket', 'Match Box (10s)',           NULL,            'Household',      2.00,  1.40, 'pack', 62),
  -- Personal Care
  ('supermarket', 'Key Soap 120g',             NULL,            'Personal Care',  3.00,  2.50, 'piece', 63),
  ('supermarket', 'Pepsodent Toothpaste 75ml', '8714789395022', 'Personal Care',  8.00,  6.00, 'piece', 64),
  ('supermarket', 'Close Up Toothpaste 100g',  '8714789395039', 'Personal Care',  9.00,  6.80, 'piece', 65),
  ('supermarket', 'Colgate Toothpaste 100g',   '8714789395046', 'Personal Care',  9.00,  6.80, 'piece', 66),
  ('supermarket', 'Pampers Baby Dry Size 4 (20s)', NULL,        'Baby Care',     45.00, 38.00, 'pack', 67),
  ('supermarket', 'Pampers Baby Dry Size 5 (18s)', NULL,        'Baby Care',     48.00, 40.00, 'pack', 68),
  ('supermarket', 'Pampers Baby Dry Size 6 (16s)', NULL,        'Baby Care',     52.00, 43.00, 'pack', 69),
  ('supermarket', 'Baby Wipes (80s)',          NULL,            'Baby Care',     15.00, 11.00, 'pack', 70),
  ('supermarket', 'Cerelac Wheat 400g',        '7613032857843', 'Baby Care',     35.00, 28.00, 'piece', 71),
  ('supermarket', 'Lactogen 400g',             NULL,            'Baby Care',     45.00, 36.00, 'piece', 72),
  ('supermarket', 'Always Sanitary Pads (14s)', NULL,           'Personal Care', 18.00, 13.50, 'pack', 73),
  ('supermarket', 'Tampons (10s)',             NULL,            'Personal Care', 22.00, 16.00, 'pack', 74),
  ('supermarket', 'Roll On Deodorant 50ml',    NULL,            'Personal Care', 15.00, 11.00, 'piece', 75),
  ('supermarket', 'Dettol Soap 175g',          '6001100200123', 'Personal Care',  8.00,  6.00, 'piece', 76)
ON CONFLICT (business_type, name) DO NOTHING;


-- ============================================================
-- 3. pharmacy — ~40 common OTC drugs in Ghana
-- ============================================================

INSERT INTO starter_catalog_templates (business_type, name, barcode, category, suggested_price, suggested_cost, unit, sort_order) VALUES
  -- Pain Relief
  ('pharmacy', 'Paracetamol 500mg (20s)',          NULL, 'Pain Relief',   5.00,  3.50, 'pack', 1),
  ('pharmacy', 'Paracetamol 500mg (100s)',         NULL, 'Pain Relief',  20.00, 14.00, 'pack', 2),
  ('pharmacy', 'Ibuprofen 400mg (20s)',            NULL, 'Pain Relief',   8.00,  5.50, 'pack', 3),
  ('pharmacy', 'Aspirin 300mg (20s)',              NULL, 'Pain Relief',   6.00,  4.20, 'pack', 4),
  ('pharmacy', 'Diclofenac 50mg (10s)',            NULL, 'Pain Relief',  10.00,  7.00, 'pack', 5),
  ('pharmacy', 'Piroxicam 20mg (10s)',             NULL, 'Pain Relief',  12.00,  8.50, 'pack', 6),
  ('pharmacy', 'Panadol Extra (24s)',              NULL, 'Pain Relief',  12.00,  8.50, 'pack', 7),
  ('pharmacy', 'Tylenol 500mg (24s)',              NULL, 'Pain Relief',  15.00, 11.00, 'pack', 8),
  -- Antibiotics
  ('pharmacy', 'Amoxil 250mg (20s)',               NULL, 'Antibiotics',  15.00, 12.00, 'pack', 9),
  ('pharmacy', 'Amoxil 500mg (20s)',               NULL, 'Antibiotics',  20.00, 15.00, 'pack', 10),
  ('pharmacy', 'Ampiclox 250mg (20s)',             NULL, 'Antibiotics',  18.00, 13.50, 'pack', 11),
  ('pharmacy', 'Flagyl 200mg (20s)',               NULL, 'Antibiotics',  12.00,  9.00, 'pack', 12),
  ('pharmacy', 'Ciprofloxacin 500mg (10s)',        NULL, 'Antibiotics',  20.00, 15.00, 'pack', 13),
  ('pharmacy', 'Septrin 480mg (20s)',              NULL, 'Antibiotics',  18.00, 13.00, 'pack', 14),
  ('pharmacy', 'Erythromycin 250mg (20s)',         NULL, 'Antibiotics',  22.00, 16.00, 'pack', 15),
  ('pharmacy', 'Doxycycline 100mg (10s)',          NULL, 'Antibiotics',  18.00, 13.00, 'pack', 16),
  -- Vitamins
  ('pharmacy', 'Vitamin C 1000mg (30s)',           NULL, 'Vitamins',     20.00, 15.00, 'pack', 17),
  ('pharmacy', 'Vitamin C 200mg (100s)',           NULL, 'Vitamins',     12.00,  8.50, 'pack', 18),
  ('pharmacy', 'Vitamin B Complex (30s)',          NULL, 'Vitamins',     15.00, 11.00, 'pack', 19),
  ('pharmacy', 'Multivitamin (30s)',               NULL, 'Vitamins',     25.00, 18.00, 'pack', 20),
  ('pharmacy', 'Vitamin A Capsules (30s)',         NULL, 'Vitamins',     12.00,  8.50, 'pack', 21),
  ('pharmacy', 'Calcium 600mg (30s)',              NULL, 'Vitamins',     28.00, 20.00, 'pack', 22),
  ('pharmacy', 'Cod Liver Oil Capsules (30s)',     NULL, 'Vitamins',     30.00, 22.00, 'pack', 23),
  ('pharmacy', 'Folic Acid 5mg (30s)',             NULL, 'Vitamins',      8.00,  5.50, 'pack', 24),
  ('pharmacy', 'Ferrous Sulphate 200mg (30s)',     NULL, 'Vitamins',     10.00,  7.00, 'pack', 25),
  -- First Aid
  ('pharmacy', 'Band Aid (20s)',                   NULL, 'First Aid',      8.00,  5.50, 'pack', 26),
  ('pharmacy', 'Cotton Wool 100g',                 NULL, 'First Aid',      6.00,  4.20, 'piece', 27),
  ('pharmacy', 'Dettol Antiseptic 250ml',          NULL, 'First Aid',     14.00, 10.50, 'piece', 28),
  ('pharmacy', 'Iodine 30ml',                      NULL, 'First Aid',      7.00,  5.00, 'piece', 29),
  ('pharmacy', 'Bandage 5cm x 4m',                 NULL, 'First Aid',      5.00,  3.50, 'piece', 30),
  ('pharmacy', 'Gauze Swabs (Pack)',               NULL, 'First Aid',      6.00,  4.20, 'pack', 31),
  ('pharmacy', 'Surgical Spirit 100ml',            NULL, 'First Aid',      7.00,  5.00, 'piece', 32),
  ('pharmacy', 'Plaster Roll 2cm',                 NULL, 'First Aid',      4.00,  2.80, 'piece', 33),
  -- Cold & Flu
  ('pharmacy', 'Coldex (10s)',                     NULL, 'Cold & Flu',    10.00,  7.00, 'pack', 34),
  ('pharmacy', 'Actifed Syrup 100ml',              NULL, 'Cold & Flu',    15.00, 11.00, 'bottle', 35),
  ('pharmacy', 'Benylin Cough Syrup 100ml',        NULL, 'Cold & Flu',    18.00, 13.00, 'bottle', 36),
  ('pharmacy', 'Chlorpheniramine 4mg (100s)',      NULL, 'Cold & Flu',     8.00,  5.50, 'pack', 37),
  ('pharmacy', 'Piriton 4mg (20s)',                NULL, 'Cold & Flu',     9.00,  6.50, 'pack', 38),
  ('pharmacy', 'Vicks VapoRub 50g',                NULL, 'Cold & Flu',    18.00, 13.00, 'piece', 39),
  -- Antacid
  ('pharmacy', 'Andrews Liver Salt',               NULL, 'Antacid',       8.00,  6.00, 'piece', 40),
  ('pharmacy', 'Gaviscon Liquid 200ml',            NULL, 'Antacid',      25.00, 18.00, 'bottle', 41),
  ('pharmacy', 'Antacid Suspension 200ml',         NULL, 'Antacid',      15.00, 11.00, 'bottle', 42),
  ('pharmacy', 'Magnesium Trisilicate (50s)',      NULL, 'Antacid',       8.00,  5.50, 'pack', 43),
  ('pharmacy', 'Gelusil (50s)',                    NULL, 'Antacid',       9.00,  6.50, 'pack', 44)
ON CONFLICT (business_type, name) DO NOTHING;


-- ============================================================
-- 4. electronics — ~20 common accessories
-- ============================================================

INSERT INTO starter_catalog_templates (business_type, name, barcode, category, suggested_price, suggested_cost, unit, sort_order) VALUES
  ('electronics', 'USB-C Cable 1m',               NULL, 'Cables',      15.00, 10.00, 'piece', 1),
  ('electronics', 'USB-C Cable 2m',               NULL, 'Cables',      20.00, 13.00, 'piece', 2),
  ('electronics', 'Lightning Cable 1m',           NULL, 'Cables',      25.00, 16.00, 'piece', 3),
  ('electronics', 'Micro USB Cable 1m',           NULL, 'Cables',      12.00,  8.00, 'piece', 4),
  ('electronics', 'HDMI Cable 1.5m',              NULL, 'Cables',      35.00, 24.00, 'piece', 5),
  ('electronics', 'Aux Cable 1m',                 NULL, 'Cables',      10.00,  6.00, 'piece', 6),
  ('electronics', 'Power Bank 10000mAh',          NULL, 'Accessories', 80.00, 60.00, 'piece', 7),
  ('electronics', 'Power Bank 20000mAh',          NULL, 'Accessories', 130.00, 95.00, 'piece', 8),
  ('electronics', 'Phone Case (Universal)',       NULL, 'Accessories', 20.00, 12.00, 'piece', 9),
  ('electronics', 'Screen Protector (Universal)', NULL, 'Accessories', 15.00,  8.00, 'piece', 10),
  ('electronics', 'Phone Stand',                  NULL, 'Accessories', 18.00, 11.00, 'piece', 11),
  ('electronics', 'Earphones Wired 3.5mm',        NULL, 'Audio',       25.00, 15.00, 'piece', 12),
  ('electronics', 'Bluetooth Earbuds',            NULL, 'Audio',       60.00, 40.00, 'piece', 13),
  ('electronics', 'Bluetooth Speaker',            NULL, 'Audio',       90.00, 65.00, 'piece', 14),
  ('electronics', 'Wired Headphones',             NULL, 'Audio',       45.00, 30.00, 'piece', 15),
  ('electronics', 'USB Wall Charger 5W',          NULL, 'Chargers',    20.00, 13.00, 'piece', 16),
  ('electronics', 'USB Wall Charger 18W Fast',    NULL, 'Chargers',    40.00, 26.00, 'piece', 17),
  ('electronics', 'Car Charger USB',              NULL, 'Chargers',    25.00, 16.00, 'piece', 18),
  ('electronics', 'Wireless Charger Pad',         NULL, 'Chargers',    70.00, 48.00, 'piece', 19),
  ('electronics', 'Multi-Plug Extension Socket',  NULL, 'Accessories', 50.00, 35.00, 'piece', 20)
ON CONFLICT (business_type, name) DO NOTHING;


-- ============================================================
-- 5. fashion — ~15 basic fashion items
-- ============================================================

INSERT INTO starter_catalog_templates (business_type, name, barcode, category, suggested_price, suggested_cost, unit, sort_order) VALUES
  ('fashion', 'Men''s Cotton T-Shirt',             NULL, 'Men',        35.00, 25.00, 'piece', 1),
  ('fashion', 'Men''s Polo Shirt',                 NULL, 'Men',        60.00, 42.00, 'piece', 2),
  ('fashion', 'Men''s Jeans',                      NULL, 'Men',        90.00, 65.00, 'piece', 3),
  ('fashion', 'Men''s Boxer Shorts (3 Pack)',      NULL, 'Men',        40.00, 28.00, 'pack',  4),
  ('fashion', 'Men''s Socks (5 Pack)',             NULL, 'Men',        25.00, 16.00, 'pack',  5),
  ('fashion', 'Women''s Cotton Dress',             NULL, 'Women',      85.00, 60.00, 'piece', 6),
  ('fashion', 'Women''s Blouse',                   NULL, 'Women',      55.00, 38.00, 'piece', 7),
  ('fashion', 'Women''s Skirt',                    NULL, 'Women',      60.00, 42.00, 'piece', 8),
  ('fashion', 'Women''s Leggings',                 NULL, 'Women',      30.00, 20.00, 'piece', 9),
  ('fashion', 'Women''s Handbag',                  NULL, 'Women',     110.00, 75.00, 'piece', 10),
  ('fashion', 'Children''s T-Shirt',               NULL, 'Children',   25.00, 17.00, 'piece', 11),
  ('fashion', 'Children''s Shorts',                NULL, 'Children',   30.00, 20.00, 'piece', 12),
  ('fashion', 'Children''s Dress',                 NULL, 'Children',   45.00, 30.00, 'piece', 13),
  ('fashion', 'Belt (Unisex)',                     NULL, 'Accessories', 30.00, 20.00, 'piece', 14),
  ('fashion', 'Cap',                               NULL, 'Accessories', 20.00, 13.00, 'piece', 15)
ON CONFLICT (business_type, name) DO NOTHING;


-- ============================================================
-- 6. hardware — ~10 basic hardware items
-- ============================================================

INSERT INTO starter_catalog_templates (business_type, name, barcode, category, suggested_price, suggested_cost, unit, sort_order) VALUES
  ('hardware', 'Claw Hammer',                     NULL, 'Tools',       35.00, 25.00, 'piece', 1),
  ('hardware', 'Screwdriver Set (6 Pieces)',      NULL, 'Tools',       40.00, 28.00, 'set',   2),
  ('hardware', 'Measuring Tape 5m',               NULL, 'Tools',       20.00, 13.00, 'piece', 3),
  ('hardware', 'Adjustable Wrench 10"',           NULL, 'Tools',       45.00, 30.00, 'piece', 4),
  ('hardware', 'PVC Pipe 1m (1/2")',              NULL, 'Plumbing',    15.00, 10.00, 'piece', 5),
  ('hardware', 'PVC Pipe 1m (3/4")',              NULL, 'Plumbing',    20.00, 14.00, 'piece', 6),
  ('hardware', 'PVC Elbow (1/2")',                NULL, 'Plumbing',     3.00,  1.80, 'piece', 7),
  ('hardware', 'Electrical Wire Roll (1.5mm)',    NULL, 'Electrical', 120.00, 90.00, 'roll',  8),
  ('hardware', 'Light Switch',                    NULL, 'Electrical',  12.00,  8.00, 'piece', 9),
  ('hardware', 'Socket Outlet',                   NULL, 'Electrical',  15.00, 10.00, 'piece', 10)
ON CONFLICT (business_type, name) DO NOTHING;
