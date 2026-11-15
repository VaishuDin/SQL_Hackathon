-- ============================================================================

--  TEAM 6 - QUERY TITANS

-- ============================================================================

--PART A: ETL AND DATABASE DESIGN

-- ============================================================================

-- PART A.1 - ETL / CLEANSING: public.covid_ms_raw  -> public.covid_ms_clean

-- ---------------------------------------------------------------------
-- Step 0: helper functions
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.yn(t text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE lower(btrim(t)) WHEN 'yes' THEN true WHEN 'no' THEN false END
$$;

CREATE OR REPLACE FUNCTION pg_temp.txt(t text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT NULLIF(lower(btrim(t)), '')
$$;

CREATE OR REPLACE FUNCTION pg_temp.num(t text) RETURNS smallint
LANGUAGE sql IMMUTABLE AS $$
    SELECT NULLIF(btrim(t), '')::numeric::smallint      -- '0.0' -> 0, '2007.0' -> 2007
$$;

-- ---------------------------------------------------------------------
-- Step 1: build the clean table
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS public.covid_ms_clean;

CREATE TABLE public.covid_ms_clean AS
SELECT
    btrim(secret_name)                                  AS secret_name,
    pg_temp.txt(report_source)                          AS report_source,
    pg_temp.num(age_in_cat)                             AS age_in_cat,
    pg_temp.txt(bmi_in_cat2)                            AS bmi_in_cat2,

    pg_temp.yn(covid19_admission_hospital)              AS covid19_admission_hospital,
    pg_temp.yn(covid19_confirmed_case)                  AS covid19_confirmed_case,
    pg_temp.txt(covid19_diagnosis)                      AS covid19_diagnosis,
    pg_temp.yn(covid19_has_symptoms)                    AS covid19_has_symptoms,
    pg_temp.yn(covid19_icu_stay)                        AS covid19_icu_stay,
    pg_temp.txt(covid19_outcome_recovered)              AS covid19_outcome_recovered,
    pg_temp.yn(covid19_self_isolation)                  AS covid19_self_isolation,

    pg_temp.yn(covid19_sympt_chills)                    AS covid19_sympt_chills,
    pg_temp.yn(covid19_sympt_dry_cough)                 AS covid19_sympt_dry_cough,
    pg_temp.yn(covid19_sympt_fatigue)                   AS covid19_sympt_fatigue,
    pg_temp.yn(covid19_sympt_fever)                     AS covid19_sympt_fever,
    pg_temp.yn(covid19_sympt_loss_smell_taste)          AS covid19_sympt_loss_smell_taste,
    pg_temp.yn(covid19_sympt_nasal_congestion)          AS covid19_sympt_nasal_congestion,
    pg_temp.yn(covid19_sympt_pain)                      AS covid19_sympt_pain,
    pg_temp.yn(covid19_sympt_pneumonia)                 AS covid19_sympt_pneumonia,
    pg_temp.yn(covid19_sympt_shortness_breath)          AS covid19_sympt_shortness_breath,
    pg_temp.yn(covid19_sympt_sore_throat)               AS covid19_sympt_sore_throat,

    pg_temp.yn(covid19_ventilation)                     AS covid19_ventilation,
    pg_temp.txt(current_dmt)                            AS current_dmt,   -- yes / no / never_treated
    pg_temp.yn(dmt_glucocorticoid)                      AS dmt_glucocorticoid,
    pg_temp.num(edss_in_cat2)                           AS edss_in_cat2,

    pg_temp.yn(has_comorbidities)                       AS has_comorbidities,
    pg_temp.yn(pregnancy)                               AS pregnancy,
    pg_temp.txt(sex)                                    AS sex,

    CASE WHEN pg_temp.num(year_onset) BETWEEN 1950 AND 2020
         THEN pg_temp.num(year_onset) END               AS year_onset,

    pg_temp.txt(ms_type2)                               AS ms_type2,
    pg_temp.yn(current_or_former_smoker)                AS current_or_former_smoker,
    pg_temp.txt(dmt_type_overall)                       AS dmt_type_overall,
    CASE
        WHEN pg_temp.txt(dmt_type_overall) = 'currently not using any dmt' THEN 'none'
        WHEN pg_temp.txt(dmt_type_overall) LIKE 'currently on %'
             THEN regexp_replace(pg_temp.txt(dmt_type_overall), '^currently on ', '')
    END                                                 AS dmt_drug,

    pg_temp.num(covid19_outcome_levels_2)               AS covid19_outcome_levels_2,
    pg_temp.num(duration_treatment_cat2)                AS duration_treatment_cat2,

    pg_temp.yn(com_cardiovascular_disease)              AS com_cardiovascular_disease,
    pg_temp.yn(com_chronic_kidney_disease)              AS com_chronic_kidney_disease,
    pg_temp.yn(com_chronic_liver_disease)               AS com_chronic_liver_disease,
    pg_temp.yn(com_diabetes)                            AS com_diabetes,
    pg_temp.yn(com_hypertension)                        AS com_hypertension,
    pg_temp.yn(com_immunodeficiency)                    AS com_immunodeficiency,
    pg_temp.yn(com_lung_disease)                        AS com_lung_disease,
    pg_temp.yn(com_malignancy)                          AS com_malignancy,
    pg_temp.yn(com_neurological_neuromuscular)          AS com_neurological_neuromuscular,

    to_date(NULLIF(btrim(stop_or_end_date_combined), ''), 'DD/MM/YYYY')
                                                        AS stop_or_end_date_combined,
    pg_temp.num(comorbidities_other)                    AS comorbidities_other
FROM public.covid_ms_raw;

-- ---------------------------------------------------------------------
-- Step 2: primary key
-- ---------------------------------------------------------------------
ALTER TABLE public.covid_ms_clean ADD PRIMARY KEY (secret_name);

-- ---------------------------------------------------------------------
-- Step 3: data-quality flags 
-- ---------------------------------------------------------------------
ALTER TABLE public.covid_ms_clean
    ADD COLUMN dq_symptom_conflict   boolean DEFAULT false,
    ADD COLUMN dq_comorb_unspecified boolean DEFAULT false;

UPDATE public.covid_ms_clean
SET dq_symptom_conflict = true
WHERE covid19_has_symptoms = false
  AND (   covid19_sympt_chills OR covid19_sympt_dry_cough OR covid19_sympt_fatigue
       OR covid19_sympt_fever OR covid19_sympt_loss_smell_taste
       OR covid19_sympt_nasal_congestion OR covid19_sympt_pain
       OR covid19_sympt_pneumonia OR covid19_sympt_shortness_breath
       OR covid19_sympt_sore_throat);

UPDATE public.covid_ms_clean
SET dq_comorb_unspecified = true
WHERE has_comorbidities = true
  AND NOT (   COALESCE(com_cardiovascular_disease, false)
           OR COALESCE(com_chronic_kidney_disease, false)
           OR COALESCE(com_chronic_liver_disease, false)
           OR COALESCE(com_diabetes, false)
           OR COALESCE(com_hypertension, false)
           OR COALESCE(com_immunodeficiency, false)
           OR COALESCE(com_lung_disease, false)
           OR COALESCE(com_malignancy, false)
           OR COALESCE(com_neurological_neuromuscular, false));


-- =====================================================================
-- PART A.2 - DATABASE DESIGN: normalize covid_ms_clean into a star-like,
--            3NF schema with keys, constraints and indexes.
-- =====================================================================
-- ---------- lookup tables ----------
CREATE TABLE age_group (
    age_group_id smallint PRIMARY KEY,
    age_range    text     NOT NULL
);
INSERT INTO age_group VALUES (0,'0-17'), (1,'18-50'), (2,'51-70'), (3,'71+');

CREATE TABLE outcome_level (
    outcome_level_id smallint PRIMARY KEY,
    outcome_desc     text     NOT NULL
);
INSERT INTO outcome_level VALUES
    (0,'COVID-19, not hospitalised'),
    (1,'Hospitalised'),
    (2,'Hospitalised with ICU and/or ventilation'),
    (3,'Died');

CREATE TABLE dmt_drug (
    dmt_id    smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dmt_name  text NOT NULL UNIQUE,
    dmt_class text NOT NULL            
);
INSERT INTO dmt_drug (dmt_name, dmt_class) VALUES
    ('none',                    'No current DMT'),
    ('never_treated',           'Never treated'),
    ('interferon',              'Injectable platform'),
    ('glatiramer',              'Injectable platform'),
    ('dimethyl fumarate',       'Oral'),
    ('teriflunomide',           'Oral'),
    ('fingolimod',              'S1P modulator'),
    ('natalizumab',             'Other monoclonal antibody'),
    ('ocrelizumab',             'Anti-CD20'),
    ('rituximab',               'Anti-CD20'),
    ('alemtuzumab',             'Immune reconstitution'),
    ('cladribine',              'Immune reconstitution'),
    ('another drug not listed', 'Other / not listed');

CREATE TABLE symptom (
    symptom_id   smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    symptom_name text NOT NULL UNIQUE
);
INSERT INTO symptom (symptom_name) VALUES
    ('chills'),('dry_cough'),('fatigue'),('fever'),('loss_smell_taste'),
    ('nasal_congestion'),('pain'),('pneumonia'),('shortness_breath'),('sore_throat');

CREATE TABLE comorbidity (
    comorbidity_id   smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    comorbidity_name text NOT NULL UNIQUE
);
INSERT INTO comorbidity (comorbidity_name) VALUES
    ('cardiovascular_disease'),('chronic_kidney_disease'),('chronic_liver_disease'),
    ('diabetes'),('hypertension'),('immunodeficiency'),('lung_disease'),
    ('malignancy'),('neurological_neuromuscular'),('other');

-- ---------- core tables ----------
CREATE TABLE patient (
    patient_id             text     PRIMARY KEY,
    report_source          text     NOT NULL CHECK (report_source IN ('patients','clinicians')),
    sex                    text     NOT NULL CHECK (sex IN ('female','male')),
    age_group_id           smallint NOT NULL REFERENCES age_group(age_group_id),
    bmi_category           text,                 
    pregnancy              boolean,
    smoker                 boolean  NOT NULL,    
    ms_type                text     NOT NULL,
    ms_onset_year          smallint,
    edss_cat               smallint,             
    current_dmt_status     text     NOT NULL CHECK (current_dmt_status IN ('yes','no','never_treated')),
    dmt_id                 smallint REFERENCES dmt_drug(dmt_id),
    on_glucocorticoid      boolean,
    treatment_duration_cat smallint,             
    stop_or_end_date       date,                 
    has_comorbidities      boolean
);

CREATE TABLE covid_case (
    patient_id       text     PRIMARY KEY REFERENCES patient(patient_id),
    diagnosis        text     NOT NULL CHECK (diagnosis IN ('confirmed','suspected','not_suspected')),
    confirmed_case   boolean,
    has_symptoms     boolean,
    self_isolated    boolean,
    hospitalised     boolean,
    icu_stay         boolean,
    ventilated       boolean,
    recovered        text,
    outcome_level_id smallint REFERENCES outcome_level(outcome_level_id)
);

CREATE TABLE patient_symptom (
    patient_id text     NOT NULL REFERENCES patient(patient_id),
    symptom_id smallint NOT NULL REFERENCES symptom(symptom_id),
    present    boolean  NOT NULL,
    PRIMARY KEY (patient_id, symptom_id)
);

CREATE TABLE patient_comorbidity (
    patient_id     text     NOT NULL REFERENCES patient(patient_id),
    comorbidity_id smallint NOT NULL REFERENCES comorbidity(comorbidity_id),
    present        boolean  NOT NULL,
    PRIMARY KEY (patient_id, comorbidity_id)
);

-- ---------- load (ETL) ----------
INSERT INTO patient (patient_id, report_source, sex, age_group_id, bmi_category, pregnancy,
                     smoker, ms_type, ms_onset_year, edss_cat, current_dmt_status, dmt_id,
                     on_glucocorticoid, treatment_duration_cat, stop_or_end_date, has_comorbidities)
SELECT c.secret_name,
       c.report_source,
       c.sex,
       c.age_in_cat,
       c.bmi_in_cat2,
       c.pregnancy,
       COALESCE(c.current_or_former_smoker, false),
       c.ms_type2,
       c.year_onset,
       c.edss_in_cat2,
       c.current_dmt,
       d.dmt_id,
       c.dmt_glucocorticoid,
       c.duration_treatment_cat2,
       c.stop_or_end_date_combined,
       c.has_comorbidities
FROM public.covid_ms_clean c
LEFT JOIN dmt_drug d
       ON d.dmt_name = COALESCE(c.dmt_drug,
                                CASE WHEN c.current_dmt = 'never_treated' THEN 'never_treated' END);

INSERT INTO covid_case (patient_id, diagnosis, confirmed_case, has_symptoms, self_isolated,
                        hospitalised, icu_stay, ventilated, recovered, outcome_level_id)
SELECT secret_name,
       covid19_diagnosis,
       covid19_confirmed_case,
       covid19_has_symptoms,
       covid19_self_isolation,
       covid19_admission_hospital,
       covid19_icu_stay,
       covid19_ventilation,
       covid19_outcome_recovered,
       covid19_outcome_levels_2
FROM public.covid_ms_clean;

INSERT INTO patient_symptom (patient_id, symptom_id, present)
SELECT c.secret_name, s.symptom_id, v.present
FROM public.covid_ms_clean c
CROSS JOIN LATERAL (VALUES
        ('chills',           c.covid19_sympt_chills),
        ('dry_cough',        c.covid19_sympt_dry_cough),
        ('fatigue',          c.covid19_sympt_fatigue),
        ('fever',            c.covid19_sympt_fever),
        ('loss_smell_taste', c.covid19_sympt_loss_smell_taste),
        ('nasal_congestion', c.covid19_sympt_nasal_congestion),
        ('pain',             c.covid19_sympt_pain),
        ('pneumonia',        c.covid19_sympt_pneumonia),
        ('shortness_breath', c.covid19_sympt_shortness_breath),
        ('sore_throat',      c.covid19_sympt_sore_throat)
     ) AS v(symptom_name, present)
JOIN symptom s ON s.symptom_name = v.symptom_name
WHERE v.present IS NOT NULL;

INSERT INTO patient_comorbidity (patient_id, comorbidity_id, present)
SELECT c.secret_name, m.comorbidity_id, v.present
FROM public.covid_ms_clean c
CROSS JOIN LATERAL (VALUES
        ('cardiovascular_disease',     c.com_cardiovascular_disease),
        ('chronic_kidney_disease',     c.com_chronic_kidney_disease),
        ('chronic_liver_disease',      c.com_chronic_liver_disease),
        ('diabetes',                   c.com_diabetes),
        ('hypertension',               c.com_hypertension),
        ('immunodeficiency',           c.com_immunodeficiency),
        ('lung_disease',               c.com_lung_disease),
        ('malignancy',                 c.com_malignancy),
        ('neurological_neuromuscular', c.com_neurological_neuromuscular),
        ('other',                      (c.comorbidities_other = 1))
     ) AS v(comorbidity_name, present)
JOIN comorbidity m ON m.comorbidity_name = v.comorbidity_name
WHERE v.present IS NOT NULL;

CREATE INDEX idx_patient_dmt        ON patient(dmt_id);
CREATE INDEX idx_patient_age_group  ON patient(age_group_id);
CREATE INDEX idx_case_diagnosis     ON covid_case(diagnosis);
CREATE INDEX idx_case_outcome       ON covid_case(outcome_level_id);
CREATE INDEX idx_ps_symptom_yes     ON patient_symptom(symptom_id)       WHERE present;
CREATE INDEX idx_pc_comorb_yes      ON patient_comorbidity(comorbidity_id) WHERE present; 


-- ---------- ETL check----------
SELECT (SELECT count(*) FROM patient)             AS patient_rows,
       (SELECT count(*) FROM covid_case)          AS covid_case_rows,
       (SELECT count(*) FROM patient_symptom)     AS symptom_rows,
       (SELECT count(*) FROM patient_comorbidity) AS comorbidity_rows;




