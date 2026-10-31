# SQL Did Exactly What You Asked. That's the Problem.

A talk about the moment a query runs perfectly and the number is still wrong.

Given at **MySQL User Group Macedonia**, 20 October 2026.

---

## The idea

The whole talk is one question:

> **How much revenue did we make yesterday?**

It looks like a ten-second job. We read it backwards, one word at a time, and
every word turns out to hide a decision that SQL cannot make for you.

| Word | The question I have to ask first | What MySQL does about it |
|---|---|---|
| **yesterday** | Whose yesterday is this? | session time zone, `CURRENT_DATE`, DATETIME vs TIMESTAMP |
| **make** | Made when? | `ON UPDATE CURRENT_TIMESTAMP`, late-arriving data |
| **we** | Who counts as "we"? | `NOT IN` with a single NULL |
| **revenue** | Which revenue? | NULL in arithmetic, `SUM` skipping NULL rows |
| **how much** | One number, or one per sport? | JOIN fan-out, a LEFT JOIN that quietly becomes an INNER JOIN |

Every wrong number in the talk gets a verdict: was the problem the **query**,
the **data**, or the **question**?

The short answer, every time: not one of these mistakes throws an error.

---

## What is in this repository

| File | |
|---|---|
| `SQL-Did-Exactly-What-You-Asked-full.pptx` | the full deck, 50 slides |
| `SQL-Did-Exactly-What-You-Asked-short.pptx` | the short version actually presented, 42 slides |
| `demo_database.sql` | builds the demo database from scratch, deterministically |
| `demo_queries.sql` | every query shown in the talk, in talk order |
| `verification_log.txt` | the real output of every query, as executed |
| `TECHNICAL_NOTES.md` | the evidence behind every claim, and the questions a DBA will ask |

---

## Reproducing the numbers

Everything was run on **MySQL 8.0.46** with the default `sql_mode`
(`ONLY_FULL_GROUP_BY`, `STRICT_TRANS_TABLES`, `NO_ZERO_IN_DATE`, `NO_ZERO_DATE`,
`ERROR_FOR_DIVISION_BY_ZERO`, `NO_ENGINE_SUBSTITUTION`).

**1. Load the time zone tables.** `CONVERT_TZ` returns NULL silently without
them, so this step is not optional:

```bash
mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -u root mysql
```

**2. Build the demo database:**

```bash
mysql -u root < demo_database.sql
```

**3. Run the queries:**

```bash
mysql -u root -t --force bi_demo < demo_queries.sql
```

Or open `demo_queries.sql` in Workbench and run it statement by statement — it
is written to be read in talk order. A few statements are marked
`-- ERROR expected`; those fail on purpose.

### Why the numbers are identical on every machine

The data is generated, not random. `demo_database.sql` uses a fixed seed
(`rev-54`) and `CRC32`-based derivation, so an import on your laptop produces
exactly the rows and exactly the totals you see on the slides:
10,000 customers, 100,000 bets, 125,766 bet legs, 42,231 payouts.

The clock is frozen too. In a UTC session:

```sql
SET time_zone = '+00:00';
SET timestamp = UNIX_TIMESTAMP('2026-10-20 16:00:00');
```

That is Tuesday 20 October 2026, 18:00 in Skopje — the moment the talk started.
So "yesterday" is always Monday 19 October.

### The reference number

One definition is treated as correct throughout, the one the fictional finance
team agreed on:

- revenue = `stake - payout` (GGR)
- only `status = 'settled'` bets
- by `settled_at`, not when the bet was placed
- the Skopje calendar day: `2026-10-18 22:00:00` ≤ `settled_at` < `2026-10-19 22:00:00` UTC
- real customers only (`is_test = 0`)

Result: **8,669.94**.

Every case in the talk keeps four of those five words exactly as defined and
changes only one, so the numbers stay comparable.

---

## About the data

The database is fictional. It simulates an online gaming operator, and nothing
in it is real: no real customers, no real bets, no real money. The distribution
is not realistic either — bets are spread evenly across the day, while real
traffic peaks in the evening. The mechanisms are real; the scale is not.

---

## What this talk deliberately does not claim

- That UTC, or `TIMESTAMP`, is always the right choice.
- That the numbers resemble a real operator.
- Anything specific to MySQL 8.4 or 9.x. The behaviours shown are either SQL
  standard or long-standing design, but `EXPLAIN` output may differ.
- Anything about milliseconds. The query plans are the evidence, not timings.

---

## Author

**Ana Daniloska** — BI & Data Analyst

[LinkedIn](https://www.linkedin.com/in/ana-daniloska-25642b61)

---

*Slides are in English. The talk was delivered in Macedonian.*
