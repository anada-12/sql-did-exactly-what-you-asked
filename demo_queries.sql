-- =============================================================================
-- demo_queries.sql  -  every query shown in the talk, in talk order
-- "SQL Did Exactly What You Asked. That's the Problem."
-- The question: "How much revenue did we make yesterday?", read backwards,
-- word by word: yesterday -> make -> we -> revenue -> how much.
--
-- Finance's definition (the right answer):
--   revenue   = stake - payout (GGR)       how much = one row per bet
--   make      = when the bet is settled    we       = real customers only
--   yesterday = Mon 19 Oct, 00:00-24:00 Skopje = 2026-10-18 22:00 .. 2026-10-19 22:00 UTC
-- Each case keeps the other words as Finance defines them and changes one.
--
-- Needs: bi_demo (demo_database.sql) + time zone tables loaded.
-- Run statement by statement in Workbench (Cmd+Return), or whole file:
--   mysql -u root -t --force bi_demo < demo_queries.sql
-- Statements marked "-- ERROR expected" fail on purpose.
-- =============================================================================
USE bi_demo;

-- -----------------------------------------------------------------------------
-- 0. Environment + frozen clock: Tue 20 Oct 2026, 18:00 Skopje = 16:00 UTC
-- -----------------------------------------------------------------------------
SELECT VERSION() AS version, @@sql_mode AS sql_mode,
       @@global.time_zone AS global_tz, @@session.time_zone AS session_tz;
SET time_zone = '+00:00';
SET timestamp = UNIX_TIMESTAMP('2026-10-20 16:00:00');
SELECT NOW(), UTC_TIMESTAMP(), CURRENT_DATE, SYSDATE() AS sysdate_not_frozen;

-- 0.1 The ten-second query (opening slide; result revealed at the end)
SELECT SUM(stake - payout) AS revenue
FROM bets
WHERE placed_at >= CURRENT_DATE - INTERVAL 1 DAY
  AND placed_at <  CURRENT_DATE;

-- 0.2 Finance's number
SELECT SUM(b.stake - b.payout) AS revenue
FROM bets b
JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00';

-- =============================================================================
-- WORD 1 - YESTERDAY
-- =============================================================================

-- Y1 The query everyone writes: Finance's definition, "yesterday" from CURRENT_DATE
SELECT SUM(b.stake - b.payout) AS revenue
FROM bets b
JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= CURRENT_DATE - INTERVAL 1 DAY
  AND b.settled_at <  CURRENT_DATE;

-- Y2 Same instant, four session time zones
SET time_zone = 'UTC';              SELECT @@session.time_zone AS tz, NOW(), CURRENT_DATE;
SET time_zone = 'Europe/Skopje';    SELECT @@session.time_zone AS tz, NOW(), CURRENT_DATE;
SET time_zone = 'Asia/Tbilisi';     SELECT @@session.time_zone AS tz, NOW(), CURRENT_DATE;
SET time_zone = 'America/New_York'; SELECT @@session.time_zone AS tz, NOW(), CURRENT_DATE;
SET time_zone = '+00:00';

-- Y3 Same data, same question, four answers
SELECT z.zone,
       CONVERT_TZ('2026-10-19 00:00:00', z.zone, 'UTC') AS starts_utc,
       COUNT(*)                   AS bets,
       SUM(b.stake - b.payout)    AS revenue
FROM (SELECT 'UTC' AS zone UNION ALL SELECT 'Europe/Skopje'
      UNION ALL SELECT 'Asia/Tbilisi' UNION ALL SELECT 'America/New_York') z
JOIN bets b
  ON b.settled_at >= CONVERT_TZ('2026-10-19 00:00:00', z.zone, 'UTC')
 AND b.settled_at <  CONVERT_TZ('2026-10-20 00:00:00', z.zone, 'UTC')
JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
GROUP BY z.zone
ORDER BY starts_utc;

-- Y3b The bets that switch days between the UTC day and the Skopje day
--     "Tuesday" in Skopje but "Monday" in UTC ...
SELECT COUNT(*) AS bets, SUM(b.stake - b.payout) AS revenue
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= '2026-10-19 22:00:00' AND b.settled_at < '2026-10-20 00:00:00';
--     ... and "Monday" in Skopje but "Sunday" in UTC
SELECT COUNT(*) AS bets, SUM(b.stake - b.payout) AS revenue
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 00:00:00';

-- Y4 Which 24 hours? Three business definitions of Monday 19 Oct in Skopje
SELECT 'calendar day   00:00-24:00' AS definition, COUNT(*) AS bets, SUM(b.stake - b.payout) AS revenue
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= CONVERT_TZ('2026-10-19 00:00:00', 'Europe/Skopje', 'UTC')
  AND b.settled_at <  CONVERT_TZ('2026-10-20 00:00:00', 'Europe/Skopje', 'UTC')
UNION ALL
SELECT 'gaming day     06:00-06:00', COUNT(*), SUM(b.stake - b.payout)
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= CONVERT_TZ('2026-10-19 06:00:00', 'Europe/Skopje', 'UTC')
  AND b.settled_at <  CONVERT_TZ('2026-10-20 06:00:00', 'Europe/Skopje', 'UTC')
UNION ALL
SELECT 'business hours 08:00-22:00', COUNT(*), SUM(b.stake - b.payout)
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= CONVERT_TZ('2026-10-19 08:00:00', 'Europe/Skopje', 'UTC')
  AND b.settled_at <  CONVERT_TZ('2026-10-19 22:00:00', 'Europe/Skopje', 'UTC');

-- Y4b Is a day even 24 hours? Length of a Skopje calendar day
SELECT d.day,
       TIMESTAMPDIFF(HOUR,
                     CONVERT_TZ(d.day, 'Europe/Skopje', 'UTC'),
                     CONVERT_TZ(d.day + INTERVAL 1 DAY, 'Europe/Skopje', 'UTC')) AS hours
FROM (SELECT DATE '2026-03-29' AS day UNION ALL SELECT DATE '2026-10-19'
      UNION ALL SELECT DATE '2026-10-25') d;

-- Y5 Yesterday disappeared: the nightly job, 00:30 in Skopje, session time zone UTC
SET time_zone = '+00:00';
SET timestamp = UNIX_TIMESTAMP('2026-10-19 22:30:00');
SELECT NOW() AS now_utc, CURRENT_DATE - INTERVAL 1 DAY AS yesterday;
-- 00:30 in Skopje = 22:30 UTC, still Monday the 19th
SELECT SUM(b.stake - b.payout) AS revenue
FROM bets b
JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND DATE(b.settled_at) = CURRENT_DATE - INTERVAL 1 DAY;

-- Y6 "Set the session to Skopje": CURRENT_DATE is right now ...
SET time_zone = 'Europe/Skopje';
SELECT NOW() AS now_skopje, CURRENT_DATE - INTERVAL 1 DAY AS yesterday;
-- ... but DATETIME is never converted. TIMESTAMP is.
SELECT label, as_datetime, as_timestamp,
       DATE(as_datetime) AS day_from_datetime, DATE(as_timestamp) AS day_from_timestamp
FROM tz_demo;
SET time_zone = '+00:00';
SELECT label, as_datetime, as_timestamp FROM tz_demo;

-- Y7 What works: business-day boundaries converted to UTC, compared with >= and <
SELECT SUM(b.stake - b.payout) AS revenue
FROM bets b
JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= CONVERT_TZ('2026-10-19 00:00:00', 'Europe/Skopje', 'UTC')
  AND b.settled_at <  CONVERT_TZ('2026-10-20 00:00:00', 'Europe/Skopje', 'UTC');
EXPLAIN
SELECT SUM(b.stake - b.payout) AS revenue
FROM bets b
JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= CONVERT_TZ('2026-10-19 00:00:00', 'Europe/Skopje', 'UTC')
  AND b.settled_at <  CONVERT_TZ('2026-10-20 00:00:00', 'Europe/Skopje', 'UTC');

-- Y8 Backup: DATE(column) and the index
EXPLAIN SELECT COUNT(*) FROM bets WHERE DATE(settled_at) = '2026-10-19';
EXPLAIN SELECT COUNT(*) FROM bets WHERE settled_at >= '2026-10-19' AND settled_at < '2026-10-20';

SET time_zone = '+00:00';
SET timestamp = UNIX_TIMESTAMP('2026-10-20 16:00:00');

-- =============================================================================
-- WORD 2 - MAKE  (when is revenue "made"?)
-- =============================================================================

-- M1 Same bets, same day, three timestamps
SELECT 'placed_at' AS by_timestamp, COUNT(*) AS bets, SUM(b.stake - b.payout) AS revenue
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.placed_at >= '2026-10-18 22:00:00' AND b.placed_at < '2026-10-19 22:00:00'
UNION ALL
SELECT 'settled_at', COUNT(*), SUM(b.stake - b.payout)
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
UNION ALL
SELECT 'updated_at', COUNT(*), SUM(b.stake - b.payout)
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.updated_at >= '2026-10-18 22:00:00' AND b.updated_at < '2026-10-19 22:00:00';

-- M1b One bet, two days: placed on Sunday, settled on Monday (Skopje time)
SELECT b.bet_id, b.stake, b.payout,
       CONVERT_TZ(b.placed_at,  'UTC', 'Europe/Skopje') AS placed_skopje,
       CONVERT_TZ(b.settled_at, 'UTC', 'Europe/Skopje') AS settled_skopje
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0 AND b.bet_type = 'single' AND b.payout = 0
  AND b.placed_at  >= '2026-10-17 22:00:00' AND b.placed_at  < '2026-10-18 22:00:00'
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
ORDER BY b.stake DESC, b.bet_id LIMIT 1;

-- M1c The bets that differ between the two views
SELECT 'placed earlier, settled Monday' AS bets_that, COUNT(*) AS bets, SUM(b.stake - b.payout) AS revenue
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.placed_at  <  '2026-10-18 22:00:00'
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
UNION ALL
SELECT 'placed Monday, settled later', COUNT(*), SUM(b.stake - b.payout)
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.placed_at  >= '2026-10-18 22:00:00' AND b.placed_at < '2026-10-19 22:00:00'
  AND b.settled_at >= '2026-10-19 22:00:00'
UNION ALL
SELECT 'placed and settled Monday', COUNT(*), SUM(b.stake - b.payout)
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.placed_at  >= '2026-10-18 22:00:00' AND b.placed_at  < '2026-10-19 22:00:00'
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00';

SHOW CREATE TABLE bets;

-- M2 Today at 18:00 marketing tags last week's big winners for a campaign
START TRANSACTION;
UPDATE bets SET promo_tag = 'big-win-oct'
WHERE payout >= 125 AND settled_at >= '2026-10-12';
SELECT ROW_COUNT() AS rows_tagged;

SELECT bet_id, payout, settled_at, updated_at
FROM bets WHERE promo_tag = 'big-win-oct'
  AND settled_at >= '2026-10-18 22:00:00' AND settled_at < '2026-10-19 22:00:00'
ORDER BY bet_id LIMIT 3;

-- "yesterday's revenue" by updated_at, after marketing's UPDATE
SELECT COUNT(*) AS bets, SUM(b.stake - b.payout) AS revenue
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.updated_at >= '2026-10-18 22:00:00' AND b.updated_at < '2026-10-19 22:00:00';

-- M2b Monday's bets that marketing tagged (they now "belong" to Tuesday by updated_at)
SELECT COUNT(*) AS monday_bets_tagged, SUM(b.stake - b.payout) AS their_revenue
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0 AND b.promo_tag = 'big-win-oct'
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00';

-- ...and by settled_at, unchanged
SELECT COUNT(*) AS bets, SUM(b.stake - b.payout) AS revenue
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00';

-- Backup: an UPDATE that changes nothing does not bump updated_at
UPDATE bets SET promo_tag = promo_tag WHERE bet_id = 1;
SELECT bet_id, updated_at FROM bets WHERE bet_id = 1;
ROLLBACK;

-- M3 Late data: what the report run at 01:00 Skopje (23:00 UTC) could see
SELECT SUM(b.stake - b.payout) AS revenue_visible_at_0100
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
  AND b.synced_at <= '2026-10-19 23:00:00';

SELECT COUNT(*) AS bets_arrived_late, SUM(b.stake - b.payout) AS their_revenue,
       MIN(b.synced_at) AS first_arrival, MAX(b.synced_at) AS last_arrival
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
  AND b.synced_at > '2026-10-19 23:00:00';

-- =============================================================================
-- WORD 3 - WE  (who is "we"?)
-- =============================================================================

-- W1 Who is in the number?
SELECT 'all accounts' AS who, COUNT(*) AS bets, SUM(b.stake - b.payout) AS revenue
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled'
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
UNION ALL
SELECT 'QA test accounts', COUNT(*), SUM(b.stake - b.payout)
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 1
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
UNION ALL
SELECT 'real customers', COUNT(*), SUM(b.stake - b.payout)
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
UNION ALL
SELECT '  of which MK', COUNT(*), SUM(b.stake - b.payout)
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0 AND c.country = 'MK'
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00';

-- W2 "Exclude test users with QA's list"
SELECT SUM(b.stake - b.payout) AS revenue
FROM bets b
WHERE b.status = 'settled'
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
  AND b.customer_id NOT IN (SELECT customer_id FROM test_accounts);

SELECT * FROM test_accounts WHERE customer_id IS NULL;
SELECT 5 NOT IN (1, 2) AS no_null, 5 NOT IN (1, 2, NULL) AS with_null, 1 IN (1, 2, NULL) AS in_with_null;

-- W3 NOT EXISTS
SELECT SUM(b.stake - b.payout) AS revenue
FROM bets b
WHERE b.status = 'settled'
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
  AND NOT EXISTS (SELECT 1 FROM test_accounts t WHERE t.customer_id = b.customer_id);

EXPLAIN SELECT SUM(b.stake - b.payout) FROM bets b
WHERE b.status = 'settled'
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
  AND b.customer_id NOT IN (SELECT customer_id FROM test_accounts);
SHOW WARNINGS;

-- =============================================================================
-- WORD 4 - REVENUE  (which revenue?)
-- =============================================================================

-- R1 One day, three "revenues"
SELECT SUM(b.stake)                                        AS turnover,
       SUM(b.stake - b.payout)                             AS ggr,
       SUM(b.stake - b.payout) - COALESCE(SUM(b.bonus_cost), 0) AS ngr
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00';

-- R2 Which bets count? Bets placed on Monday (Skopje), by status
SELECT b.status, COUNT(*) AS bets, SUM(b.stake) AS stakes, SUM(b.stake - b.payout) AS stake_minus_payout
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE c.is_test = 0
  AND b.placed_at >= '2026-10-18 22:00:00' AND b.placed_at < '2026-10-19 22:00:00'
GROUP BY b.status
ORDER BY bets DESC;

-- R3 NGR, the obvious way
SELECT SUM(b.stake - b.payout - b.bonus_cost) AS ngr,
       COUNT(*) AS bets, COUNT(b.bonus_cost) AS bets_with_bonus
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00';

-- R3 fix
SELECT SUM(b.stake - b.payout - COALESCE(b.bonus_cost, 0)) AS ngr
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00';

SELECT 10 - 2 - NULL AS arithmetic_with_null;

-- R3b What SUM actually sees: three real Monday bets
(SELECT 'normal bet, lost' AS example, b.bet_id, b.stake, b.payout, b.bonus_cost,
        b.stake - b.payout - b.bonus_cost AS row_value
 FROM bets b JOIN customers c ON c.customer_id = b.customer_id
 WHERE b.status = 'settled' AND c.is_test = 0 AND b.bonus_cost IS NULL AND b.payout = 0
   AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
 ORDER BY b.bet_id LIMIT 1)
UNION ALL
(SELECT 'normal bet, won', b.bet_id, b.stake, b.payout, b.bonus_cost, b.stake - b.payout - b.bonus_cost
 FROM bets b JOIN customers c ON c.customer_id = b.customer_id
 WHERE b.status = 'settled' AND c.is_test = 0 AND b.bonus_cost IS NULL AND b.payout > 0
   AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
 ORDER BY b.bet_id LIMIT 1)
UNION ALL
(SELECT 'free bet, won', b.bet_id, b.stake, b.payout, b.bonus_cost, b.stake - b.payout - b.bonus_cost
 FROM bets b JOIN customers c ON c.customer_id = b.customer_id
 WHERE b.status = 'settled' AND c.is_test = 0 AND b.bonus_cost IS NOT NULL AND b.payout > 0
   AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
 ORDER BY b.bet_id LIMIT 1);

-- R3c The only rows SUM added up: the free bets
SELECT COUNT(*) AS free_bets, SUM(b.stake - b.bonus_cost) AS stake_minus_bonus,
       SUM(b.payout) AS their_payouts
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0 AND b.bonus_cost IS NOT NULL
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00';

-- =============================================================================
-- WORD 5 - HOW MUCH  (adding it up)
-- =============================================================================

-- H1 "How much did we make on football yesterday?"
SELECT SUM(b.stake - b.payout) AS football_revenue
FROM bets b
JOIN customers c       ON c.customer_id = b.customer_id
JOIN bet_selections s  ON s.bet_id = b.bet_id
WHERE b.status = 'settled' AND c.is_test = 0 AND s.sport = 'football'
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00';

SELECT SUM(b.stake - b.payout) AS football_revenue
FROM bets b
JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
  AND EXISTS (SELECT 1 FROM bet_selections s WHERE s.bet_id = b.bet_id AND s.sport = 'football');

-- H1b One treble, three football legs
SELECT b.bet_id, s.leg_no, s.sport, b.stake, b.payout
FROM bets b JOIN bet_selections s ON s.bet_id = b.bet_id
WHERE b.bet_id = (
    SELECT b2.bet_id
    FROM bets b2 JOIN bet_selections s2 ON s2.bet_id = b2.bet_id
    JOIN customers c2 ON c2.customer_id = b2.customer_id
    WHERE b2.bet_type = 'treble' AND b2.status = 'settled' AND c2.is_test = 0 AND b2.payout = 0
      AND b2.settled_at >= '2026-10-18 22:00:00' AND b2.settled_at < '2026-10-19 22:00:00'
    GROUP BY b2.bet_id
    HAVING SUM(s2.sport = 'football') = 3
    ORDER BY MAX(b2.stake) DESC, b2.bet_id LIMIT 1)
ORDER BY s.leg_no;

-- H1c Each sport counted once per bet: do the sports add up to the day?
SELECT sp.sport, SUM(b.stake - b.payout) AS revenue
FROM (SELECT 'football' AS sport UNION ALL SELECT 'tennis' UNION ALL SELECT 'basketball') sp
JOIN bets b ON EXISTS (SELECT 1 FROM bet_selections s WHERE s.bet_id = b.bet_id AND s.sport = sp.sport)
JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
GROUP BY sp.sport WITH ROLLUP;

SELECT COUNT(*) AS multi_sport_bets FROM (
  SELECT b.bet_id
  FROM bets b JOIN customers c ON c.customer_id = b.customer_id
  JOIN bet_selections s ON s.bet_id = b.bet_id
  WHERE b.status = 'settled' AND c.is_test = 0
    AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
  GROUP BY b.bet_id HAVING COUNT(DISTINCT s.sport) > 1) x;

-- H2 "Stakes minus payouts, from the payments table, for yesterday"
SELECT SUM(b.stake) - SUM(p.amount) AS revenue
FROM bets b
JOIN customers c     ON c.customer_id = b.customer_id
LEFT JOIN payouts p  ON p.bet_id = b.bet_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
  AND p.paid_at    >= '2026-10-18 22:00:00' AND p.paid_at    < '2026-10-19 22:00:00';

EXPLAIN
SELECT SUM(b.stake) - SUM(p.amount) AS revenue
FROM bets b
JOIN customers c     ON c.customer_id = b.customer_id
LEFT JOIN payouts p  ON p.bet_id = b.bet_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
  AND p.paid_at    >= '2026-10-18 22:00:00' AND p.paid_at    < '2026-10-19 22:00:00';
SHOW WARNINGS;

SELECT COUNT(*) AS settled_bets, SUM(b.payout = 0) AS losing_bets, SUM(b.payout > 0) AS winning_bets
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00';

-- H3 Fix: the condition on the optional table goes into ON
SELECT SUM(b.stake) - SUM(p.amount) AS revenue
FROM bets b
JOIN customers c     ON c.customer_id = b.customer_id
LEFT JOIN payouts p  ON p.bet_id = b.bet_id
                    AND p.paid_at >= '2026-10-18 22:00:00' AND p.paid_at < '2026-10-19 22:00:00'
WHERE b.status = 'settled' AND c.is_test = 0
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00';

-- =============================================================================
-- INVESTIGATION - "Finance says yesterday's revenue report is too high"
-- =============================================================================
SET time_zone = '+00:00';
SET timestamp = UNIX_TIMESTAMP('2026-10-20 16:00:00');

-- I.0 The report
SELECT IF(GROUPING(s.sport), 'TOTAL', s.sport) AS sport,
       SUM(b.stake - b.payout) AS revenue
FROM bets b
JOIN bet_selections s ON s.bet_id = b.bet_id
WHERE DATE(b.placed_at) = CURRENT_DATE - INTERVAL 1 DAY
  AND b.status <> 'cancelled'
GROUP BY s.sport WITH ROLLUP;

-- I.1 The waterfall: one word at a time
SELECT 'reported' AS step, SUM(b.stake - b.payout) AS revenue
FROM bets b JOIN bet_selections s ON s.bet_id = b.bet_id
WHERE b.placed_at >= '2026-10-19' AND b.placed_at < '2026-10-20' AND b.status <> 'cancelled'
UNION ALL
SELECT '1 how much: one row per bet', SUM(b.stake - b.payout)
FROM bets b
WHERE b.placed_at >= '2026-10-19' AND b.placed_at < '2026-10-20' AND b.status <> 'cancelled'
UNION ALL
SELECT '2 revenue: settled bets only', SUM(b.stake - b.payout)
FROM bets b
WHERE b.placed_at >= '2026-10-19' AND b.placed_at < '2026-10-20' AND b.status = 'settled'
UNION ALL
SELECT '3 make: by settlement time', SUM(b.stake - b.payout)
FROM bets b
WHERE b.settled_at >= '2026-10-19' AND b.settled_at < '2026-10-20' AND b.status = 'settled'
UNION ALL
SELECT '4 yesterday: Skopje day', SUM(b.stake - b.payout)
FROM bets b
WHERE b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
  AND b.status = 'settled'
UNION ALL
SELECT '5 we: real customers', SUM(b.stake - b.payout)
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00'
  AND b.status = 'settled' AND c.is_test = 0;

-- I.2 What was hiding behind the steps
SELECT status, COUNT(*) AS bets, SUM(stake) AS stakes, SUM(stake - payout) AS stake_minus_payout
FROM bets
WHERE placed_at >= '2026-10-19' AND placed_at < '2026-10-20'
GROUP BY status ORDER BY bets DESC;

SELECT bet_type, COUNT(*) AS bets
FROM bets
WHERE placed_at >= '2026-10-19' AND placed_at < '2026-10-20' AND status <> 'cancelled'
GROUP BY bet_type ORDER BY bets DESC;

SELECT COUNT(*) AS test_bets, SUM(b.stake - b.payout) AS test_revenue
FROM bets b JOIN customers c ON c.customer_id = b.customer_id
WHERE c.is_test = 1 AND b.status = 'settled'
  AND b.settled_at >= '2026-10-18 22:00:00' AND b.settled_at < '2026-10-19 22:00:00';

-- =============================================================================
-- Audience questions we prepared for
-- =============================================================================

-- Q: ONLY_FULL_GROUP_BY is on; grouping by the PK makes username legal ...
SELECT c.customer_id, c.username, COUNT(*) AS bets FROM customers c
JOIN bets b ON b.customer_id = c.customer_id
WHERE c.customer_id = 1 GROUP BY c.customer_id;
-- ... a column that is not functionally dependent fails:
SELECT c.country, c.username, COUNT(*) FROM customers c GROUP BY c.country;  -- ERROR expected (1055)

-- Q: NOT IN with an empty list keeps everything
SELECT COUNT(*) AS bets FROM bets WHERE customer_id NOT IN (SELECT customer_id FROM test_accounts WHERE 1 = 0);

-- Q: COUNT variants with NULLs; SUM of no rows
SELECT COUNT(*) AS cnt_star, COUNT(x) AS cnt_col, COUNT(DISTINCT x) AS cnt_distinct
FROM (SELECT NULL AS x UNION ALL SELECT 1 UNION ALL SELECT 1) t;
SELECT SUM(stake) AS sum_no_rows, COALESCE(SUM(stake), 0) AS coalesced FROM bets WHERE 1 = 0;

-- Q: No time zone tables / unknown zone name -> NULL, silently
SELECT CONVERT_TZ('2026-10-19 00:00:00', 'Mars/Olympus', 'UTC') AS unknown_zone,
       CONVERT_TZ('2026-10-19 00:00:00', '+02:00', '+00:00')      AS numeric_offset;

-- Q: Why not '+02:00'? DST ends Sunday 25 Oct 2026.
SELECT CONVERT_TZ('2026-10-26 00:00:00', 'Europe/Skopje', 'UTC') AS named_next_monday,
       CONVERT_TZ('2026-10-26 00:00:00', '+02:00', '+00:00')      AS fixed_offset_next_monday;
SELECT CONVERT_TZ('2026-10-19 00:00:00', 'Europe/Skopje', 'America/New_York') AS skopje_midnight_in_ny_this_week,
       CONVERT_TZ('2026-10-26 00:00:00', 'Europe/Skopje', 'America/New_York') AS skopje_midnight_in_ny_next_week;

-- Q: Literals compared with TIMESTAMP are read in the session time zone; DATETIME ones are not
SET time_zone = 'Europe/Skopje';
SELECT SUM(as_timestamp >= '2026-10-20 00:00:00') AS ts_is_oct20_skopje,
       SUM(as_datetime  >= '2026-10-20 00:00:00') AS dt_is_oct20_skopje
FROM tz_demo;
SET time_zone = '+00:00';

-- Q: The session time zone doesn't change what DATETIME returns
SET time_zone = 'Asia/Tbilisi';
SELECT MIN(settled_at), MAX(settled_at) FROM bets;
SET time_zone = '+00:00';
SELECT MIN(settled_at), MAX(settled_at) FROM bets;

-- Q: A functional index makes DATE(col) indexable (8.0.13+); the time zone problem stays
ALTER TABLE bets ADD INDEX ix_settled_day ((DATE(settled_at)));
EXPLAIN SELECT COUNT(*) FROM bets WHERE DATE(settled_at) = '2026-10-19';
ALTER TABLE bets DROP INDEX ix_settled_day;

-- Q: Setting updated_at explicitly in an UPDATE wins over ON UPDATE
START TRANSACTION;
UPDATE bets SET promo_tag = 'x', updated_at = '2026-10-19 12:00:00' WHERE bet_id = 1;
SELECT bet_id, promo_tag, updated_at FROM bets WHERE bet_id = 1;
ROLLBACK;

-- Q: What time zone does a new connection get on this server?
SELECT @@global.time_zone, @@system_time_zone;

SET timestamp = DEFAULT;
