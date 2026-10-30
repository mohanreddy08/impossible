# VIS — Daily Visit List Rules (Chandrapuri Block)

> Simplified for the TalentAP hackathon from public Government of India guidance. Not for clinical use.
> The vaccine ages, ANC windows and HBNC visit days in this document come from the other protocol documents (IMM, ANC, HBNC), which cite their sources. The counting conventions marked **[block rule]** (grace period, monthly follow-up, "this week", days-per-month) are operational rules agreed for Chandrapuri Block for this hackathon; they are not national numbers.

## VIS-1 How the daily visit list works

### VIS-1.1 Purpose
Every morning the ASHA/ANM makes a list of household members who need a visit or a service: who is due for what, and which visits come first. The list is made from the household register for one day ("today"). For this hackathon, today is **2026-10-26 (Monday)**. The register contains everything recorded up to the evening of 2026-10-25.

### VIS-1.2 Status of an item
Each item on the list has one status:
- **overdue** — the item was due and its allowed time has passed without it being done.
- **due_today** — the item is due now: its due date has arrived and it is still within its allowed time.
- **due_this_week** — the item will become due in the next 6 days (2026-10-27 to 2026-11-01). Plan it now.

Note that "overdue" depends on the item: ANC is overdue the day after its window closes (VIS-2.1), an HBNC visit the day after its visit day (VIS-4.1), and all other items more than 28 days after their due date (VIS-1.3).

Items that become due later than 6 days from today are **not** listed.

### VIS-1.3 Counting conventions [block rule]

| Parameter | Value |
|---|---|
| upcoming_horizon_days | 6 |
| grace_days | 28 |
| followup_interval_days | 30 |
| td2_gap_days | 28 |
| vaccine_list_age_to_days | 2554 |
| hbnc_age_to_days | 42 |
| muac_age_from_days | 184 |
| muac_age_to_days | 1824 |

- All ages and gaps are counted in **days**. Age in days = today minus date of birth.
- Calendar ages are converted to days so that an item is **never listed before** the child completes that age: 6 weeks = 42 days, 10 weeks = 70, 14 weeks = 98, 6 months = 184, 9 completed months = 276, 16 months = 490, 5 years = 1827. The "not after" ages in VIS-3.1 are the last age (in days) at which a dose may still be listed: 365 (1 year), 1825 (5 years) and 2554 (just under 7 years). Follow-up intervals use 30 days for one month.
- **grace_days**: a vaccine, Td dose, MUAC check or NCD follow-up is **overdue** when today is more than 28 days after its due date (four weekly session cycles missed). On day 28 after the due date it is still due_today. Every "becomes overdue 28 days after its due date" in this document means this.
- **followup_interval_days**: MUAC re-check and NCD (BP / sugar) follow-up are due 30 days after the last recorded check.
- Children are on the vaccine part of the list while their age is 0 to 2554 days (under 7 years, the upper age for DPT boosters).
- The list starts from what is recorded in the register. A **new** danger sign found during any visit is never left for the list: refer immediately (ESC-1.1).

### VIS-1.4 Messy register entries
The register is filled by hand. Vaccine codes may be written in different ways (for example `penta1`, `PENTA 1`, `Penta-1` all mean Penta-1). A blood-pressure reading of `0/0` or a blank cell means the reading was not recorded (a check date in its own column still counts as a check). A blank date means "not recorded". Duplicate vaccine entries count once (use the earliest date).

## VIS-2 Pregnant women

### VIS-2.1 ANC check-ups
ANC check-ups are numbered in the order they happen: the first recorded check-up is ANC-1, the second is ANC-2, and so on (see ANC-1.2 for the timing). The next check-up due is number (check-ups done + 1). It is due from the day the pregnancy reaches the start of its window, and it is **overdue** after the end of its window. Days are counted from the first day of the last menstrual period (LMP).

| Item | Opens (days since LMP) | Closes (days since LMP) |
|---|---|---|
| ANC-1 | 0 | 84 |
| ANC-2 | 98 | 182 |
| ANC-3 | 196 | 238 |
| ANC-4 | 252 | 280 |

(84 days = 12 weeks; 98 = 14 weeks; 182 = 26 weeks; 196 = 28 weeks; 238 = 34 weeks; 252 = 36 weeks; 280 days = 40 weeks = the expected date of delivery, EDD = LMP + 280 days.) After 4 check-ups no ANC item is listed. The whole open window counts as due_today. A woman still recorded as pregnant after her EDD keeps her next missing ANC check-up (whatever its number) as overdue — inform the ANM.

### VIS-2.2 Td in pregnancy
- If the woman is **booster-eligible** (`td_booster_eligible = Y`: two TT/Td doses in a pregnancy within the last 3 years, see IMM-4.1), she needs only **Td-BST**. Otherwise she needs **Td-1** and **Td-2**.
- Td-1 (or Td-BST) is due on the date of her first recorded ANC check-up. If she has no ANC check-up yet, Td is not listed separately (ANC-1 is listed instead).
- Td-2 is due 28 days after the date Td-1 was actually given (listed only once Td-1 is recorded).
- Each Td item becomes overdue 28 days after its due date (grace_days). Td items are listed while she is recorded as pregnant.

### VIS-2.3 High-risk pregnancy follow-up [block rule]
Every pregnant woman whose last recorded Hb is below 7 g/dL or whose last ANC BP is 140/90 or more was referred at that ANC check-up (ESC-2.3, ESC-2.5). She gets the item **HRP-followup** on every day's list, with status **due_today** (and therefore priority 1): visit her, confirm that the referral to the MO/FRU was completed, and check for danger signs.

## VIS-3 Children: vaccines

### VIS-3.1 Vaccine due rules
A dose is listed when: the child has not had it; the "previous dose needed" (if any) has been given; and the child is not past the "not after" age. Its due date is the later of (date of birth + due age) and (date of previous dose + minimum gap). It becomes overdue 28 days after its due date, or on the day the child reaches the "not after" age, whichever is earlier. Doses past the "not after" age are not listed — tell the ANM, who decides on catch-up. A dose whose due date (after adding the minimum gap) falls after its "not after" age is also not listed. In the table, "-" in the "not after" column means no limit other than the vaccine-list age (2554 days); "-" in the gap column means no minimum gap; "-" in the previous-dose column means none needed. The ages come from IMM-2.

| Item | Due from age (days) | Not after age (days) | Previous dose needed | Minimum gap after previous dose (days) |
|---|---|---|---|---|
| BCG | 0 | 365 | - | - |
| HepB-0 | 0 | 0 | - | - |
| OPV-0 | 0 | 15 | - | - |
| OPV-1 | 42 | 1825 | - | - |
| OPV-2 | 70 | 1825 | OPV-1 | 28 |
| OPV-3 | 98 | 1825 | OPV-2 | 28 |
| Penta-1 | 42 | 365 | - | - |
| Penta-2 | 70 | 365 | Penta-1 | 28 |
| Penta-3 | 98 | 365 | Penta-2 | 28 |
| RVV-1 | 42 | 365 | - | - |
| RVV-2 | 70 | 365 | RVV-1 | 28 |
| RVV-3 | 98 | 365 | RVV-2 | 28 |
| fIPV-1 | 42 | 365 | - | - |
| fIPV-2 | 98 | 365 | fIPV-1 | 56 |
| fIPV-3 | 276 | 729 | fIPV-2 | 56 |
| PCV-1 | 42 | 365 | - | - |
| PCV-2 | 98 | 729 | PCV-1 | 60 |
| PCV-B | 276 | 729 | PCV-2 | 60 |
| MR-1 | 276 | 1825 | - | - |
| MR-2 | 490 | 1825 | MR-1 | 28 |
| OPV-B | 490 | 1825 | OPV-3 | 180 |
| DPT-B1 | 490 | 2554 | Penta-3 | 180 |
| DPT-B2 | 1827 | 2554 | DPT-B1 | - |

"-" means no limit within this list (the child stays on the vaccine list until 2554 days of age). Upper ages follow IMM-2: Penta, RVV, fIPV-1/2 and PCV-1 only up to 1 year (365 days); PCV-2, PCV-B and fIPV-3 only before 2 years (729 days; fIPV-3 catch-up is at 16–23 months, and it exists only since 1 January 2023, so every child young enough to be listed for it is eligible); MR and OPV up to 5 years; DPT boosters up to 7 years. A child who never received Penta-3 before age 1 therefore never gets DPT-B1/DPT-B2 on this list — tell the ANM/MO, who decides the catch-up. HepB-0 can only be listed on the day of birth, so with a register filled up to yesterday it never appears. JE vaccine is not listed because Chandrapuri is not a JE-endemic district (IMM-2.4). Vitamin A, Td at 10 and 16 years and HPV are given through other channels and are not on this list.

## VIS-4 Newborns: home visits

### VIS-4.1 HBNC visit days
Babies whose age today is 42 days or less get home visits on fixed days (HBNC-1.1). The day of birth counts as day 1, so the visit for day *d* falls on date of birth + (*d* − 1) days. List at most one HBNC item per baby:
1. Take the **latest scheduled visit dated on or before today**. If it is **not** recorded in `hbnc_visits_done`, list it: date before today = **overdue**, date today = **due_today**. (Older missed visits are not listed separately; this one replaces them.)
2. Otherwise (it was done, or no visit is dated on or before today yet), take the **next** scheduled visit dated after today. If its date is within the next 6 days and it is not recorded as done, list it as **due_this_week**. The item is written `HBNC-D<day>`, for example `HBNC-D7`. The register does not record caesarean deliveries, so every institutional delivery follows the institutional schedule below.

| Place of delivery | Visit days |
|---|---|
| institution | 3,7,14,21,28,42 |
| home | 1,3,7,14,21,28,42 |

## VIS-5 Children 6–59 months and NCD patients

### VIS-5.1 Who is high-risk
High-risk members get **priority 1** for every one of their items that is overdue or due today (all items of that member, not only the item linked to the risk) (see VIS-6.1). Extra low-birth-weight visits (HBNC-1.2) are not on this list. A member is high-risk if any of these is true:
- a pregnant woman whose last recorded Hb is below 7 g/dL (severe anaemia, ANC-3.2) or whose last ANC blood pressure is 140/90 or more (systolic 140 or more, or diastolic 90 or more; ANC-4.1);
- a baby 42 days old or younger (newborn period, HBNC-1.1);
- a child aged 184–1824 days whose last MUAC is below 11.5 cm or who has bilateral pitting oedema (`Y`) (NUT-1.2);
- an NCD patient (HTN, DM or both) whose last recorded BP is 140/90 or more (NCD-2.1).

| Threshold | Value |
|---|---|
| pregnancy_hb_below_gdl | 7 |
| systolic_at_or_above | 140 |
| diastolic_at_or_above | 90 |
| muac_below_cm | 11.5 |
| newborn_age_max_days | 42 |

### VIS-5.2 MUAC check
Children 6 to 59 months old are re-measured with the MUAC tape every 30 days (NUT-1.1) [block rule]. Item `MUAC-check` is due 30 days after `last_muac_date`. If the child has never been measured, it is due on the day the child becomes 184 days old. A child is considered for this item if their age today is at most 1824 days and at least 178 days (so a child turning 184 days old within the next 6 days is listed as due_this_week). It becomes overdue 28 days after its due date.

### VIS-5.3 NCD follow-up
Patients with `ncd_condition` HTN get `BP-followup`; patients with DM get `Sugar-followup`; HTN+DM get both (NCD-2.1: BP and blood sugar every month). Each is due 30 days after the last recorded check (`last_bp_check_date` or `last_sugar_check_date`) and becomes overdue 28 days after its due date. If no check date is recorded, the follow-up is overdue.

## VIS-6 Priority

### VIS-6.1 Priority tiers
- **Priority 1** — overdue or due_today items for a **high-risk** member (VIS-5.1). Visit these first.
- **Priority 2** — all other overdue or due_today items.
- **Priority 3** — due_this_week items (upcoming), for everyone.

Danger signs are never left for the visit list: if anyone has a danger sign, refer immediately (ESC-1.1).

### VIS-6.2 What the list file looks like
One row per member and item: `member_id, due_item, priority` (you may add more columns such as status; they are ignored by the scorer). Members with nothing due have no row. Item codes are exactly as written in this document (`ANC-2`, `Td-2`, `HRP-followup`, `Penta-3`, `HBNC-D7`, `MUAC-check`, `BP-followup`, `Sugar-followup`, ...).

## Sources
- Vaccine ages and upper age limits: IMM document (National Immunization Schedule, MoHFW/NHM; fIPV-3 MoHFW guidance 2023).
- ANC windows: ANC document (MoHFW ANC guidelines for ANMs/LHVs/SNs, 2010).
- HBNC visit days: HBNC document (MoHFW HBNC Operational Guidelines, revised 2014).
- MUAC and BP thresholds: NUT and NCD documents.
- [block rule] items: Chandrapuri Block operational convention for this hackathon.
