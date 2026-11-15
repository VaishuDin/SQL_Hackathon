-- ============================================================================

--  TEAM 6 - QUERY TITANS

-- ============================================================================

--  CATEGORY 2 : INTERMEDIATE  

-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. Create a reusable "analysis-ready" view of the COVID-19 cohort and use
--     it to compare hospitalisation by MS type and sex.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_covid_cohort AS
SELECT p.patient_id,
       p.report_source,
       p.sex,
       ag.age_range,
       p.ms_type,
       p.ms_onset_year,
       p.bmi_category,
       p.has_comorbidities,
       p.current_dmt_status,
       d.dmt_name,
       d.dmt_class,
       cc.diagnosis,
       cc.hospitalised,
       cc.outcome_level_id,
       COALESCE(sc.symptom_count, 0) AS symptom_count
FROM patient p
JOIN covid_case cc ON cc.patient_id   = p.patient_id
JOIN age_group  ag ON ag.age_group_id = p.age_group_id
LEFT JOIN dmt_drug d ON d.dmt_id      = p.dmt_id
LEFT JOIN (SELECT patient_id, COUNT(*) AS symptom_count
           FROM patient_symptom
           WHERE present
           GROUP BY patient_id) sc ON sc.patient_id = p.patient_id
WHERE cc.diagnosis IN ('confirmed','suspected');

SELECT INITCAP(REPLACE(ms_type, '_', ' '))                              AS ms_type,
       INITCAP(sex)                                                     AS sex,
       COUNT(*)                                                         AS cohort_patients,
       COUNT(*) FILTER (WHERE hospitalised)                             AS hospitalised,
       ROUND(100.0 * COUNT(*) FILTER (WHERE hospitalised) / COUNT(*), 1) AS hosp_rate_pct
FROM v_covid_cohort
GROUP BY ms_type, sex
ORDER BY ms_type, sex;


-- ---------------------------------------------------------------------
-- Q2. What is the hospitalisation count and rate for each sex and age
--     group in the COVID-19 cohort, with subtotals and a grand total?
-- ---------------------------------------------------------------------
SELECT CASE WHEN GROUPING(p.sex) = 1 THEN 'All sexes'
            ELSE INITCAP(p.sex) END                                    AS sex,
       CASE WHEN GROUPING(ag.age_range) = 1 THEN 'All ages'
            ELSE ag.age_range END                                      AS age_range,
       COUNT(*)                                                        AS cohort_patients,
       COUNT(*) FILTER (WHERE cc.hospitalised)                         AS hospitalised,
       ROUND(100.0 * COUNT(*) FILTER (WHERE cc.hospitalised)
                   / COUNT(*), 1)                                      AS hosp_rate_pct
FROM patient p
JOIN covid_case cc ON cc.patient_id    = p.patient_id
JOIN age_group  ag ON ag.age_group_id  = p.age_group_id
WHERE cc.diagnosis IN ('confirmed','suspected')
GROUP BY ROLLUP (p.sex, ag.age_range)
ORDER BY GROUPING(p.sex), p.sex, GROUPING(ag.age_range), ag.age_range;


-- ---------------------------------------------------------------------
-- Q3. Rank the individual MS drugs by hospitalisation rate in the COVID-19
--     cohort (drugs with at least 5 cohort patients).
-- ---------------------------------------------------------------------
WITH drug_rates AS (
    SELECT d.dmt_name,
           COUNT(*)                                          AS cohort_patients,
           COUNT(*) FILTER (WHERE cc.hospitalised)           AS hospitalised,
           ROUND(100.0 * COUNT(*) FILTER (WHERE cc.hospitalised)
                       / COUNT(*), 1)                        AS hosp_rate_pct
    FROM patient p
    JOIN covid_case cc ON cc.patient_id = p.patient_id
    JOIN dmt_drug   d  ON d.dmt_id      = p.dmt_id
    WHERE cc.diagnosis IN ('confirmed','suspected')
      AND d.dmt_name NOT IN ('none','never_treated')
    GROUP BY d.dmt_name
    HAVING COUNT(*) >= 5
)
SELECT RANK()       OVER (ORDER BY hosp_rate_pct DESC) AS rate_rank,
       DENSE_RANK() OVER (ORDER BY hosp_rate_pct DESC) AS rate_dense_rank,
       INITCAP(dmt_name)                                AS dmt_drug,
       cohort_patients,
       hospitalised,
       hosp_rate_pct
FROM drug_rates
ORDER BY rate_rank, cohort_patients DESC;


-- ---------------------------------------------------------------------
-- Q4. What share of named-DMT patients falls into each drug class?
-- ---------------------------------------------------------------------
SELECT d.dmt_class,
       COUNT(*)                                                    AS patients,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS pct_of_named_dmt_patients
FROM patient p
JOIN dmt_drug d ON d.dmt_id = p.dmt_id
WHERE d.dmt_name NOT IN ('none','never_treated')
GROUP BY d.dmt_class
ORDER BY patients DESC;


-- ---------------------------------------------------------------------
-- Q5. How far does each DMT's patient count drop from the previous, more common drug?
-- ---------------------------------------------------------------------
WITH drug_counts AS (
    SELECT d.dmt_name,
           COUNT(*) AS patient_count
    FROM patient p
    JOIN dmt_drug d ON d.dmt_id = p.dmt_id
    WHERE d.dmt_name NOT IN ('none','never_treated')
    GROUP BY d.dmt_name
),
ordered AS (
    SELECT dmt_name,
           patient_count,
           LAG(patient_count) OVER (ORDER BY patient_count DESC, dmt_name) AS previous_drug_count
    FROM drug_counts
)
SELECT INITCAP(dmt_name)                                           AS dmt_drug,
       patient_count,
       previous_drug_count,
       patient_count - previous_drug_count                         AS difference_from_previous,
       ROUND(100.0 * (patient_count - previous_drug_count)
                   / NULLIF(previous_drug_count, 0), 1)            AS pct_change
FROM ordered
ORDER BY patient_count DESC, dmt_name;


-- ---------------------------------------------------------------------
-- Q6. For each comorbidity, how much more likely was hospitalisation in
--     people WITH the condition than in people without it (relative risk)?
-- ---------------------------------------------------------------------
WITH comorb AS (
    SELECT m.comorbidity_name,
           COUNT(*) FILTER (WHERE pc.present)                           AS with_n,
           COUNT(*) FILTER (WHERE pc.present AND cc.hospitalised)       AS with_hosp,
           COUNT(*) FILTER (WHERE NOT pc.present)                       AS without_n,
           COUNT(*) FILTER (WHERE NOT pc.present AND cc.hospitalised)   AS without_hosp
    FROM patient_comorbidity pc
    JOIN comorbidity m  ON m.comorbidity_id = pc.comorbidity_id
    JOIN covid_case  cc ON cc.patient_id    = pc.patient_id
    WHERE cc.diagnosis IN ('confirmed','suspected')
    GROUP BY m.comorbidity_name
)
SELECT INITCAP(REPLACE(comorbidity_name, '_', ' '))                     AS comorbidity,
       with_n                                                           AS patients_with,
       with_hosp                                                        AS hosp_with,
       ROUND(100.0 * with_hosp / with_n, 1)                             AS rate_with_pct,
       ROUND(100.0 * without_hosp / NULLIF(without_n, 0), 1)            AS rate_without_pct,
       ROUND((1.0 * with_hosp / with_n)
             / NULLIF(1.0 * without_hosp / NULLIF(without_n, 0), 0), 1) AS relative_risk
FROM comorb
WHERE with_n >= 3
ORDER BY relative_risk DESC NULLS LAST, with_n DESC;


-- ---------------------------------------------------------------------
-- Q7. Does hospitalisation and ICU admission rise with the number of comorbidities?
-- ---------------------------------------------------------------------
WITH comorb_counts AS (
    SELECT patient_id,
           COUNT(*) FILTER (WHERE present) AS n_comorb
    FROM patient_comorbidity
    GROUP BY patient_id
)
SELECT CASE WHEN COALESCE(cn.n_comorb, 0) = 0 THEN '0 comorbidities'
            WHEN cn.n_comorb = 1               THEN '1 comorbidity'
            WHEN cn.n_comorb = 2               THEN '2 comorbidities'
            ELSE '3+ comorbidities' END                             AS comorbidity_bracket,
       COUNT(*)                                                     AS cohort_patients,
       SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)             AS hospitalised,
       ROUND(100.0 * SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)
                   / COUNT(*), 1)                                   AS hosp_rate_pct,
       SUM(CASE WHEN cc.icu_stay THEN 1 ELSE 0 END)                 AS icu_cases,
       ROUND(100.0 * SUM(CASE WHEN cc.icu_stay THEN 1 ELSE 0 END)
                   / COUNT(*), 1)                                   AS icu_rate_pct
FROM patient p
JOIN covid_case cc ON cc.patient_id = p.patient_id
LEFT JOIN comorb_counts cn ON cn.patient_id = p.patient_id
WHERE cc.diagnosis IN ('confirmed','suspected')
GROUP BY 1
ORDER BY MIN(COALESCE(cn.n_comorb, 0));


-- ---------------------------------------------------------------------
-- Q8. What are the three most common comorbidities within each MS type?
-- ---------------------------------------------------------------------
WITH counts AS (
    SELECT p.ms_type,
           m.comorbidity_name,
           COUNT(*) AS patients,
           ROW_NUMBER() OVER (PARTITION BY p.ms_type
                              ORDER BY COUNT(*) DESC, m.comorbidity_name) AS rn
    FROM patient p
    JOIN patient_comorbidity pc ON pc.patient_id     = p.patient_id
    JOIN comorbidity         m  ON m.comorbidity_id  = pc.comorbidity_id
    WHERE pc.present
      AND m.comorbidity_name <> 'other'
    GROUP BY p.ms_type, m.comorbidity_name
)
SELECT CASE c.ms_type WHEN 'progressive_ms' THEN 'Progressive MS'
            ELSE INITCAP(REPLACE(c.ms_type, '_', ' ')) END          AS ms_type,
       c.rn                                                         AS prevalence_rank,
       INITCAP(REPLACE(c.comorbidity_name, '_', ' '))               AS comorbidity,
       c.patients,
       ROUND(100.0 * c.patients /
             (SELECT COUNT(*) FROM patient p2 WHERE p2.ms_type = c.ms_type), 1) AS pct_of_ms_type
FROM counts c
WHERE c.rn <= 3
ORDER BY c.ms_type, c.rn;


-- ---------------------------------------------------------------------
-- Q9. Do patients with the lowest and highest total symptom burden differ in hospitalisation, and does a respiratory symptom change the picture?
-- ---------------------------------------------------------------------
WITH base AS (
    SELECT v.patient_id,
           v.hospitalised,
           v.symptom_count,
           EXISTS (SELECT 1
                   FROM patient_symptom ps
                   JOIN symptom s ON s.symptom_id = ps.symptom_id
                   WHERE ps.patient_id = v.patient_id
                     AND ps.present
                     AND s.symptom_name IN ('dry_cough','shortness_breath','pneumonia')) AS respiratory
    FROM v_covid_cohort v
),
quint AS (
    SELECT base.*,
           NTILE(5) OVER (ORDER BY symptom_count, patient_id) AS symptom_quintile
    FROM base
)
SELECT symptom_quintile,
       CASE WHEN respiratory THEN 'Respiratory symptom'
            ELSE 'No respiratory symptom' END                       AS respiratory_involvement,
       MIN(symptom_count)                                           AS min_symptoms,
       MAX(symptom_count)                                           AS max_symptoms,
       COUNT(*)                                                     AS patients,
       COUNT(*) FILTER (WHERE hospitalised)                         AS hospitalised,
       ROUND(100.0 * COUNT(*) FILTER (WHERE hospitalised) / COUNT(*), 1) AS hosp_rate_pct
FROM quint
GROUP BY symptom_quintile, respiratory
ORDER BY symptom_quintile, respiratory;


-- ---------------------------------------------------------------------
-- Q10. What share of all reported symptom events does each symptom account for, and how do the symptoms rank by hospitalisation rate?
-- ---------------------------------------------------------------------
WITH sym AS (
    SELECT s.symptom_name,
           COUNT(*)                                AS patients_with_symptom,
           COUNT(*) FILTER (WHERE cc.hospitalised) AS hospitalised
    FROM patient_symptom ps
    JOIN symptom    s  ON s.symptom_id  = ps.symptom_id
    JOIN covid_case cc ON cc.patient_id = ps.patient_id
    WHERE ps.present
      AND cc.diagnosis IN ('confirmed','suspected')
    GROUP BY s.symptom_name
)
SELECT INITCAP(REPLACE(symptom_name, '_', ' '))                     AS symptom,
       patients_with_symptom,
       ROUND(100.0 * patients_with_symptom
                   / SUM(patients_with_symptom) OVER (), 1)         AS share_of_events_pct,
       hospitalised,
       ROUND(100.0 * hospitalised / patients_with_symptom, 1)       AS hosp_rate_pct,
       RANK() OVER (ORDER BY 100.0 * hospitalised / patients_with_symptom DESC)
                                                                    AS hosp_rate_rank
FROM sym
ORDER BY hosp_rate_rank;


-- ---------------------------------------------------------------------
-- Q11. Which cohort patients reported more symptoms than the average for
--      their own diagnosis group (confirmed vs suspected)?
-- ---------------------------------------------------------------------
WITH scored AS (
    SELECT patient_id,
           diagnosis,
           hospitalised,
           symptom_count,
           ROUND(AVG(symptom_count) OVER (PARTITION BY diagnosis), 2) AS diagnosis_avg
    FROM v_covid_cohort
)
SELECT patient_id,
       diagnosis,
       symptom_count,
       diagnosis_avg,
       symptom_count - diagnosis_avg AS above_avg_by,
       hospitalised
FROM scored
WHERE symptom_count > diagnosis_avg
ORDER BY above_avg_by DESC, patient_id
LIMIT 10;


-- ---------------------------------------------------------------------
-- Q12. Where do the ICU patients sit, by number of comorbidities, among all patients of their own age group?
-- ---------------------------------------------------------------------
WITH comorb AS (
    SELECT p.patient_id,
           p.age_group_id,
           cc.icu_stay,
           COUNT(pc.comorbidity_id) FILTER (WHERE pc.present) AS comorbidity_count
    FROM patient p
    JOIN covid_case cc ON cc.patient_id = p.patient_id
    LEFT JOIN patient_comorbidity pc ON pc.patient_id = p.patient_id
    GROUP BY p.patient_id, p.age_group_id, cc.icu_stay
),
ranked AS (
    SELECT comorb.*,
           PERCENT_RANK() OVER (PARTITION BY age_group_id ORDER BY comorbidity_count) AS pct_rank,
           COUNT(*)       OVER (PARTITION BY age_group_id)                            AS patients_in_age_group
    FROM comorb
)
SELECT r.patient_id,
       ag.age_range,
       r.comorbidity_count,
       r.patients_in_age_group,
       ROUND((100 * r.pct_rank)::numeric, 1) AS percentile_rank
FROM ranked r
JOIN age_group ag ON ag.age_group_id = r.age_group_id
WHERE r.icu_stay
ORDER BY ag.age_group_id, r.pct_rank DESC;


-- ---------------------------------------------------------------------
-- Q13. How do patient numbers and hospitalisation rates build up across MS onset decades?
-- ---------------------------------------------------------------------
WITH decade AS (
    SELECT (p.ms_onset_year / 10) * 10                    AS decade_start,
           COUNT(*)                                       AS patients,
           COUNT(*) FILTER (WHERE cc.hospitalised)        AS hospitalised
    FROM patient p
    JOIN covid_case cc ON cc.patient_id = p.patient_id
    WHERE cc.diagnosis IN ('confirmed','suspected')
      AND p.ms_onset_year IS NOT NULL
    GROUP BY 1
)
SELECT decade_start::text || 's'                                    AS onset_decade,
       patients,
       SUM(patients) OVER (ORDER BY decade_start)                   AS cumulative_patients,
       ROUND(100.0 * SUM(patients) OVER (ORDER BY decade_start)
                   / SUM(patients) OVER (), 1)                      AS cumulative_pct,
       hospitalised,
       ROUND(100.0 * hospitalised / patients, 1)                    AS hosp_rate_pct
FROM decade
ORDER BY decade_start;


-- ---------------------------------------------------------------------
-- Q14. How many years after MS onset was the date recorded, by MS type
--     (average and median)?
-- ---------------------------------------------------------------------
SELECT INITCAP(REPLACE(ms_type, '_', ' '))                              AS ms_type,
       COUNT(*)                                                         AS patients,
       ROUND(AVG(yrs_since_onset), 1)                                   AS avg_years,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY yrs_since_onset)::numeric, 1)
                                                                        AS median_years,
       MIN(yrs_since_onset)                                             AS min_years,
       MAX(yrs_since_onset)                                             AS max_years
FROM (
    SELECT ms_type,
           EXTRACT(YEAR FROM stop_or_end_date)::int - ms_onset_year     AS yrs_since_onset
    FROM patient
    WHERE ms_onset_year IS NOT NULL
      AND stop_or_end_date IS NOT NULL
      AND EXTRACT(YEAR FROM stop_or_end_date) >= ms_onset_year
) t
GROUP BY ms_type
ORDER BY avg_years DESC;


-- ---------------------------------------------------------------------
-- Q15. How are the recorded stop/end dates spread across five time periods?
-- ---------------------------------------------------------------------
WITH era (era_label, era_range) AS (
    VALUES ('1. Up to 2017',      daterange('1990-01-01', '2018-01-01', '[)')),
           ('2. 2018-2019',       daterange('2018-01-01', '2020-01-01', '[)')),
           ('3. Jan-Feb 2020',    daterange('2020-01-01', '2020-03-01', '[)')),
           ('4. Mar-Apr 2020',    daterange('2020-03-01', '2020-05-01', '[)')),
           ('5. May 2020 onward', daterange('2020-05-01', '2021-01-01', '[)'))
)
SELECT e.era_label,
       COUNT(*)                                                         AS patients,
       ROUND(100.0 * COUNT(*) /
             (SELECT COUNT(stop_or_end_date) FROM patient), 1)          AS pct_of_dated_records
FROM era e
JOIN patient p ON e.era_range @> p.stop_or_end_date
GROUP BY e.era_label
ORDER BY e.era_label;


-- ---------------------------------------------------------------------
-- Q16. How many dates were recorded in each month of 2019-2020, including
--      months with none, plus a 3-month moving average?
-- ---------------------------------------------------------------------
WITH months AS (
    SELECT generate_series(DATE '2019-01-01', DATE '2020-12-01', INTERVAL '1 month')::date
           AS month_start
)
SELECT TO_CHAR(m.month_start, 'Mon YYYY')                               AS month,
       COUNT(p.patient_id)                                              AS records,
       ROUND(AVG(COUNT(p.patient_id)) OVER (ORDER BY m.month_start
                                            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1)
                                                                        AS moving_avg_3m
FROM months m
LEFT JOIN patient p
       ON p.stop_or_end_date >= m.month_start
      AND p.stop_or_end_date <  m.month_start + INTERVAL '1 month'
GROUP BY m.month_start
ORDER BY m.month_start;


-- ---------------------------------------------------------------------
-- Q17. Which hospitalised cohort patients had NO recorded comorbidity?
-- ---------------------------------------------------------------------
WITH hosp_no_comorb AS (
    SELECT patient_id
    FROM covid_case
    WHERE hospitalised
      AND diagnosis IN ('confirmed','suspected')
    EXCEPT
    SELECT patient_id
    FROM patient
    WHERE has_comorbidities
)
SELECT p.patient_id,
       ag.age_range,
       INITCAP(p.sex)                         AS sex,
       INITCAP(REPLACE(p.ms_type,'_',' '))    AS ms_type,
       COALESCE(d.dmt_name, 'unknown')        AS dmt,
       cc.diagnosis,
       cc.icu_stay
FROM hosp_no_comorb h
JOIN patient    p  ON p.patient_id    = h.patient_id
JOIN covid_case cc ON cc.patient_id   = h.patient_id
JOIN age_group  ag ON ag.age_group_id = p.age_group_id
LEFT JOIN dmt_drug d ON d.dmt_id      = p.dmt_id
ORDER BY p.patient_id;


-- ---------------------------------------------------------------------
-- Q18. How many confirmed COVID-19 cases have zero, one, or two-plus symptoms recorded, and who reported them?
-- ---------------------------------------------------------------------
SELECT CASE WHEN v.symptom_count = 0 THEN '0 symptoms recorded'
            WHEN v.symptom_count = 1 THEN '1 symptom recorded'
            ELSE '2+ symptoms recorded' END                         AS symptom_records,
       INITCAP(v.report_source)                                     AS report_source,
       COUNT(*)                                                     AS confirmed_cases,
       ROUND(100.0 * COUNT(*) /
             (SELECT COUNT(*) FROM covid_case WHERE diagnosis = 'confirmed'), 1) AS pct_of_confirmed
FROM v_covid_cohort v
WHERE v.diagnosis = 'confirmed'
GROUP BY 1, v.report_source
ORDER BY MIN(v.symptom_count), v.report_source;


-- ---------------------------------------------------------------------
-- Q19. Which patient fields have the most missing values?
-- ---------------------------------------------------------------------
SELECT field_name,
       population,
       missing_count,
       ROUND(100.0 * missing_count / population, 2) AS missing_pct
FROM (
    SELECT 'bmi_category' AS field_name,
           COUNT(*) AS population,
           COUNT(*) FILTER (WHERE bmi_category IS NULL) AS missing_count
    FROM patient
    UNION ALL
    SELECT 'ms_onset_year', COUNT(*), COUNT(*) FILTER (WHERE ms_onset_year IS NULL)
    FROM patient
    UNION ALL
    SELECT 'edss_cat', COUNT(*), COUNT(*) FILTER (WHERE edss_cat IS NULL)
    FROM patient
    UNION ALL
    SELECT 'treatment_duration_cat', COUNT(*), COUNT(*) FILTER (WHERE treatment_duration_cat IS NULL)
    FROM patient
    UNION ALL
    SELECT 'on_glucocorticoid', COUNT(*), COUNT(*) FILTER (WHERE on_glucocorticoid IS NULL)
    FROM patient
    UNION ALL
    SELECT 'stop_or_end_date', COUNT(*), COUNT(*) FILTER (WHERE stop_or_end_date IS NULL)
    FROM patient
    UNION ALL
    SELECT 'pregnancy (females only)', COUNT(*), COUNT(*) FILTER (WHERE pregnancy IS NULL)
    FROM patient
    WHERE sex = 'female'
) x
ORDER BY missing_pct DESC;


-- ---------------------------------------------------------------------
-- Q20. Do the highest-risk drugs stay the same when only lab-confirmed COVID-19 cases are used?
-- ---------------------------------------------------------------------
WITH drug_rates AS (
    SELECT d.dmt_name,
           COUNT(*)                                           AS confirmed_cases,
           COUNT(*) FILTER (WHERE cc.hospitalised)            AS hospitalised,
           ROUND(100.0 * COUNT(*) FILTER (WHERE cc.hospitalised)
                       / COUNT(*), 1)                         AS hosp_rate_pct
    FROM patient p
    JOIN covid_case cc ON cc.patient_id = p.patient_id
    JOIN dmt_drug   d  ON d.dmt_id      = p.dmt_id
    WHERE cc.diagnosis = 'confirmed'
      AND d.dmt_name NOT IN ('none','never_treated')
    GROUP BY d.dmt_name
    HAVING COUNT(*) >= 3
)
SELECT RANK() OVER (ORDER BY hosp_rate_pct DESC) AS rate_rank,
       INITCAP(dmt_name)                         AS dmt_drug,
       confirmed_cases,
       hospitalised,
       hosp_rate_pct
FROM drug_rates
ORDER BY rate_rank, confirmed_cases DESC, dmt_drug;


-- ---------------------------------------------------------------------
-- Q21. Among drugs with at least 20 cohort patients, which have a higher hospitalisation rate than all the OTHER named drugs combined?
-- ---------------------------------------------------------------------
WITH drug AS (
    SELECT d.dmt_name,
           COUNT(*)                                AS n,
           COUNT(*) FILTER (WHERE cc.hospitalised) AS h
    FROM patient p
    JOIN covid_case cc ON cc.patient_id = p.patient_id
    JOIN dmt_drug   d  ON d.dmt_id      = p.dmt_id
    WHERE cc.diagnosis IN ('confirmed','suspected')
      AND d.dmt_name NOT IN ('none','never_treated')
    GROUP BY d.dmt_name
),
compared AS (
    SELECT dmt_name, n, h,
           100.0 * h / n                                       AS rate_pct,
           100.0 * (SUM(h) OVER () - h) / (SUM(n) OVER () - n) AS rate_other_pct
    FROM drug
)
SELECT INITCAP(dmt_name)                                       AS dmt_drug,
       n                                                       AS cohort_patients,
       h                                                       AS hospitalised,
       ROUND(rate_pct, 1)                                      AS hosp_rate_pct,
       ROUND(rate_other_pct, 1)                                AS rate_other_drugs_pct,
       ROUND(rate_pct / NULLIF(rate_other_pct, 0), 2)          AS relative_risk
FROM compared
WHERE n >= 20
ORDER BY relative_risk DESC;


-- ---------------------------------------------------------------------
-- Q22. How does each ICU patient's clinical burden (symptoms + comorbidities) compare with the average, and the rank, within their own DMT class?
-- ---------------------------------------------------------------------
WITH burden AS (
    SELECT p.patient_id,
           COALESCE(d.dmt_class, 'Unknown')   AS dmt_class,
           cc.icu_stay,
           COALESCE(sc.n, 0)                  AS symptom_count,
           COALESCE(cm.n, 0)                  AS comorbidity_count
    FROM patient p
    JOIN covid_case cc ON cc.patient_id = p.patient_id
    LEFT JOIN dmt_drug d ON d.dmt_id    = p.dmt_id
    LEFT JOIN (SELECT patient_id, COUNT(*) AS n
               FROM patient_symptom WHERE present GROUP BY patient_id) sc ON sc.patient_id = p.patient_id
    LEFT JOIN (SELECT patient_id, COUNT(*) AS n
               FROM patient_comorbidity WHERE present GROUP BY patient_id) cm ON cm.patient_id = p.patient_id
    WHERE cc.diagnosis IN ('confirmed','suspected')
),
scored AS (
    SELECT burden.*,
           symptom_count + comorbidity_count                                   AS total_burden,
           ROUND(AVG(symptom_count + comorbidity_count) OVER (PARTITION BY dmt_class), 2) AS class_avg,
           RANK() OVER (PARTITION BY dmt_class
                        ORDER BY symptom_count + comorbidity_count DESC)       AS burden_rank,
           COUNT(*) OVER (PARTITION BY dmt_class)                              AS class_size
    FROM burden
)
SELECT patient_id,
       dmt_class,
       symptom_count,
       comorbidity_count,
       total_burden,
       class_avg,
       total_burden - class_avg AS deviation_from_class_avg,
       burden_rank,
       class_size
FROM scored
WHERE icu_stay
ORDER BY deviation_from_class_avg DESC;


-- ---------------------------------------------------------------------
-- Q23. How do MS type and sex subgroups compare in average symptom and comorbidity burden?
-- ---------------------------------------------------------------------
WITH per_patient AS (
    SELECT p.ms_type,
           p.sex,
           COALESCE(sc.n, 0) AS symptoms,
           COALESCE(cm.n, 0) AS comorbidities
    FROM patient p
    JOIN covid_case cc ON cc.patient_id = p.patient_id
    LEFT JOIN (SELECT patient_id, COUNT(*) AS n
               FROM patient_symptom WHERE present GROUP BY patient_id) sc ON sc.patient_id = p.patient_id
    LEFT JOIN (SELECT patient_id, COUNT(*) AS n
               FROM patient_comorbidity WHERE present GROUP BY patient_id) cm ON cm.patient_id = p.patient_id
    WHERE cc.diagnosis IN ('confirmed','suspected')
)
SELECT CASE ms_type WHEN 'progressive_ms' THEN 'Progressive MS'
            ELSE INITCAP(REPLACE(ms_type, '_', ' ')) END           AS ms_type,
       INITCAP(sex)                                                AS sex,
       COUNT(*)                                                    AS cohort_patients,
       ROUND(AVG(symptoms), 2)                                     AS avg_symptoms,
       ROUND(AVG(comorbidities), 2)                                AS avg_comorbidities,
       ROUND(AVG(symptoms + comorbidities), 2)                     AS avg_total_burden,
       RANK() OVER (ORDER BY AVG(symptoms + comorbidities) DESC)   AS burden_rank
FROM per_patient
GROUP BY ms_type, sex
ORDER BY burden_rank;


-- ---------------------------------------------------------------------
-- Q24. How often is loss of smell or taste reported by symptomatic COVID-19 cohort patients, and how is it spread across age groups?
-- ---------------------------------------------------------------------
WITH asked AS (
    SELECT ag.age_group_id,
           ag.age_range,
           ps.present
    FROM patient p
    JOIN covid_case      cc ON cc.patient_id   = p.patient_id
    JOIN age_group       ag ON ag.age_group_id = p.age_group_id
    JOIN patient_symptom ps ON ps.patient_id   = p.patient_id
    JOIN symptom         s  ON s.symptom_id    = ps.symptom_id
    WHERE cc.diagnosis IN ('confirmed','suspected')
      AND cc.has_symptoms
      AND s.symptom_name = 'loss_smell_taste'
)
SELECT age_range,
       COUNT(*)                                                    AS symptomatic_patients_asked,
       COUNT(*) FILTER (WHERE present)                             AS reported_loss_smell_taste,
       ROUND(100.0 * COUNT(*) FILTER (WHERE present) / COUNT(*), 1) AS pct_within_age_group,
       ROUND(100.0 * COUNT(*) FILTER (WHERE present)
                   / SUM(COUNT(*) FILTER (WHERE present)) OVER (), 1) AS pct_of_all_cases
FROM asked
GROUP BY age_group_id, age_range
ORDER BY age_group_id;


-- ---------------------------------------------------------------------
-- Q25. Who has the longest-standing MS in each MS type, and how did COVID-19 affect them?
-- ---------------------------------------------------------------------
SELECT CASE p.ms_type WHEN 'progressive_ms' THEN 'Progressive MS'
            ELSE INITCAP(REPLACE(p.ms_type, '_', ' ')) END         AS ms_type,
       p.ms_onset_year,
       p.patient_id,
       ag.age_range,
       cc.diagnosis,
       cc.hospitalised
FROM patient p
JOIN covid_case cc ON cc.patient_id   = p.patient_id
JOIN age_group  ag ON ag.age_group_id = p.age_group_id
WHERE p.ms_onset_year = (SELECT MIN(p2.ms_onset_year)
                         FROM patient p2
                         WHERE p2.ms_type = p.ms_type)
ORDER BY p.ms_onset_year, p.patient_id;


-- ---------------------------------------------------------------------
-- Q26. For each drug, how many patients have a recorded stop/end date, and what is the earliest, latest and span of those dates?
-- ---------------------------------------------------------------------
SELECT COALESCE(INITCAP(REPLACE(d.dmt_name, '_', ' ')), 'No drug recorded') AS dmt_drug,
       COUNT(*)                                                    AS patients,
       COUNT(p.stop_or_end_date)                                   AS dated_records,
       ROUND(100.0 * COUNT(p.stop_or_end_date) / COUNT(*), 1)      AS pct_with_date,
       MIN(p.stop_or_end_date)                                     AS earliest_date,
       MAX(p.stop_or_end_date)                                     AS latest_date,
       AGE(MAX(p.stop_or_end_date), MIN(p.stop_or_end_date))       AS date_span
FROM patient p
LEFT JOIN dmt_drug d ON d.dmt_id = p.dmt_id
GROUP BY d.dmt_name
ORDER BY pct_with_date DESC, patients DESC;


-- ---------------------------------------------------------------------
-- Q27. Is the confirmed-case rate different across age groups, and how much does the report source change it?
-- ---------------------------------------------------------------------

SELECT ag.age_range,
       INITCAP(p.report_source)                                    AS report_source,
       COUNT(*)                                                    AS patients,
       COUNT(*) FILTER (WHERE cc.confirmed_case)                   AS confirmed_cases,
       ROUND(100.0 * COUNT(*) FILTER (WHERE cc.confirmed_case) / COUNT(*), 1) AS confirmed_pct,
       ROUND(100.0 * SUM(COUNT(*) FILTER (WHERE cc.confirmed_case)) OVER (PARTITION BY ag.age_group_id)
                   / SUM(COUNT(*)) OVER (PARTITION BY ag.age_group_id), 1)     AS age_group_confirmed_pct,
       DENSE_RANK() OVER (ORDER BY 100.0 * COUNT(*) FILTER (WHERE cc.confirmed_case) / COUNT(*) DESC)
                                                                   AS rate_rank
FROM patient p
JOIN covid_case cc ON cc.patient_id   = p.patient_id
JOIN age_group  ag ON ag.age_group_id = p.age_group_id
GROUP BY ag.age_group_id, ag.age_range, p.report_source
ORDER BY ag.age_group_id, p.report_source;


-- ---------------------------------------------------------------------
-- Q28. What is the 3-year moving average of new MS onsets per year from 1990 onwards?
-- ---------------------------------------------------------------------
WITH years AS (
    SELECT generate_series(1990, 2020) AS yr
),
counts AS (
    SELECT ms_onset_year AS yr,
           COUNT(*)      AS patients
    FROM patient
    WHERE ms_onset_year BETWEEN 1990 AND 2020
    GROUP BY ms_onset_year
)
SELECT y.yr                                                        AS onset_year,
       COALESCE(c.patients, 0)                                     AS patients,
       ROUND(AVG(COALESCE(c.patients, 0)) OVER (ORDER BY y.yr
                                                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1)
                                                                   AS moving_avg_3yr
FROM years y
LEFT JOIN counts c ON c.yr = y.yr
ORDER BY y.yr;


-- ---------------------------------------------------------------------
-- Q29. What percentage of each MS type is female, and how far is that from the overall percentage?
-- ---------------------------------------------------------------------
SELECT CASE p.ms_type WHEN 'progressive_ms' THEN 'Progressive MS'
            ELSE INITCAP(REPLACE(p.ms_type, '_', ' ')) END         AS ms_type,
       COUNT(*)                                                    AS patients,
       COUNT(*) FILTER (WHERE p.sex = 'female')                    AS female_patients,
       ROUND(100.0 * COUNT(*) FILTER (WHERE p.sex = 'female') / COUNT(*), 1) AS female_pct,
       ROUND(100.0 * SUM(COUNT(*) FILTER (WHERE p.sex = 'female')) OVER ()
                   / SUM(COUNT(*)) OVER (), 1)                     AS overall_female_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE p.sex = 'female') / COUNT(*)
           - 100.0 * SUM(COUNT(*) FILTER (WHERE p.sex = 'female')) OVER ()
                   / SUM(COUNT(*)) OVER (), 1)                     AS points_vs_overall
FROM patient p
GROUP BY p.ms_type
ORDER BY female_pct DESC;


-- ---------------------------------------------------------------------
-- Q30. What is the average severity level, and how many severe outcomes, in each COVID-19 diagnosis group?
-- ---------------------------------------------------------------------
SELECT diagnosis,
       COUNT(*)                                                    AS records,
       ROUND(AVG(outcome_level_id), 3)                             AS severity_index_0_to_2,
       COUNT(*) FILTER (WHERE outcome_level_id = 1)                AS level_1_hospitalised,
       COUNT(*) FILTER (WHERE outcome_level_id = 2)                AS level_2_icu_or_ventilation,
       ROUND(100.0 * COUNT(*) FILTER (WHERE outcome_level_id >= 1) / COUNT(*), 1)
                                                                   AS pct_hospitalised_or_worse
FROM covid_case
GROUP BY diagnosis
ORDER BY severity_index_0_to_2 DESC;