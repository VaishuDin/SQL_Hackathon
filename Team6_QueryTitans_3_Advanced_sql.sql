-- ============================================================================

--  TEAM 6 - QUERY TITANS

-- ============================================================================

--  CATEGORY 3 : ADVANCED  

-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. Label every drug class as higher, similar or lower than the cohort's
--     overall hospitalisation rate, and refuse to label small groups.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_risk_band(p_hosp bigint, p_n bigint, p_baseline_pct numeric)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
             WHEN p_n < 10                                      THEN 'Insufficient data (n<10)'
             WHEN 100.0 * p_hosp / p_n >= p_baseline_pct * 1.25 THEN 'Higher than cohort'
             WHEN 100.0 * p_hosp / p_n <= p_baseline_pct * 0.75 THEN 'Lower than cohort'
             ELSE 'Similar to cohort'
           END
$$;

WITH base AS (
    SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE hospitalised) / COUNT(*), 2) AS cohort_rate
    FROM v_covid_cohort
)
SELECT v.dmt_class,
       COUNT(*)                                                         AS cohort_patients,
       COUNT(*) FILTER (WHERE v.hospitalised)                           AS hospitalised,
       ROUND(100.0 * COUNT(*) FILTER (WHERE v.hospitalised) / COUNT(*), 1) AS hosp_rate_pct,
       b.cohort_rate                                                    AS baseline_pct,
       fn_risk_band(COUNT(*) FILTER (WHERE v.hospitalised), COUNT(*), b.cohort_rate)
                                                                        AS risk_band
FROM v_covid_cohort v
CROSS JOIN base b
WHERE v.dmt_class IS NOT NULL
GROUP BY v.dmt_class, b.cohort_rate
ORDER BY hosp_rate_pct DESC;


-- ---------------------------------------------------------------------
-- Q2. Give me hospitalisation counts and rates for ANY patient
--     characteristic (sex, age, MS type, BMI, drug class, report source)
--     with one function call.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_cohort_rates(p_dimension text)
RETURNS TABLE (group_label text, cohort_patients bigint, hospitalised bigint, hosp_rate_pct numeric)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF NOT (p_dimension = ANY (ARRAY['sex','age_range','ms_type','bmi_category',
                                     'dmt_class','report_source'])) THEN
        RAISE EXCEPTION 'Unsupported dimension "%". Use sex, age_range, ms_type, bmi_category, dmt_class or report_source.',
                        p_dimension;
    END IF;

    RETURN QUERY EXECUTE format(
        'SELECT COALESCE(%I::text, ''unknown''),
                COUNT(*),
                COUNT(*) FILTER (WHERE hospitalised),
                ROUND(100.0 * COUNT(*) FILTER (WHERE hospitalised) / COUNT(*), 1)
         FROM v_covid_cohort
         GROUP BY 1
         ORDER BY 1', p_dimension);
END
$$;

SELECT 'sex' AS dimension, * FROM fn_cohort_rates('sex')
UNION ALL
SELECT 'age_range',     * FROM fn_cohort_rates('age_range')
UNION ALL
SELECT 'ms_type',       * FROM fn_cohort_rates('ms_type')
UNION ALL
SELECT 'report_source', * FROM fn_cohort_rates('report_source');


-- ---------------------------------------------------------------------
-- Q3. Which patient characteristics are associated with hospitalisation,
--     measured as an odds ratio with a 95% confidence interval?
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_odds_ratio(exp_hosp bigint, exp_n bigint,
                                         ref_hosp bigint, ref_n bigint)
RETURNS TABLE (odds_ratio numeric, ci_low numeric, ci_high numeric)
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    a numeric := exp_hosp;               -- exposed, hospitalised
    b numeric := exp_n - exp_hosp;       -- exposed, not hospitalised
    c numeric := ref_hosp;               -- reference, hospitalised
    d numeric := ref_n - ref_hosp;       -- reference, not hospitalised
    v_se numeric;
    v_or numeric;
BEGIN
    IF a = 0 OR b = 0 OR c = 0 OR d = 0 THEN
        a := a + 0.5;  b := b + 0.5;  c := c + 0.5;  d := d + 0.5;
    END IF;

    v_or := (a * d) / (b * c);
    v_se := SQRT(1/a + 1/b + 1/c + 1/d);

    RETURN QUERY
    SELECT ROUND(v_or, 2),
           ROUND(EXP(LN(v_or) - 1.96 * v_se), 2),
           ROUND(EXP(LN(v_or) + 1.96 * v_se), 2);
END
$$;

WITH f AS (
    SELECT 'Has a comorbidity (vs none)' AS factor,
           COUNT(*) FILTER (WHERE has_comorbidities)                      AS exp_n,
           COUNT(*) FILTER (WHERE has_comorbidities AND hospitalised)     AS exp_hosp,
           COUNT(*) FILTER (WHERE NOT has_comorbidities)                  AS ref_n,
           COUNT(*) FILTER (WHERE NOT has_comorbidities AND hospitalised) AS ref_hosp
    FROM v_covid_cohort
    UNION ALL
    SELECT 'Age 51-70 (vs 18-50)',
           COUNT(*) FILTER (WHERE age_range = '51-70'),
           COUNT(*) FILTER (WHERE age_range = '51-70' AND hospitalised),
           COUNT(*) FILTER (WHERE age_range = '18-50'),
           COUNT(*) FILTER (WHERE age_range = '18-50' AND hospitalised)
    FROM v_covid_cohort
    UNION ALL
    SELECT 'Male (vs female)',
           COUNT(*) FILTER (WHERE sex = 'male'),
           COUNT(*) FILTER (WHERE sex = 'male' AND hospitalised),
           COUNT(*) FILTER (WHERE sex = 'female'),
           COUNT(*) FILTER (WHERE sex = 'female' AND hospitalised)
    FROM v_covid_cohort
    UNION ALL
    SELECT 'Currently on a DMT (vs not)',
           COUNT(*) FILTER (WHERE current_dmt_status = 'yes'),
           COUNT(*) FILTER (WHERE current_dmt_status = 'yes' AND hospitalised),
           COUNT(*) FILTER (WHERE current_dmt_status <> 'yes'),
           COUNT(*) FILTER (WHERE current_dmt_status <> 'yes' AND hospitalised)
    FROM v_covid_cohort
    UNION ALL
    SELECT 'Clinician-reported (vs patient-reported)',
           COUNT(*) FILTER (WHERE report_source = 'clinicians'),
           COUNT(*) FILTER (WHERE report_source = 'clinicians' AND hospitalised),
           COUNT(*) FILTER (WHERE report_source = 'patients'),
           COUNT(*) FILTER (WHERE report_source = 'patients' AND hospitalised)
    FROM v_covid_cohort
)
SELECT f.factor,
       f.exp_n, f.exp_hosp, f.ref_n, f.ref_hosp,
       o.odds_ratio, o.ci_low, o.ci_high,
       CASE WHEN o.ci_low > 1 OR o.ci_high < 1 THEN 'Yes' ELSE 'No' END AS interval_excludes_1
FROM f
CROSS JOIN LATERAL fn_odds_ratio(f.exp_hosp, f.exp_n, f.ref_hosp, f.ref_n) o
ORDER BY o.odds_ratio DESC;


-- ---------------------------------------------------------------------
-- Q4. Produce a complete one-patient case summary as a single JSON document.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_patient_profile(p_patient_id text)
RETURNS jsonb
LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'patient_id',    p.patient_id,
        'report_source', p.report_source,
        'sex',           p.sex,
        'age_range',     ag.age_range,
        'ms_type',       p.ms_type,
        'dmt',           COALESCE(d.dmt_name, 'unknown'),
        'diagnosis',     cc.diagnosis,
        'outcome',       ol.outcome_desc,
        'symptoms',      COALESCE((SELECT jsonb_agg(s.symptom_name ORDER BY s.symptom_name)
                                   FROM patient_symptom ps
                                   JOIN symptom s ON s.symptom_id = ps.symptom_id
                                   WHERE ps.patient_id = p.patient_id AND ps.present),
                                  '[]'::jsonb),
        'comorbidities', COALESCE((SELECT jsonb_agg(m.comorbidity_name ORDER BY m.comorbidity_name)
                                   FROM patient_comorbidity pc
                                   JOIN comorbidity m ON m.comorbidity_id = pc.comorbidity_id
                                   WHERE pc.patient_id = p.patient_id AND pc.present),
                                  '[]'::jsonb)
    )
    FROM patient p
    JOIN covid_case    cc ON cc.patient_id       = p.patient_id
    JOIN age_group     ag ON ag.age_group_id     = p.age_group_id
    JOIN outcome_level ol ON ol.outcome_level_id = cc.outcome_level_id
    LEFT JOIN dmt_drug d  ON d.dmt_id            = p.dmt_id
    WHERE p.patient_id = p_patient_id
$$;

SELECT jsonb_pretty(
           fn_patient_profile(
               (SELECT MIN(patient_id) FROM covid_case WHERE outcome_level_id = 2))
       ) AS most_severe_case_profile;


-- ---------------------------------------------------------------------
-- Q5. What is each patient's observed severity category, and how many patients fall in each?
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_severity_category(p_hospitalised boolean,
                                                p_icu          boolean,
                                                p_ventilated   boolean)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
             WHEN p_icu IS TRUE OR p_ventilated IS TRUE THEN 'ICU and/or ventilation'
             WHEN p_hospitalised IS TRUE                THEN 'Hospitalised'
             WHEN p_hospitalised IS FALSE AND p_icu IS FALSE AND p_ventilated IS FALSE
                                                        THEN 'Not hospitalised'
             ELSE 'Unknown or inconsistent'
           END
$$;

-- 1) category counts
WITH labelled AS (
    SELECT cc.patient_id,
           cc.diagnosis,
           fn_severity_category(cc.hospitalised, cc.icu_stay, cc.ventilated) AS severity_category
    FROM covid_case cc
)
SELECT severity_category,
       COUNT(*)                                                         AS all_patients,
       COUNT(*) FILTER (WHERE diagnosis IN ('confirmed','suspected'))   AS cohort_patients,
       ROUND(100.0 * COUNT(*) FILTER (WHERE diagnosis IN ('confirmed','suspected'))
                   / SUM(COUNT(*) FILTER (WHERE diagnosis IN ('confirmed','suspected'))) OVER (), 1)
                                                                        AS pct_of_cohort
FROM labelled
GROUP BY severity_category
ORDER BY CASE severity_category
              WHEN 'ICU and/or ventilation'   THEN 1
              WHEN 'Hospitalised'             THEN 2
              WHEN 'Not hospitalised'         THEN 3
              ELSE 4 END;

-- 2) per-patient listing (run separately): the five most severe patients
SELECT patient_id,
       fn_severity_category(hospitalised, icu_stay, ventilated) AS severity_category
FROM covid_case
WHERE outcome_level_id = 2
ORDER BY patient_id;


-- ---------------------------------------------------------------------
-- Q6. Which symptom pairs, and which comorbidity pairs, occur together most often in the COVID-19 cohort?
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_cooccurring_pairs(p_kind text, p_min_patients integer DEFAULT 5)
RETURNS TABLE (item_a text, item_b text, patients_with_both bigint, pct_of_cohort numeric)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_cohort bigint;
BEGIN
    SELECT COUNT(*) INTO v_cohort
    FROM covid_case
    WHERE diagnosis IN ('confirmed','suspected');

    IF p_kind = 'symptom' THEN
        RETURN QUERY
        SELECT s1.symptom_name, s2.symptom_name, COUNT(*),
               ROUND(100.0 * COUNT(*) / v_cohort, 1)
        FROM patient_symptom a
        JOIN patient_symptom b ON b.patient_id = a.patient_id AND a.symptom_id < b.symptom_id
        JOIN symptom s1 ON s1.symptom_id = a.symptom_id
        JOIN symptom s2 ON s2.symptom_id = b.symptom_id
        JOIN covid_case cc ON cc.patient_id = a.patient_id
        WHERE a.present AND b.present
          AND cc.diagnosis IN ('confirmed','suspected')
        GROUP BY s1.symptom_name, s2.symptom_name
        HAVING COUNT(*) >= p_min_patients
        ORDER BY 3 DESC, 1, 2;

    ELSIF p_kind = 'comorbidity' THEN
        RETURN QUERY
        SELECT m1.comorbidity_name, m2.comorbidity_name, COUNT(*),
               ROUND(100.0 * COUNT(*) / v_cohort, 1)
        FROM patient_comorbidity a
        JOIN patient_comorbidity b ON b.patient_id = a.patient_id AND a.comorbidity_id < b.comorbidity_id
        JOIN comorbidity m1 ON m1.comorbidity_id = a.comorbidity_id
        JOIN comorbidity m2 ON m2.comorbidity_id = b.comorbidity_id
        JOIN covid_case cc ON cc.patient_id = a.patient_id
        WHERE a.present AND b.present
          AND cc.diagnosis IN ('confirmed','suspected')
        GROUP BY m1.comorbidity_name, m2.comorbidity_name
        HAVING COUNT(*) >= p_min_patients
        ORDER BY 3 DESC, 1, 2;

    ELSE
        RAISE EXCEPTION 'Unsupported kind "%". Use symptom or comorbidity.', p_kind;
    END IF;
END
$$;

(SELECT 'Symptom' AS pair_type,
        INITCAP(REPLACE(item_a, '_', ' ')) AS item_a,
        INITCAP(REPLACE(item_b, '_', ' ')) AS item_b,
        patients_with_both,
        pct_of_cohort
 FROM fn_cooccurring_pairs('symptom', 1)
 LIMIT 5)
UNION ALL
(SELECT 'Comorbidity',
        INITCAP(REPLACE(item_a, '_', ' ')),
        INITCAP(REPLACE(item_b, '_', ' ')),
        patients_with_both,
        pct_of_cohort
 FROM fn_cooccurring_pairs('comorbidity', 1)
 LIMIT 5);


-- ---------------------------------------------------------------------
-- Q7. Refresh a ready-to-report summary table with one command.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rpt_outcome_summary (
    dimension       text,
    group_label     text,
    cohort_patients bigint,
    hospitalised    bigint,
    hosp_rate_pct   numeric,
    refreshed_at    timestamptz DEFAULT now()
);

CREATE OR REPLACE PROCEDURE sp_refresh_outcome_summary()
LANGUAGE plpgsql AS $$
DECLARE
    v_dim  text;
    v_rows integer;
BEGIN
    TRUNCATE rpt_outcome_summary;

    FOREACH v_dim IN ARRAY ARRAY['sex','age_range','ms_type','bmi_category',
                                 'dmt_class','report_source'] LOOP
        INSERT INTO rpt_outcome_summary (dimension, group_label, cohort_patients,
                                         hospitalised, hosp_rate_pct)
        SELECT v_dim, group_label, cohort_patients, hospitalised, hosp_rate_pct
        FROM fn_cohort_rates(v_dim);
    END LOOP;

    SELECT COUNT(*) INTO v_rows FROM rpt_outcome_summary;
    RAISE NOTICE 'rpt_outcome_summary refreshed: % rows', v_rows;
END
$$;

CALL sp_refresh_outcome_summary();

SELECT dimension, group_label, cohort_patients, hospitalised, hosp_rate_pct
FROM rpt_outcome_summary
ORDER BY dimension, hosp_rate_pct DESC;


-- ---------------------------------------------------------------------
-- Q8. Run a repeatable set of data-quality checks and keep a history of the
--     results.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dq_issue_log (
    log_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_at      timestamptz NOT NULL,
    check_name  text        NOT NULL,
    issue_count bigint      NOT NULL
);

CREATE OR REPLACE PROCEDURE sp_run_data_quality_checks()
LANGUAGE plpgsql AS $$
DECLARE
    v_run   timestamptz := clock_timestamp();
    v_total bigint;
BEGIN
    INSERT INTO dq_issue_log (run_at, check_name, issue_count)
    SELECT v_run, '1. Hospitalised but diagnosis is not_suspected', COUNT(*)
    FROM covid_case
    WHERE hospitalised AND diagnosis = 'not_suspected'
    UNION ALL
    SELECT v_run, '2. ICU or ventilation without hospital admission', COUNT(*)
    FROM covid_case
    WHERE (icu_stay IS TRUE OR ventilated IS TRUE) AND hospitalised IS NOT TRUE
    UNION ALL
    SELECT v_run, '3. "No symptoms" but a symptom is yes', COUNT(DISTINCT cc.patient_id)
    FROM covid_case cc
    JOIN patient_symptom ps ON ps.patient_id = cc.patient_id
    WHERE cc.has_symptoms = false AND ps.present
    UNION ALL
    SELECT v_run, '4. Comorbidity flag yes but no condition listed', COUNT(*)
    FROM patient p
    WHERE p.has_comorbidities
      AND NOT EXISTS (SELECT 1
                      FROM patient_comorbidity pc
                      WHERE pc.patient_id = p.patient_id AND pc.present)
    UNION ALL
    SELECT v_run, '5. Pregnancy recorded for a male', COUNT(*)
    FROM patient
    WHERE sex = 'male' AND pregnancy
    UNION ALL
    SELECT v_run, '6. Stop/end date year before MS onset year', COUNT(*)
    FROM patient
    WHERE stop_or_end_date IS NOT NULL
      AND ms_onset_year IS NOT NULL
      AND EXTRACT(YEAR FROM stop_or_end_date) < ms_onset_year;

    SELECT SUM(issue_count) INTO v_total FROM dq_issue_log WHERE run_at = v_run;
    RAISE NOTICE 'Data-quality run finished: % issues found across 6 checks', v_total;
END
$$;

CALL sp_run_data_quality_checks();

SELECT check_name, issue_count,
       TO_CHAR(run_at, 'YYYY-MM-DD HH24:MI:SS') AS run_at
FROM dq_issue_log
WHERE run_at = (SELECT MAX(run_at) FROM dq_issue_log)
ORDER BY check_name;


-- ---------------------------------------------------------------------
-- Q9. Cross-tab: for each drug class, how many cohort patients reached each
--     outcome level, shown as columns?
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS tablefunc;

SELECT dmt_class,
       COALESCE(not_hospitalised, 0)  AS not_hospitalised,
       COALESCE(hospitalised, 0)      AS hospitalised,
       COALESCE(icu_or_ventilation, 0) AS icu_or_ventilation,
       COALESCE(not_hospitalised, 0) + COALESCE(hospitalised, 0)
         + COALESCE(icu_or_ventilation, 0) AS total
FROM crosstab(
    $$ SELECT COALESCE(dmt_class, 'Unknown'),
              outcome_level_id::int,
              COUNT(*)
       FROM v_covid_cohort
       GROUP BY 1, 2
       ORDER BY 1, 2 $$,
    $$ VALUES (0), (1), (2) $$
) AS ct (dmt_class text,
         not_hospitalised bigint,
         hospitalised bigint,
         icu_or_ventilation bigint)
ORDER BY dmt_class;


-- ---------------------------------------------------------------------
-- Q10. How many cohort patients reached each outcome level, for each comorbidity?
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS tablefunc;

SELECT comorbidity,
       COALESCE(not_hospitalised, 0)   AS not_hospitalised,
       COALESCE(hospitalised, 0)       AS hospitalised,
       COALESCE(icu_or_ventilation, 0) AS icu_or_ventilation,
       COALESCE(not_hospitalised, 0) + COALESCE(hospitalised, 0)
         + COALESCE(icu_or_ventilation, 0) AS patients_with_condition
FROM crosstab(
    $$ SELECT INITCAP(REPLACE(m.comorbidity_name, '_', ' ')),
              cc.outcome_level_id::int,
              COUNT(*)
       FROM patient_comorbidity pc
       JOIN comorbidity m  ON m.comorbidity_id = pc.comorbidity_id
       JOIN covid_case  cc ON cc.patient_id    = pc.patient_id
       WHERE pc.present
         AND cc.diagnosis IN ('confirmed','suspected')
       GROUP BY 1, 2
       ORDER BY 1, 2 $$,
    $$ VALUES (0), (1), (2) $$
) AS ct (comorbidity text,
         not_hospitalised bigint,
         hospitalised bigint,
         icu_or_ventilation bigint)
ORDER BY patients_with_condition DESC, comorbidity;


-- ---------------------------------------------------------------------
-- Q11. Show hospitalisation as a tree: all DMTs -> route of administration ->
--     individual drug, with every level rolled up from the drugs below it.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS dmt_hierarchy CASCADE;

CREATE TABLE dmt_hierarchy (
    node_id   smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_id smallint REFERENCES dmt_hierarchy(node_id),
    node_name text NOT NULL,
    dmt_id    smallint REFERENCES dmt_drug(dmt_id)      -- only filled for leaf (drug) nodes
);
CREATE INDEX idx_dmt_hierarchy_parent ON dmt_hierarchy(parent_id);

INSERT INTO dmt_hierarchy (node_name) VALUES ('All DMTs');

INSERT INTO dmt_hierarchy (parent_id, node_name)
SELECT (SELECT node_id FROM dmt_hierarchy WHERE node_name = 'All DMTs'), r.route
FROM (VALUES ('Injectable'), ('Oral'), ('Infusion'), ('Other')) AS r(route);

INSERT INTO dmt_hierarchy (parent_id, node_name, dmt_id)
SELECT rt.node_id, INITCAP(d.dmt_name), d.dmt_id
FROM (VALUES ('interferon','Injectable'), ('glatiramer','Injectable'),
             ('dimethyl fumarate','Oral'), ('teriflunomide','Oral'),
             ('fingolimod','Oral'), ('cladribine','Oral'),
             ('natalizumab','Infusion'), ('ocrelizumab','Infusion'),
             ('rituximab','Infusion'), ('alemtuzumab','Infusion'),
             ('another drug not listed','Other')) AS m(drug, route)
JOIN dmt_drug      d  ON d.dmt_name  = m.drug
JOIN dmt_hierarchy rt ON rt.node_name = m.route;

WITH RECURSIVE
tree AS (                                         -- top-down: depth and display order
    SELECT node_id, parent_id, node_name, 0 AS depth, node_name::text AS sort_path
    FROM dmt_hierarchy
    WHERE parent_id IS NULL
    UNION ALL
    SELECT h.node_id, h.parent_id, h.node_name, t.depth + 1,
           t.sort_path || ' > ' || h.node_name
    FROM dmt_hierarchy h
    JOIN tree t ON h.parent_id = t.node_id
),
closure AS (                                      -- bottom-up: each drug with all its ancestors
    SELECT node_id AS leaf_node, node_id AS ancestor_node, parent_id
    FROM dmt_hierarchy
    WHERE dmt_id IS NOT NULL
    UNION ALL
    SELECT c.leaf_node, h.node_id, h.parent_id
    FROM closure c
    JOIN dmt_hierarchy h ON h.node_id = c.parent_id
),
leaf_stats AS (                                   -- facts per drug
    SELECT h.node_id AS leaf_node,
           COUNT(*)                                AS n,
           COUNT(*) FILTER (WHERE cc.hospitalised) AS hosp
    FROM dmt_hierarchy h
    JOIN patient    p  ON p.dmt_id     = h.dmt_id
    JOIN covid_case cc ON cc.patient_id = p.patient_id
    WHERE cc.diagnosis IN ('confirmed','suspected')
    GROUP BY h.node_id
)
SELECT REPEAT('    ', t.depth) || t.node_name                          AS dmt_tree,
       SUM(ls.n)                                                       AS cohort_patients,
       SUM(ls.hosp)                                                    AS hospitalised,
       ROUND(100.0 * SUM(ls.hosp) / NULLIF(SUM(ls.n), 0), 1)           AS hosp_rate_pct
FROM tree t
JOIN closure    c  ON c.ancestor_node = t.node_id
JOIN leaf_stats ls ON ls.leaf_node    = c.leaf_node
GROUP BY t.node_id, t.depth, t.node_name, t.sort_path
ORDER BY t.sort_path;


-- ---------------------------------------------------------------------
-- Q12. Automatically record who changed a patient's hospitalisation or
--     outcome, and when (audit trigger).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS covid_case_audit (
    audit_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id        text        NOT NULL,
    changed_at        timestamptz NOT NULL DEFAULT now(),
    changed_by        text        NOT NULL DEFAULT current_user,
    old_hospitalised  boolean,
    new_hospitalised  boolean,
    old_outcome_level smallint,
    new_outcome_level smallint
);

CREATE OR REPLACE FUNCTION fn_audit_covid_case()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.hospitalised     IS DISTINCT FROM OLD.hospitalised
    OR NEW.outcome_level_id IS DISTINCT FROM OLD.outcome_level_id THEN
        INSERT INTO covid_case_audit (patient_id, old_hospitalised, new_hospitalised,
                                      old_outcome_level, new_outcome_level)
        VALUES (NEW.patient_id, OLD.hospitalised, NEW.hospitalised,
                OLD.outcome_level_id, NEW.outcome_level_id);
    END IF;
    RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS tr_covid_case_audit ON covid_case;
CREATE TRIGGER tr_covid_case_audit
    AFTER UPDATE ON covid_case
    FOR EACH ROW EXECUTE FUNCTION fn_audit_covid_case();

-- test: change one patient, then restore the original value
DO $$
DECLARE
    v_id text;
BEGIN
    SELECT MIN(patient_id) INTO v_id
    FROM covid_case
    WHERE diagnosis = 'suspected' AND NOT hospitalised;

    UPDATE covid_case SET hospitalised = true  WHERE patient_id = v_id;
    UPDATE covid_case SET hospitalised = false WHERE patient_id = v_id;
    RAISE NOTICE 'Test patient: %', v_id;
END
$$;

SELECT audit_id, patient_id, changed_by, old_hospitalised, new_hospitalised,
       TO_CHAR(changed_at, 'YYYY-MM-DD HH24:MI:SS') AS changed_at
FROM covid_case_audit
ORDER BY audit_id;


-- ---------------------------------------------------------------------
-- Q13. Block impossible data from entering the cases table (validation trigger).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validate_covid_case()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF (NEW.icu_stay IS TRUE OR NEW.ventilated IS TRUE)
       AND NEW.hospitalised IS NOT TRUE THEN
        RAISE EXCEPTION 'Invalid case %: ICU/ventilation recorded without hospital admission',
                        NEW.patient_id;
    END IF;
    RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS tr_validate_covid_case ON covid_case;
CREATE TRIGGER tr_validate_covid_case
    BEFORE INSERT OR UPDATE ON covid_case
    FOR EACH ROW EXECUTE FUNCTION fn_validate_covid_case();

-- test: this update must be rejected
DO $$
DECLARE
    v_id text;
BEGIN
    SELECT MIN(patient_id) INTO v_id
    FROM covid_case
    WHERE diagnosis = 'suspected' AND NOT hospitalised;

    BEGIN
        UPDATE covid_case SET icu_stay = true WHERE patient_id = v_id;
        RAISE NOTICE 'ERROR: the invalid update was NOT blocked';
    EXCEPTION WHEN raise_exception THEN
        RAISE NOTICE 'Blocked by trigger: %', SQLERRM;
    END;
END
$$;

SELECT COUNT(*) AS invalid_rows
FROM covid_case
WHERE (icu_stay IS TRUE OR ventilated IS TRUE)
  AND hospitalised IS NOT TRUE;


-- ---------------------------------------------------------------------
-- Q14. Keep each case's outcome level automatically in step with its hospital, ICU and ventilation flags, and leave an audit entry.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_sync_outcome_level()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.outcome_level_id IS DISTINCT FROM 3 THEN        -- never overwrite "died"
        NEW.outcome_level_id := CASE
            WHEN NEW.icu_stay IS TRUE OR NEW.ventilated IS TRUE THEN 2
            WHEN NEW.hospitalised IS TRUE                       THEN 1
            ELSE 0
        END;
    END IF;
    RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS tr_sync_outcome_level ON covid_case;
CREATE TRIGGER tr_sync_outcome_level
    BEFORE INSERT OR UPDATE ON covid_case
    FOR EACH ROW EXECUTE FUNCTION fn_sync_outcome_level();

-- test: change ONLY the hospitalised flag, then restore it; the outcome level must follow by itself
DO $$
DECLARE
    v_id text;
    v_before smallint;
    v_after smallint;
    v_restored smallint;
BEGIN
    SELECT MIN(patient_id) INTO v_id
    FROM covid_case
    WHERE diagnosis = 'suspected' AND NOT hospitalised;

    SELECT outcome_level_id INTO v_before FROM covid_case WHERE patient_id = v_id;
    UPDATE covid_case SET hospitalised = true  WHERE patient_id = v_id;
    SELECT outcome_level_id INTO v_after FROM covid_case WHERE patient_id = v_id;
    UPDATE covid_case SET hospitalised = false WHERE patient_id = v_id;
    SELECT outcome_level_id INTO v_restored FROM covid_case WHERE patient_id = v_id;

    RAISE NOTICE 'Patient %: level before % -> after hospitalised flag set % -> after restore %',
                 v_id, v_before, v_after, v_restored;
END
$$;

-- the audit log recorded both changes (run separately)
SELECT audit_id, patient_id, old_hospitalised, new_hospitalised,
       old_outcome_level, new_outcome_level
FROM covid_case_audit
ORDER BY audit_id DESC
LIMIT 2;

-- proof: no row disagrees with the rule (run separately)
SELECT COUNT(*) AS mismatched_rows
FROM covid_case
WHERE outcome_level_id IS DISTINCT FROM
      CASE WHEN icu_stay OR ventilated THEN 2
           WHEN hospitalised           THEN 1
           ELSE 0 END;


-- ---------------------------------------------------------------------
-- Q15. How does PostgreSQL execute the confirmed-cases-by-sex query, and does the diagnosis index help?
-- ---------------------------------------------------------------------
-- 1) planner's own choice
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.sex,
       COUNT(*)                                       AS records,
       COUNT(*) FILTER (WHERE cc.hospitalised IS TRUE) AS hospitalised
FROM patient p
JOIN covid_case cc USING (patient_id)
WHERE cc.diagnosis = 'confirmed'
GROUP BY p.sex;

-- 2) index use switched off (forces a sequential scan)
SET enable_indexscan  = off;
SET enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.sex,
       COUNT(*)                                       AS records,
       COUNT(*) FILTER (WHERE cc.hospitalised IS TRUE) AS hospitalised
FROM patient p
JOIN covid_case cc USING (patient_id)
WHERE cc.diagnosis = 'confirmed'
GROUP BY p.sex;
RESET enable_indexscan;
RESET enable_bitmapscan;

-- 3) sequential scans switched off (forces the index)
SET enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.sex,
       COUNT(*)                                       AS records,
       COUNT(*) FILTER (WHERE cc.hospitalised IS TRUE) AS hospitalised
FROM patient p
JOIN covid_case cc USING (patient_id)
WHERE cc.diagnosis = 'confirmed'
GROUP BY p.sex;
RESET enable_seqscan;