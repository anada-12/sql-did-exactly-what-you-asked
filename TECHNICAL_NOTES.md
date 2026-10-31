# Technical Defense Sheet

For every claim in the talk, this sheet gives what MySQL does, the evidence, and
the questions a DBA is likely to ask. Everything was executed on MySQL 8.0.46
(`verification_log.txt`) unless it's marked **[manual]**, which means it comes
from the MySQL 8.0 Reference Manual and was not executed here.

**Environment:**
- MySQL 8.0.46, default `sql_mode` (ONLY_FULL_GROUP_BY, STRICT_TRANS_TABLES,
  NO_ZERO_IN_DATE, NO_ZERO_DATE, ERROR_FOR_DIVISION_BY_ZERO,
  NO_ENGINE_SUBSTITUTION)
- time zone tables loaded
- demo session in UTC, clock frozen at 2026-10-20 16:00 UTC (18:00 Skopje)

Every talk query passes ONLY_FULL_GROUP_BY. The only error in the log is the
one we trigger on purpose (1055).

**Finance's definition, used as the reference in every case:**
- stake − payout
- `status = 'settled'`
- by `settled_at`
- Skopje calendar day = `2026-10-18 22:00:00` ≤ t < `2026-10-19 22:00:00` UTC
- `is_test = 0`

Result: **8,669.94**.

---

## Frozen clock

`SET timestamp = …` fixes `NOW()`, `CURRENT_DATE` and `UTC_TIMESTAMP()` for the
session. Evidence: all three show 2026-10-20 16:00, while `SYSDATE()` still shows
the real time. It also drives `ON UPDATE CURRENT_TIMESTAMP`: the tagged rows get
`updated_at = 2026-10-20 16:00:00`.

- `UNIX_TIMESTAMP('…')` reads the string in the session time zone, so the session
  is set to UTC first.
- **Q: Is that cheating?** No. It's a documented session variable (replication
  uses it). `NOW()` returns the statement start time, which this variable controls.

## yesterday

| Claim | Evidence |
|---|---|
| `CURRENT_DATE`/`NOW()` follow the session time zone | Same instant: 16:00 UTC, 18:00 Skopje, 20:00 Tbilisi, 12:00 New York. All show 2026-10-20. |
| Same question, four answers | Tbilisi 8,865.94 · Skopje 8,669.94 · UTC 8,924.91 · New York 8,782.58 |
| Bets switch days (Y3b) | 568 bets (−363.42) settled Sun 22:00–24:00 UTC are Monday in Skopje only. 558 bets (−108.45) settled Mon 22:00–24:00 UTC are Monday in UTC only. 8,924.91 − (−108.45) + (−363.42) = 8,669.94 exactly. Both slices are negative: customers won more than they staked in those evening hours. |
| Which 24 hours | calendar 8,669.94 · gaming day 06–06 8,782.58 · business hours 08–22 3,625.68 (42%) |
| A day isn't 24 h | Skopje: 29 Mar = 23 h, 19 Oct = 24 h, 25 Oct = 25 h (`TIMESTAMPDIFF` on `CONVERT_TZ` of consecutive midnights) |
| Nightly job at 00:30 Skopje on a UTC session | `CURRENT_DATE - INTERVAL 1 DAY` = 2026-10-18 → 8,210.50 |
| Skopje session doesn't fix DATETIME | tz_demo: DATETIME 2026-10-19 23:30 stays; TIMESTAMP reads 2026-10-20 01:30. In a Skopje session `as_timestamp >= '2026-10-20'` is true, `as_datetime >= …` is false. Session Tbilisi vs UTC: `MIN/MAX(settled_at)` identical. |
| The fix | `CONVERT_TZ` on the boundaries → 8,669.94. EXPLAIN: `b` range on `ix_settled`, `c` eq_ref on PRIMARY. |

**Mechanism:**
- TIMESTAMP is stored in UTC and converted to and from the session time zone.
  DATETIME is stored as-is.
- Literals compared with a TIMESTAMP are read in the session time zone.
- `CONVERT_TZ` on constants keeps the predicate sargable.

**Likely questions:**
- **Honest note on the totals:** the four zones differ by a few percent. The
  stronger point is the individual bets that change day.
- **Gaming day = New York numbers?** Yes, both are 8,782.58. 06:00 Skopje and
  00:00 New York are both 04:00 UTC, so it's the same UTC window. A "day" is
  just a pair of UTC boundaries.
- **The generated bets are spread evenly over 24 h.** Real traffic peaks in
  the evening, so the 42% business-hours share is a demo number.
- **`DATE(settled_at) = …`** gives type=index, rows ≈ 100,000 (estimate
  99,501). The range version gives type=range, ≈ 6,665. `rows` is an estimate
  and changes between runs; use `EXPLAIN ANALYZE` for actual counts.
- **Functional index?** Since 8.0.13, `INDEX ((DATE(settled_at)))` gives
  type=ref. But it indexes the UTC date, so the time zone problem stays.
- **Why not `'+02:00'`?** DST ends Sunday 25 Oct 2026. Next Monday, Skopje
  midnight is 23:00 UTC, but `'+02:00'` still says 22:00. Europe and the US are
  out of step for a week: Skopje midnight is 18:00 in New York this week and
  19:00 next week.
- **No time zone tables?** `CONVERT_TZ` with an unknown zone returns NULL,
  silently (verified with 'Mars/Olympus').
- **Why not TIMESTAMP everywhere?** Its reads depend on the client session.
  **[manual]** Its range ends 2038-01-19 03:14:07 UTC. Storing UTC in DATETIME
  is a common, valid choice; the rule is to know which one you have.
- **Default for new connections:** `@@global.time_zone` = SYSTEM (CEST on this
  Mac). Cloud servers are often UTC.

## make

| Claim | Evidence |
|---|---|
| Three timestamps, three answers | by placed_at 6,616 bets / 8,958.53 · settled_at 6,653 / 8,669.94 · updated_at 6,653 / 8,669.94 |
| One bet, two days (M1b) | bet 792, stake 50.00, lost: placed 2026-10-18 23:53:19, settled 2026-10-19 01:42:33 (Skopje) |
| Where the two views differ (M1c) | placed and settled Monday 6,021 / 8,306.82 · placed earlier, settled Monday 632 / 363.12 · placed Monday, settled later 595 / 651.71. 8,306.82 + 363.12 = 8,669.94 and 8,306.82 + 651.71 = 8,958.53. |
| Tagged Monday bets (M2b) | 47 bets, revenue −3,624.50. 8,669.94 − (−3,624.50) = 12,294.44. |
| updated_at is maintained by MySQL | `SHOW CREATE TABLE`: `` `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP `` |
| An unrelated UPDATE moves revenue | `UPDATE … SET promo_tag = 'big-win-oct' WHERE payout >= 125 AND settled_at >= '2026-10-12'` → 348 rows. E.g. bet 2915, settled 2026-10-18 23:28:31, updated_at becomes 2026-10-20 16:00:00. Yesterday by updated_at: 6,606 bets / **12,294.44**. By settled_at: unchanged, 8,669.94. |
| Late data | Visible at 01:00 Skopje (`synced_at <= 2026-10-19 23:00 UTC`): 8,567.59. 70 bets (revenue 102.35) arrived 23:32:47–00:58:55 UTC. |

**Mechanism:** `ON UPDATE CURRENT_TIMESTAMP` sets the column whenever an UPDATE
changes any other column in the row.

**Likely questions:**
- **Does a no-op UPDATE bump it?** No. `SET promo_tag = promo_tag` → 0 rows
  affected, `updated_at` unchanged (verified).
- **Can you prevent it?** Assign the column explicitly in the UPDATE: `SET
  promo_tag = 'x', updated_at = '2026-10-19 12:00:00'` keeps the given value
  (verified).
- **DATETIME too?** **[manual]** Yes, since 5.6.5 DATETIME supports DEFAULT /
  ON UPDATE CURRENT_TIMESTAMP. For DATETIME the value is in the *session* time
  zone, which is another trap.
- **The demo runs inside `START TRANSACTION … ROLLBACK`,** so the database is
  unchanged afterwards.

## we

| Claim | Evidence |
|---|---|
| Who is in the number | all accounts 6,662 / 9,119.94 · QA 9 / 450.00 · real 6,653 / 8,669.94 · MK 2,685 / 3,758.85 |
| NOT IN with QA's list → NULL | `… NOT IN (SELECT customer_id FROM test_accounts)` → SUM = NULL. The list has `qa_test_old` with customer_id NULL. |
| Three-valued logic | `5 NOT IN (1, 2)` = 1 · `5 NOT IN (1, 2, NULL)` = NULL · `1 IN (1, 2, NULL)` = 1 |
| NOT EXISTS | 8,669.94 |

**Mechanism:**
- `x NOT IN (a, b, NULL)` means `x <> a AND x <> b AND x <> NULL`, so it is
  never TRUE.
- Every row is filtered out, and SUM over zero rows is NULL, not 0 (verified).
- The optimizer note shows `<in_optimizer>(… in (<materialize> …))`: NOT IN is
  executed as an IN over a materialized subquery, negated.
- NOT IN over an *empty* list keeps all 100,000 bets.

**Q: Is this MySQL-specific?** No. It's standard SQL, and every database
behaves this way.

## revenue

| Claim | Evidence |
|---|---|
| Three revenues | turnover 127,391.00 · GGR 8,669.94 · NGR 2,647.94 |
| Statuses | placed Monday (Skopje), real customers: settled 6,616 · cancelled 196 (3,686.00) · open 32 (862.00) · rolled_back 15 (194.00). Their payout is 0, so stake − payout = the full stake. |
| NULL in arithmetic | `SUM(stake - payout - bonus_cost)` → −4,977.92 over 6,653 bets, of which 297 have a bonus. `10 - 2 - NULL` = NULL. `COALESCE(bonus_cost, 0)` → 2,647.94. |
| What SUM saw (R3b, R3c) | bet 13 (2.00, 0.00, NULL) → NULL · bet 61 (20.00, 31.40, NULL) → NULL · bet 1070 free bet (50.00, 74.50, 50.00) → −74.50. The 297 free bets: SUM(stake − bonus_cost) = 0.00, SUM(payout) = 4,977.92. |
| Which bets count | 3,686.00 + 862.00 + 194.00 = 4,742.00 (cancelled + open + rolled back, placed Monday, real customers) |

**Mechanism:** any arithmetic with NULL is NULL. SUM ignores NULL values, so
only the 297 bonus rows are summed, and for them stake − payout − stake is
negative.

**Likely questions:**
- **Is NGR really GGR − bonus?** It's simplified for the demo; real NGR also
  depends on taxes, fees and jurisdiction. That is exactly the point of
  "which revenue?".
- **Is NULL for "no bonus" bad design?** Not necessarily. It's a valid choice.
  The query has to handle it.

## how much

| Claim | Evidence |
|---|---|
| JOIN to matches multiplies | football via JOIN 6,195.36 vs EXISTS 5,796.82 (difference 398.54). Treble 8230: 3 football matches (legs), stake 5.00, payout 0, so 5.00 counted 3×. |
| Sports don't add up | EXISTS per sport: basketball 2,141.76 · football 5,796.82 · tennis 566.70 · sum 8,505.28 vs day 8,669.94. 824 bets are in more than one sport. |
| LEFT JOIN + WHERE on the right table | → −56,866.06. `SHOW WARNINGS` note 1003: `from bets b join customers c join payouts p where …`, a plain join. 6,653 settled bets: 3,711 losing (no payout row), 2,942 winning. |
| Fix: condition in ON | 8,669.94 |

**Mechanism:**
- The JOIN produces one row per leg. With `WHERE sport = 'football'`, a bet
  appears once per football leg.
- The sports don't add up because a multi-sport bet is counted in each of its
  sports, and its revenue can be positive or negative.
- The WHERE condition on `p.paid_at` is null-rejecting, so MySQL simplifies the
  outer join to an inner join. Losing bets have no payout row and disappear, so
  only winners remain (stake − payout < 0).

**Likely questions:**
- **Isn't the JOIN just wrong?** The JOIN is correct. The grain of the answer
  is "per bet", and the JOIN makes it "per leg".
- **Which sport owns a multi-sport bet?** There's no SQL answer. It's an
  allocation rule the business must define (first leg, split, or a "multi"
  bucket).
- **`SUM(DISTINCT …)`?** It removes repeated *values*, not repeated rows, so it
  would drop legitimately equal stakes. Don't use it.

## Investigation

The report: `JOIN bet_selections`, `DATE(b.placed_at) = CURRENT_DATE - INTERVAL
1 DAY` (UTC session), `status <> 'cancelled'`, all customers.
- basketball 1,749.28 · football 6,724.69 · tennis 1,310.84 · TOTAL 9,784.81
- Finance 8,669.94, so the report is +12.9%

| Step | Revenue | What it removes |
|---|---|---|
| Reported | 9,784.81 | |
| 1 how much | 9,574.95 | multi-leg bets counted per leg (901 doubles, 421 trebles that day) |
| 2 revenue | 8,502.95 | 35 open (853.00) + 16 rolled back (219.00) counted at full stake |
| 3 make | 9,274.91 | bets placed that day → bets settled that day |
| 4 yesterday | 9,119.94 | UTC day → Skopje day |
| 5 we | 8,669.94 | 9 QA bets, all lost (450.00) |

- **The order of the steps** changes the size of each step, not the end result.
- **Step 3 goes up.** Fixes don't all move in one direction. After step 2 the
  number is below Finance's.

## ONLY_FULL_GROUP_BY

- `SELECT c.customer_id, c.username, COUNT(*) … GROUP BY c.customer_id` works
  (player_0001, 10 bets). `username` is functionally dependent on the PK
  (**[manual]** detected since 5.7.5).
- `SELECT c.country, c.username, COUNT(*) … GROUP BY c.country` → ERROR 1055.

## What we deliberately do not claim

- That UTC or TIMESTAMP is always right.
- That the numbers resemble a real operator.
- Anything about 8.4 / 9.x specifically. The concepts are the same, but
  EXPLAIN output may differ.
- Timings. The plans are the evidence, not the milliseconds.
