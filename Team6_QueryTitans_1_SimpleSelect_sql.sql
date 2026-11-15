-- ============================================================================

--  TEAM 6 - QUERY TITANS

-- ============================================================================

--  CATEGORY 1 : SIMPLE SELECT   

-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. How is the whole dataset distributed by sex, MS type, BMI category
--     and DMT status?
-- ---------------------------------------------------------------------
SELECT 'Sex' AS dimension,
       INITCAP(p.sex)                                                  AS category,
       COUNT(*)                                                        AS patients,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM patient), 1)     AS pct_of_patients
FROM patient p
GROUP BY p.sex
UNION ALL
SELECT 'MS type',
       CASE p.ms_type WHEN 'progressive_ms' THEN 'Progressive MS'
            ELSE INITCAP(REPLACE(p.ms_type, '_', ' ')) END,
       COUNT(*),
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM patient), 1)
FROM patient p
GROUP BY p.ms_type
UNION ALL
SELECT 'BMI category',
       COALESCE(INITCAP(REPLACE(p.bmi_category, '_', ' ')), 'Not reported'),
       COUNT(*),
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM patient), 1)
FROM patient p
GROUP BY p.bmi_category
UNION ALL
SELECT 'DMT status',
       CASE p.current_dmt_status
            WHEN 'yes'           THEN 'On a DMT'
            WHEN 'no'            THEN 'Not currently on a DMT'
            ELSE 'Never treated' END,
       COUNT(*),
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM patient), 1)
FROM patient p
GROUP BY p.current_dmt_status
ORDER BY dimension, patients DESC;


-- ---------------------------------------------------------------------
-- Q2. How many people fall into each COVID-19 diagnosis group, and how
--     many of each group were hospitalised?
-- ---------------------------------------------------------------------
SELECT diagnosis,
       COUNT(*)                                                       AS patients,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM covid_case), 1) AS pct_of_dataset,
       SUM(CASE WHEN hospitalised THEN 1 ELSE 0 END)                  AS hospitalised,
       ROUND(100.0 * SUM(CASE WHEN hospitalised THEN 1 ELSE 0 END)
                   / COUNT(*), 1)                                     AS hosp_rate_pct
FROM covid_case
GROUP BY diagnosis
ORDER BY patients DESC;


-- ---------------------------------------------------------------------
-- Q3. What is the patient count and percentage by age group and sex?
-- ---------------------------------------------------------------------
SELECT ag.age_range,
       INITCAP(p.sex)                                                  AS sex,
       COUNT(*)                                                        AS patients,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM patient), 1)     AS pct_of_all_patients
FROM patient p
JOIN age_group ag ON ag.age_group_id = p.age_group_id
GROUP BY ag.age_group_id, ag.age_range, p.sex
ORDER BY ag.age_group_id, p.sex;


-- ---------------------------------------------------------------------
-- Q4. Is the hospitalisation rate different between patient-reported and
--     clinician-reported records?
-- ---------------------------------------------------------------------
SELECT p.report_source,
       SPLIT_PART(p.patient_id, '_', 1)                                AS id_prefix,
       COUNT(*)                                                        AS patients,
       SUM(CASE WHEN cc.diagnosis = 'confirmed' THEN 1 ELSE 0 END)     AS confirmed_cases,
       SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)                AS hospitalised,
       ROUND(100.0 * SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)
                   / COUNT(*), 1)                                      AS hosp_rate_pct
FROM patient p
JOIN covid_case cc ON cc.patient_id = p.patient_id
GROUP BY p.report_source, SPLIT_PART(p.patient_id, '_', 1)
ORDER BY hosp_rate_pct DESC;


-- ---------------------------------------------------------------------
-- Q5. How is the COVID-19 cohort spread across MS disease-duration brackets,
--     and how many in each bracket were hospitalised?
-- ---------------------------------------------------------------------
SELECT CASE WHEN 2020 - p.ms_onset_year < 5  THEN '0-4 years'
            WHEN 2020 - p.ms_onset_year < 10 THEN '5-9 years'
            WHEN 2020 - p.ms_onset_year < 20 THEN '10-19 years'
            ELSE '20+ years' END                                       AS duration_bracket,
       COUNT(*)                                                        AS cohort_patients,
       SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)                AS hospitalised,
       ROUND(100.0 * SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)
                   / COUNT(*), 1)                                      AS hosp_rate_pct
FROM patient p
JOIN covid_case cc ON cc.patient_id = p.patient_id
WHERE cc.diagnosis IN ('confirmed','suspected')
  AND p.ms_onset_year IS NOT NULL
GROUP BY 1
ORDER BY MIN(2020 - p.ms_onset_year);


-- ---------------------------------------------------------------------
-- Q6. What does the severity ladder look like for the COVID-19 cohort?
-- ---------------------------------------------------------------------
SELECT ol.outcome_level_id,
       ol.outcome_desc,
       COUNT(cc.patient_id) AS patients,
       ROUND(100.0 * COUNT(cc.patient_id) /
             (SELECT COUNT(*) FROM covid_case
              WHERE diagnosis IN ('confirmed','suspected')), 1) AS pct_of_cohort
FROM outcome_level ol
LEFT JOIN covid_case cc
       ON cc.outcome_level_id = ol.outcome_level_id
      AND cc.diagnosis IN ('confirmed','suspected')
GROUP BY ol.outcome_level_id, ol.outcome_desc
ORDER BY ol.outcome_level_id;


-- ---------------------------------------------------------------------
-- Q7. How does the hospitalisation rate change with age group in the
--     COVID-19 cohort?
-- ---------------------------------------------------------------------
SELECT ag.age_range,
       COUNT(*)                                                        AS cohort_patients,
       SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)                AS hospitalised,
       ROUND(100.0 * SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)
                   / COUNT(*), 1)                                      AS hosp_rate_pct
FROM covid_case cc
JOIN patient   p  ON p.patient_id    = cc.patient_id
JOIN age_group ag ON ag.age_group_id = p.age_group_id
WHERE cc.diagnosis IN ('confirmed','suspected')
GROUP BY ag.age_group_id, ag.age_range
ORDER BY ag.age_group_id;


-- ---------------------------------------------------------------------
-- Q8. How do confirmed cases, hospitalisations and ICU stays compare across
--     sex and age group?
-- ---------------------------------------------------------------------
SELECT INITCAP(p.sex)                                                  AS sex,
       ag.age_range,
       COUNT(*)                                                        AS cohort_patients,
       SUM(CASE WHEN cc.diagnosis = 'confirmed' THEN 1 ELSE 0 END)     AS confirmed_cases,
       SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)                AS hospitalised,
       SUM(CASE WHEN cc.icu_stay THEN 1 ELSE 0 END)                    AS icu_cases,
       ROUND(100.0 * SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)
                   / COUNT(*), 1)                                      AS hosp_rate_pct,
       ROUND(100.0 * SUM(CASE WHEN cc.icu_stay THEN 1 ELSE 0 END)
                   / COUNT(*), 1)                                      AS icu_rate_pct
FROM patient p
JOIN covid_case cc ON cc.patient_id   = p.patient_id
JOIN age_group  ag ON ag.age_group_id = p.age_group_id
WHERE cc.diagnosis IN ('confirmed','suspected')
GROUP BY p.sex, ag.age_group_id, ag.age_range
ORDER BY p.sex, ag.age_group_id;


-- ---------------------------------------------------------------------
-- Q9. What are the hospitalisation counts, rates and ICU cases by MS type?
-- ---------------------------------------------------------------------
SELECT CASE p.ms_type WHEN 'progressive_ms' THEN 'Progressive MS'
            ELSE INITCAP(REPLACE(p.ms_type, '_', ' ')) END             AS ms_type,
       COUNT(*)                                                        AS cohort_patients,
       SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)                AS hospitalised,
       ROUND(100.0 * SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)
                   / COUNT(*), 1)                                      AS hosp_rate_pct,
       SUM(CASE WHEN cc.icu_stay THEN 1 ELSE 0 END)                    AS icu_cases
FROM patient p
JOIN covid_case cc ON cc.patient_id = p.patient_id
WHERE cc.diagnosis IN ('confirmed','suspected')
GROUP BY p.ms_type
ORDER BY cohort_patients DESC;


-- ---------------------------------------------------------------------
-- Q10. What is the average number of symptoms reported per BMI category?
-- ---------------------------------------------------------------------
SELECT COALESCE(INITCAP(REPLACE(p.bmi_category, '_', ' ')), 'Not reported') AS bmi_category,
       COUNT(*)                                                        AS cohort_patients,
       ROUND(AVG(COALESCE(sc.symptom_count, 0)), 2)                    AS avg_symptoms
FROM patient p
JOIN covid_case cc ON cc.patient_id = p.patient_id
LEFT JOIN (SELECT patient_id, COUNT(*) AS symptom_count
           FROM patient_symptom
           WHERE present
           GROUP BY patient_id) sc ON sc.patient_id = p.patient_id
WHERE cc.diagnosis IN ('confirmed','suspected')
GROUP BY p.bmi_category
ORDER BY avg_symptoms DESC;


-- ---------------------------------------------------------------------
-- Q11. How many patients use each named DMT drug?
-- ---------------------------------------------------------------------
SELECT INITCAP(REPLACE(d.dmt_name, '_', ' '))                          AS dmt_drug,
       d.dmt_class,
       COUNT(p.patient_id)                                             AS patients,
       ROUND(100.0 * COUNT(p.patient_id) / (SELECT COUNT(*) FROM patient), 1) AS pct_of_patients
FROM dmt_drug d
LEFT JOIN patient p ON p.dmt_id = d.dmt_id
GROUP BY d.dmt_id, d.dmt_name, d.dmt_class
ORDER BY patients DESC, dmt_drug;


-- ---------------------------------------------------------------------
-- Q12. Do people currently on a DMT have a different hospitalisation rate
--      from those not on one or never treated?
-- ---------------------------------------------------------------------
SELECT CASE p.current_dmt_status
            WHEN 'yes'           THEN 'On a DMT'
            WHEN 'no'            THEN 'Not currently on a DMT'
            WHEN 'never_treated' THEN 'Never treated'
       END                                                             AS treatment_group,
       COUNT(*)                                                        AS cohort_patients,
       SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)                AS hospitalised,
       ROUND(100.0 * SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)
                   / COUNT(*), 1)                                      AS hosp_rate_pct
FROM patient p
JOIN covid_case cc ON cc.patient_id = p.patient_id
WHERE cc.diagnosis IN ('confirmed','suspected')
GROUP BY p.current_dmt_status
ORDER BY hosp_rate_pct DESC;


-- ---------------------------------------------------------------------
-- Q13. Which classes of MS drug are linked to higher or lower hospitalisation
--      and ICU rates among people currently on a DMT?
-- ---------------------------------------------------------------------
SELECT d.dmt_class,
       COUNT(*)                                                        AS cohort_patients,
       SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)                AS hospitalised,
       ROUND(100.0 * SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)
                   / COUNT(*), 1)                                      AS hosp_rate_pct,
       SUM(CASE WHEN cc.icu_stay THEN 1 ELSE 0 END)                    AS icu_cases,
       ROUND(100.0 * SUM(CASE WHEN cc.icu_stay THEN 1 ELSE 0 END)
                   / COUNT(*), 1)                                      AS icu_rate_pct
FROM patient p
JOIN covid_case cc ON cc.patient_id = p.patient_id
JOIN dmt_drug   d  ON d.dmt_id      = p.dmt_id
WHERE cc.diagnosis IN ('confirmed','suspected')
  AND d.dmt_name NOT IN ('none','never_treated')
GROUP BY d.dmt_class
HAVING COUNT(*) >= 10
ORDER BY hosp_rate_pct DESC, cohort_patients DESC;


-- ---------------------------------------------------------------------
-- Q14. What are the hospitalisation, ICU and ventilation counts by
--      glucocorticoid (steroid) use?
-- ---------------------------------------------------------------------
SELECT CASE WHEN p.on_glucocorticoid     THEN 'On glucocorticoid'
            WHEN NOT p.on_glucocorticoid THEN 'Not on glucocorticoid'
            ELSE 'Not reported' END                                    AS steroid_group,
       COUNT(*)                                                        AS cohort_patients,
       SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)                AS hospitalised,
       SUM(CASE WHEN cc.icu_stay THEN 1 ELSE 0 END)                    AS icu_cases,
       SUM(CASE WHEN cc.ventilated THEN 1 ELSE 0 END)                  AS ventilated
FROM patient p
JOIN covid_case cc ON cc.patient_id = p.patient_id
WHERE cc.diagnosis IN ('confirmed','suspected')
GROUP BY p.on_glucocorticoid
ORDER BY cohort_patients DESC;


-- ---------------------------------------------------------------------
-- Q15. Does steroid use relate to severity differently across MS types?
-- ---------------------------------------------------------------------
SELECT CASE p.ms_type WHEN 'progressive_ms' THEN 'Progressive MS'
            ELSE INITCAP(REPLACE(p.ms_type, '_', ' ')) END             AS ms_type,
       CASE WHEN p.on_glucocorticoid     THEN 'On glucocorticoid'
            WHEN NOT p.on_glucocorticoid THEN 'Not on glucocorticoid'
            ELSE 'Not reported' END                                    AS steroid_group,
       COUNT(*)                                                        AS cohort_patients,
       SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)                AS hospitalised,
       SUM(CASE WHEN cc.outcome_level_id = 2 THEN 1 ELSE 0 END)        AS severe_cases
FROM patient p
JOIN covid_case cc ON cc.patient_id = p.patient_id
WHERE cc.diagnosis IN ('confirmed','suspected')
GROUP BY p.ms_type, p.on_glucocorticoid
ORDER BY p.ms_type, p.on_glucocorticoid;


-- ---------------------------------------------------------------------
-- Q16. Do people with comorbidities have a higher hospitalisation rate?
-- ---------------------------------------------------------------------
SELECT CASE WHEN p.has_comorbidities     THEN 'With comorbidity'
            WHEN NOT p.has_comorbidities THEN 'No comorbidity'
       END                                                             AS comorbidity_group,
       COUNT(*)                                                        AS cohort_patients,
       SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)                AS hospitalised,
       ROUND(100.0 * SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)
                   / COUNT(*), 1)                                      AS hosp_rate_pct
FROM patient p
JOIN covid_case cc ON cc.patient_id = p.patient_id
WHERE cc.diagnosis IN ('confirmed','suspected')
GROUP BY p.has_comorbidities
ORDER BY hosp_rate_pct DESC;


-- ---------------------------------------------------------------------
-- Q17. Which individual comorbidities carry the highest hospitalisation and
--      ICU risk?
-- ---------------------------------------------------------------------
SELECT INITCAP(REPLACE(m.comorbidity_name, '_', ' '))                  AS comorbidity,
       COUNT(*)                                                        AS cohort_patients_with_condition,
       SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)                AS hospitalised,
       ROUND(100.0 * SUM(CASE WHEN cc.hospitalised THEN 1 ELSE 0 END)
                   / COUNT(*), 1)                                      AS hosp_rate_pct,
       SUM(CASE WHEN cc.icu_stay THEN 1 ELSE 0 END)                    AS icu_cases
FROM patient_comorbidity pc
JOIN comorbidity m  ON m.comorbidity_id = pc.comorbidity_id
JOIN covid_case  cc ON cc.patient_id    = pc.patient_id
WHERE pc.present
  AND cc.diagnosis IN ('confirmed','suspected')
GROUP BY m.comorbidity_name
HAVING COUNT(*) >= 3
ORDER BY hosp_rate_pct DESC, cohort_patients_with_condition DESC;


-- ---------------------------------------------------------------------
-- Q18. Do current or former smokers report breathing-related symptoms more
--      often than non-smokers?
-- ---------------------------------------------------------------------
SELECT INITCAP(REPLACE(s.symptom_name, '_', ' '))                      AS symptom,
       CASE WHEN p.smoker THEN 'Current or former smoker'
            ELSE 'Non-smoker' END                                      AS smoking_group,
       COUNT(*)                                                        AS people_asked,
       SUM(CASE WHEN ps.present THEN 1 ELSE 0 END)                     AS reported_yes,
       ROUND(100.0 * SUM(CASE WHEN ps.present THEN 1 ELSE 0 END)
                   / COUNT(*), 1)                                      AS pct_yes
FROM patient p
JOIN covid_case      cc ON cc.patient_id = p.patient_id
JOIN patient_symptom ps ON ps.patient_id = p.patient_id
JOIN symptom         s  ON s.symptom_id  = ps.symptom_id
WHERE cc.diagnosis IN ('confirmed','suspected')
  AND s.symptom_name IN ('dry_cough','shortness_breath','pneumonia')
GROUP BY s.symptom_name, p.smoker
ORDER BY s.symptom_name, p.smoker DESC;


-- ---------------------------------------------------------------------
-- Q19. What are the top 5 most common symptoms in confirmed COVID-19 cases?
-- ---------------------------------------------------------------------
SELECT INITCAP(REPLACE(s.symptom_name, '_', ' '))                      AS symptom,
       COUNT(*)                                                        AS confirmed_cases_with_symptom,
       ROUND(100.0 * COUNT(*) /
             (SELECT COUNT(*) FROM covid_case WHERE diagnosis = 'confirmed'), 1) AS pct_of_confirmed
FROM patient_symptom ps
JOIN symptom    s  ON s.symptom_id  = ps.symptom_id
JOIN covid_case cc ON cc.patient_id = ps.patient_id
WHERE cc.diagnosis = 'confirmed'
  AND ps.present
GROUP BY s.symptom_name
ORDER BY confirmed_cases_with_symptom DESC, symptom
LIMIT 5;


-- ---------------------------------------------------------------------
-- Q20. Who were the most severe cases (ICU and/or ventilation)?
-- ---------------------------------------------------------------------
SELECT p.patient_id,
       ag.age_range,
       INITCAP(p.sex)                                   AS sex,
       CASE p.ms_type WHEN 'progressive_ms' THEN 'Progressive MS'
            ELSE INITCAP(REPLACE(p.ms_type, '_', ' ')) END AS ms_type,
       p.bmi_category,
       COALESCE(d.dmt_name, 'unknown')                  AS dmt,
       p.has_comorbidities,
       cc.diagnosis,
       cc.icu_stay,
       cc.ventilated
FROM covid_case cc
JOIN patient   p  ON p.patient_id    = cc.patient_id
JOIN age_group ag ON ag.age_group_id = p.age_group_id
LEFT JOIN dmt_drug d ON d.dmt_id     = p.dmt_id
WHERE cc.outcome_level_id = 2
ORDER BY ag.age_group_id DESC, p.patient_id;