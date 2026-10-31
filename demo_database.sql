-- =============================================================================
-- bi_demo  -  demo database for the talk
-- "SQL Did Exactly What You Asked. That's the Problem."
-- Everything revolves around: "How much revenue did we make yesterday?"
--
-- A fictional online gaming operator. 100% generated data, no real data.
-- Target: MySQL 8.0 (verified on 8.0.46).
--
-- Import:
--   Workbench : File > Open SQL Script > this file > Execute (lightning bolt)
--   CLI       : mysql -u root < demo_database.sql
--
-- Deterministic: CRC32/MD5-based generation (no RAND()), so every import
-- produces exactly the same rows and the same numbers on the slides.
--
-- All DATETIME columns store UTC.
-- The talk's frozen "now" is Tue 2026-10-20 16:00 UTC (= 18:00 in Skopje,
-- when the talk starts), so "yesterday" is Monday 2026-10-19.
--
-- Named time zones (Europe/Skopje, ...) used by the demo QUERIES need the
-- time zone tables loaded once per server:
--   mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -u root mysql
-- =============================================================================

SET SQL_SAFE_UPDATES = 0;          -- Workbench blocks UPDATE/DELETE without a key otherwise
SET SESSION time_zone = '+00:00';  -- we write UTC
SET @salt = 'rev-54';              -- generator seed (fixed; changes every number)
SET @start = TIMESTAMP('2026-10-06 00:00:00');
SET @now   = TIMESTAMP('2026-10-20 16:00:00');
SET @span  = TIMESTAMPDIFF(SECOND, @start, @now);

DROP DATABASE IF EXISTS bi_demo;
CREATE DATABASE bi_demo CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE bi_demo;

-- helper: numbers 0 .. 99,999 (dropped at the end)
CREATE TABLE _digits (d TINYINT PRIMARY KEY);
INSERT INTO _digits VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);
CREATE TABLE _seq (n INT PRIMARY KEY);
INSERT INTO _seq
SELECT a.d + 10*b.d + 100*c.d + 1000*e.d + 10000*f.d
FROM _digits a, _digits b, _digits c, _digits e, _digits f;

-- =============================================================================
-- customers : 10,000
--   1 .. 9990      regular customers (about 70% of them bet in the period)
--   9991 .. 10000  QA test accounts (is_test = 1)
-- =============================================================================
CREATE TABLE customers (
    customer_id   INT          NOT NULL PRIMARY KEY,
    username      VARCHAR(40)  NOT NULL,
    country       CHAR(2)      NOT NULL,
    is_test       TINYINT(1)   NOT NULL DEFAULT 0,
    registered_at DATETIME     NOT NULL,              -- UTC
    UNIQUE KEY uq_username (username)
) ENGINE=InnoDB;

INSERT INTO customers (customer_id, username, country, is_test, registered_at)
SELECT n,
       IF(n > 9990, CONCAT('qa_test_', n - 9990), CONCAT('player_', LPAD(n, 4, '0'))),
       ELT(1 + MOD(CRC32(CONCAT(@salt, 'country', n)), 10),
           'MK','MK','MK','MK','RS','RS','BA','BA','GE','GE'),
       IF(n > 9990, 1, 0),
       TIMESTAMP('2025-01-01') + INTERVAL MOD(CRC32(CONCAT(@salt, 'reg', n)), 55123200) SECOND
FROM _seq
WHERE n BETWEEN 1 AND 10000;

CREATE TABLE _active (rn INT PRIMARY KEY, customer_id INT NOT NULL);
INSERT INTO _active
SELECT ROW_NUMBER() OVER (ORDER BY customer_id), customer_id
FROM customers
WHERE customer_id <= 9990
  AND MOD(CRC32(CONCAT(@salt, 'act', customer_id)), 10) < 7;
SET @n_active = (SELECT COUNT(*) FROM _active);

-- =============================================================================
-- bets : 100,000, placed 2026-10-06 00:00 .. 2026-10-20 16:00 UTC
--   status      settled | placed (still open) | cancelled | rolled_back
--   payout      0 until a bet is won
--   bonus_cost  free-bet value paid by the operator, NULL for normal bets
--   settled_at  when the result was decided (UTC)
--   synced_at   when that result reached the reporting database (UTC)
--   updated_at  added at the end: ON UPDATE CURRENT_TIMESTAMP
-- =============================================================================
CREATE TABLE bets (
    bet_id       INT            NOT NULL PRIMARY KEY,
    customer_id  INT            NOT NULL,
    bet_type     VARCHAR(10)    NOT NULL,             -- single | double | treble
    stake        DECIMAL(12,2)  NOT NULL,
    total_odds   DECIMAL(8,2)   NULL,
    payout       DECIMAL(12,2)  NOT NULL DEFAULT 0,
    bonus_cost   DECIMAL(12,2)  NULL,
    status       VARCHAR(12)    NOT NULL,
    promo_tag    VARCHAR(20)    NULL,
    placed_at    DATETIME       NOT NULL,
    settled_at   DATETIME       NULL,
    synced_at    DATETIME       NULL,
    KEY ix_customer (customer_id),
    KEY ix_placed   (placed_at),
    KEY ix_settled  (settled_at)
) ENGINE=InnoDB;

INSERT INTO bets (bet_id, customer_id, bet_type, stake, payout, bonus_cost, status, placed_at, settled_at)
SELECT g.n, g.customer_id, g.bet_type, g.stake, 0,
       IF(g.is_test = 0 AND g.hfb < 4, g.stake, NULL),
       CASE WHEN g.status = 'settled' AND g.placed_at + INTERVAL g.delay_s SECOND > @now
            THEN 'placed' ELSE g.status END,
       g.placed_at,
       CASE WHEN g.status IN ('settled', 'rolled_back')
             AND g.placed_at + INTERVAL g.delay_s SECOND <= @now
            THEN g.placed_at + INTERVAL g.delay_s SECOND END
FROM (
    SELECT h.n, h.is_test, h.hfb,
           IF(h.is_test, 9991 + MOD(h.hc, 10), a.customer_id)              AS customer_id,
           IF(h.is_test, 'single', ELT(h.kt, 'single', 'double', 'treble')) AS bet_type,
           CASE WHEN h.is_test THEN 50
                WHEN h.kt = 1  THEN ELT(1 + MOD(h.hs, 8), 5, 10, 10, 20, 20, 20, 50, 50)
                WHEN h.kt = 2  THEN ELT(1 + MOD(h.hs, 5), 2, 2, 5, 5, 10)
                ELSE                ELT(1 + MOD(h.hs, 4), 1, 2, 2, 5) END     AS stake,
           CASE WHEN h.hst < 30 THEN 'cancelled'
                WHEN h.hst < 32 THEN 'rolled_back'
                ELSE 'settled' END                                          AS status,
           @start + INTERVAL h.ht SECOND                                    AS placed_at,
           IF(h.hd < 993, 1200 + MOD(h.hdd, 13200),                         -- 20 min .. 4 h
                          14400 + MOD(h.hdd, 244800))                       AS delay_s   -- 4 h .. 3 days
    FROM (
        SELECT s.n,
               MOD(CRC32(CONCAT(@salt, 't',  s.n)), @span)    AS ht,
               CASE WHEN MOD(CRC32(CONCAT(@salt, 'k', s.n)), 100) < 80 THEN 1
                    WHEN MOD(CRC32(CONCAT(@salt, 'k', s.n)), 100) < 94 THEN 2
                    ELSE 3 END                                AS kt,
               CRC32(CONCAT(@salt, 's',  s.n))                AS hs,
               MOD(CRC32(CONCAT(@salt, 'st', s.n)), 1000)     AS hst,
               MOD(CRC32(CONCAT(@salt, 'd',  s.n)), 1000)     AS hd,
               CRC32(CONCAT(@salt, 'dd', s.n))                AS hdd,
               CRC32(CONCAT(@salt, 'c',  s.n))                AS hc,
               MOD(CRC32(CONCAT(@salt, 'fb', s.n)), 100)      AS hfb,
               MOD(CRC32(CONCAT(@salt, 'x',  s.n)), 10000) < 12 AS is_test
        FROM (SELECT n + 1 AS n FROM _seq) s
    ) h
    JOIN _active a ON a.rn = 1 + MOD(h.hc, @n_active)
) g;

-- one row per leg of a bet (singles 1, doubles 2, trebles 3)
CREATE TABLE bet_selections (
    selection_id  INT           NOT NULL AUTO_INCREMENT PRIMARY KEY,
    bet_id        INT           NOT NULL,
    leg_no        TINYINT       NOT NULL,
    sport         VARCHAR(12)   NOT NULL,
    odds          DECIMAL(6,2)  NOT NULL,
    UNIQUE KEY uq_bet_leg (bet_id, leg_no),
    KEY ix_sport (sport, bet_id)
) ENGINE=InnoDB;

INSERT INTO bet_selections (bet_id, leg_no, sport, odds)
SELECT b.bet_id, x.i,
       ELT(1 + MOD(CRC32(CONCAT(@salt, 'sp', b.bet_id, '-', x.i)), 10),
           'football','football','football','football','football','football',
           'tennis','tennis','basketball','basketball'),
       1.30 + MOD(CRC32(CONCAT(@salt, 'o', b.bet_id, '-', x.i)), 131) / 100
FROM bets b
JOIN (SELECT 1 AS i UNION ALL SELECT 2 UNION ALL SELECT 3) x
  ON x.i <= CASE b.bet_type WHEN 'single' THEN 1 WHEN 'double' THEN 2 ELSE 3 END
ORDER BY b.bet_id, x.i;

UPDATE bets b
JOIN (SELECT bet_id, ROUND(EXP(SUM(LN(odds))), 2) AS tot
      FROM bet_selections GROUP BY bet_id) x ON x.bet_id = b.bet_id
SET b.total_odds = x.tot;

-- winners: probability 0.92 / total_odds (an 8% house margin). QA accounts never win.
UPDATE bets
SET payout = ROUND(stake * total_odds, 2)
WHERE status = 'settled'
  AND customer_id <= 9990
  AND MOD(CRC32(CONCAT(@salt, 'w', bet_id)), 100000) < 92000 / total_odds;

-- results reach the reporting database a few seconds after settlement...
UPDATE bets
SET synced_at = settled_at + INTERVAL (2 + MOD(bet_id, 9)) SECOND
WHERE settled_at IS NOT NULL;

-- ...except a provider batch on Monday evening (22:30-24:00 Skopje) that arrived 3 hours late
UPDATE bets
SET synced_at = settled_at + INTERVAL 3 HOUR
WHERE settled_at >= '2026-10-19 20:30:00' AND settled_at < '2026-10-19 22:00:00'
  AND MOD(CRC32(CONCAT(@salt, 'late', bet_id)), 100) < 15;

-- updated_at: "last time this row changed", maintained by MySQL.
-- Added last, so the generator's own UPDATEs above don't touch it.
ALTER TABLE bets
  ADD COLUMN updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  ADD KEY ix_updated (updated_at);
UPDATE bets SET updated_at = COALESCE(settled_at, placed_at);   -- explicit value: no auto-update

-- =============================================================================
-- payouts : the payment side. One row per won bet, paid when the bet settles.
-- =============================================================================
CREATE TABLE payouts (
    payout_id  INT            NOT NULL AUTO_INCREMENT PRIMARY KEY,
    bet_id     INT            NOT NULL,
    amount     DECIMAL(12,2)  NOT NULL,
    paid_at    DATETIME       NOT NULL,               -- UTC
    UNIQUE KEY uq_bet (bet_id),
    KEY ix_paid (paid_at)
) ENGINE=InnoDB;

INSERT INTO payouts (bet_id, amount, paid_at)
SELECT bet_id, payout, settled_at
FROM bets
WHERE status = 'settled' AND payout > 0
ORDER BY settled_at, bet_id;

-- =============================================================================
-- test_accounts : the list QA maintains by hand.
-- One entry could not be matched to a customer, so its customer_id is NULL.
-- =============================================================================
CREATE TABLE test_accounts (
    username     VARCHAR(40) NOT NULL,
    customer_id  INT         NULL,
    added_by     VARCHAR(20) NOT NULL
) ENGINE=InnoDB;

INSERT INTO test_accounts (username, customer_id, added_by)
SELECT username, customer_id, 'qa' FROM customers WHERE is_test = 1;
INSERT INTO test_accounts VALUES ('qa_test_old', NULL, 'qa');

-- =============================================================================
-- tz_demo : one moment stored as DATETIME and as TIMESTAMP (session is UTC)
-- =============================================================================
CREATE TABLE tz_demo (
    label        VARCHAR(40) NOT NULL,
    as_datetime  DATETIME    NOT NULL,
    as_timestamp TIMESTAMP   NOT NULL
) ENGINE=InnoDB;

INSERT INTO tz_demo VALUES ('bet settled 23:30 UTC', '2026-10-19 23:30:00', '2026-10-19 23:30:00');

-- -----------------------------------------------------------------------------
-- cleanup + summary
-- -----------------------------------------------------------------------------
DROP TABLE _active, _seq, _digits;
ANALYZE TABLE customers, bets, bet_selections, payouts;

SELECT 'customers' AS tbl, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'bets',           COUNT(*) FROM bets
UNION ALL SELECT 'bet_selections', COUNT(*) FROM bet_selections
UNION ALL SELECT 'payouts',        COUNT(*) FROM payouts
UNION ALL SELECT 'test_accounts',  COUNT(*) FROM test_accounts;
