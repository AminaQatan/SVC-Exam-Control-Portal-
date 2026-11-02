/* =====================================================================
   SVC Exam Portal  -  Oracle database script
   Salalah Vocational College - Midterm Exam - November 2026 - Term 1
   Developer : Ms. Amina Qatan
   Version   : 1.4 (2026-11-02) - staff chat; course, invigilator and floor
               invigilator dropdowns; exam dropdowns; user roles; day report

   Runs on   : Oracle Database 19c or later, Oracle APEX 22.2 or later
               (a free workspace on apex.oracle.com works)
   Encoding  : UTF-8 (the notice and violation labels contain Arabic)

   HOW TO RUN
     Oracle APEX           : SQL Workshop > SQL Scripts > Upload > Run
     SQL Developer / SQLcl : @svc_exam_portal.sql

   The script can be run again. It drops only the objects it creates.

   CONTENTS
     1. Clean up
     2. Tables
     3. Indexes and trigger
     4. Views
     5. PL/SQL package SVC_EXAM_PKG
     6. Reference data (exam, rooms, staff, violation types, colour themes, portal owner)
     7. Data from the Room 13 sheet
     8. End-of-day report export SVC_REPORT_PKG (administrators only, needs APEX 20.2+)
     9. Quick checks
    10. Building the APEX application

   HOW THE SHEET MAPS TO THE TABLES
     Room tabs (Room 1 ... Physics lab)          -> SVC_ROOMS
     Morning / Afternoon blocks                  -> SVC_SESSIONS
     Day, Date, Course name, No. of present      -> SVC_SESSIONS
     Warning 1 / 2 / 3 / Cheating report         -> SVC_INCIDENTS.INCIDENT_LEVEL
     Names of the absent students                -> SVC_ABSENTEES
     Invigilator 1, 2, Floor invigilator         -> SVC_SESSIONS -> SVC_STAFF
     Copying / Sharing answers / Mobile / Talking-> SVC_SESSION_FLAGS
     Washroom notice (Arabic + English)          -> SVC_EXAMS
     Exam dropdown (Midterm / Final)             -> SVC_EXAM_TYPES
     Programs (Preparatory / Post-Preparatory,
               one or both)                      -> SVC_PROGRAMS, SVC_EXAM_PROGRAMS
     Academic year (2026-2027 onwards)           -> SVC_V_ACADEMIC_YEARS
     Month (September to August)                 -> SVC_V_EXAM_MONTHS
     Term (1, 2, 3)                              -> SVC_EXAMS.TERM_NO
     Course name dropdown (code + name)          -> SVC_COURSES (114 courses)
     Invigilator (1) and (2) dropdowns           -> SVC_STAFF.IS_INVIGILATOR = 'Y'
     Floor invigilator dropdown                  -> SVC_STAFF.IS_FLOOR_INVIGILATOR = 'Y'
     Staff chat                                  -> SVC_CHAT_MESSAGES, SVC_V_CHAT
     Colour themes                               -> SVC_THEMES, SVC_USER_PREFS
     Who may open and download the day report    -> SVC_APP_USERS (OWNER / ADMIN)

   ROLES
     OWNER, ADMIN        see the "Day report" icon, open the end-of-day
                         dashboard and download it (Excel, CSV, HTML)
     FLOOR_INVIGILATOR,  fill in the room sheets only. The icon is hidden
     INVIGILATOR         AND the report page and downloads are locked
                         on the server, so a typed link does not work.
   ===================================================================== */


-- =====================================================================
-- 1. CLEAN UP
-- =====================================================================
DECLARE
  PROCEDURE drop_object (p_sql IN VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p_sql;
  EXCEPTION
    WHEN OTHERS THEN
      -- ORA-00942 table or view does not exist, ORA-04043 object does not exist
      IF SQLCODE NOT IN (-942, -4043) THEN
        RAISE;
      END IF;
  END drop_object;
BEGIN
  drop_object('DROP VIEW svc_v_chat');
  drop_object('DROP VIEW svc_v_exam_months');
  drop_object('DROP VIEW svc_v_academic_years');
  drop_object('DROP VIEW svc_v_incidents');
  drop_object('DROP VIEW svc_v_session_summary');
  drop_object('DROP PACKAGE svc_report_pkg');
  drop_object('DROP PACKAGE svc_exam_pkg');
  drop_object('DROP TABLE svc_chat_messages   CASCADE CONSTRAINTS PURGE');
  drop_object('DROP TABLE svc_app_users       CASCADE CONSTRAINTS PURGE');
  drop_object('DROP TABLE svc_user_prefs      CASCADE CONSTRAINTS PURGE');
  drop_object('DROP TABLE svc_themes          CASCADE CONSTRAINTS PURGE');
  drop_object('DROP TABLE svc_session_flags   CASCADE CONSTRAINTS PURGE');
  drop_object('DROP TABLE svc_absentees       CASCADE CONSTRAINTS PURGE');
  drop_object('DROP TABLE svc_incidents       CASCADE CONSTRAINTS PURGE');
  drop_object('DROP TABLE svc_sessions        CASCADE CONSTRAINTS PURGE');
  drop_object('DROP TABLE svc_violation_types CASCADE CONSTRAINTS PURGE');
  drop_object('DROP TABLE svc_students        CASCADE CONSTRAINTS PURGE');
  drop_object('DROP TABLE svc_staff           CASCADE CONSTRAINTS PURGE');
  drop_object('DROP TABLE svc_courses         CASCADE CONSTRAINTS PURGE');
  drop_object('DROP TABLE svc_rooms           CASCADE CONSTRAINTS PURGE');
  drop_object('DROP TABLE svc_exam_programs   CASCADE CONSTRAINTS PURGE');
  drop_object('DROP TABLE svc_exams           CASCADE CONSTRAINTS PURGE');
  drop_object('DROP TABLE svc_programs        CASCADE CONSTRAINTS PURGE');
  drop_object('DROP TABLE svc_exam_types      CASCADE CONSTRAINTS PURGE');
END;
/


-- =====================================================================
-- 2. TABLES
-- =====================================================================

-- Exam dropdown: Midterm Exam, Final Exam
CREATE TABLE svc_exam_types (
  exam_type_code  VARCHAR2(20 CHAR)
                  CONSTRAINT svc_exam_types_pk PRIMARY KEY,
  label_en        VARCHAR2(50 CHAR) NOT NULL,
  label_ar        VARCHAR2(50 CHAR) NOT NULL,
  sort_order      NUMBER(2) NOT NULL
);

-- Programs dropdown: Preparatory, Post-Preparatory
CREATE TABLE svc_programs (
  program_code  VARCHAR2(20 CHAR)
                CONSTRAINT svc_programs_pk PRIMARY KEY,
  label_en      VARCHAR2(50 CHAR) NOT NULL,
  label_ar      VARCHAR2(50 CHAR) NOT NULL,
  sort_order    NUMBER(2) NOT NULL
);

-- One row per exam: exam type + academic year + term.
-- Academic years start at 2026-2027; terms are 1, 2 or 3.
CREATE TABLE svc_exams (
  exam_id         NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY
                  CONSTRAINT svc_exams_pk PRIMARY KEY,
  exam_type_code  VARCHAR2(20 CHAR) NOT NULL
                  CONSTRAINT svc_exams_type_fk REFERENCES svc_exam_types (exam_type_code),
  exam_month      DATE
                  CONSTRAINT svc_exams_month_ck CHECK (exam_month = TRUNC(exam_month, 'MM')),
  academic_year   VARCHAR2(9 CHAR) NOT NULL
                  CONSTRAINT svc_exams_year_ck CHECK (
                    CASE
                      WHEN NOT REGEXP_LIKE(academic_year, '^[0-9]{4}-[0-9]{4}$') THEN 0
                      WHEN TO_NUMBER(SUBSTR(academic_year, 1, 4)) >= 2026
                       AND TO_NUMBER(SUBSTR(academic_year, 6, 4)) = TO_NUMBER(SUBSTR(academic_year, 1, 4)) + 1
                      THEN 1
                      ELSE 0
                    END = 1),
  term_no         NUMBER(1) NOT NULL
                  CONSTRAINT svc_exams_term_ck CHECK (term_no IN (1, 2, 3)),
  notice_ar       VARCHAR2(400 CHAR),
  notice_en       VARCHAR2(400 CHAR),
  is_active       VARCHAR2(1 CHAR) DEFAULT 'Y' NOT NULL
                  CONSTRAINT svc_exams_active_ck CHECK (is_active IN ('Y', 'N')),
  created_at      TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT svc_exams_uk UNIQUE (exam_type_code, academic_year, term_no)
);

-- Which programs an exam covers (one or more)
CREATE TABLE svc_exam_programs (
  exam_id       NUMBER NOT NULL
                CONSTRAINT svc_exam_programs_exam_fk
                REFERENCES svc_exams (exam_id) ON DELETE CASCADE,
  program_code  VARCHAR2(20 CHAR) NOT NULL
                CONSTRAINT svc_exam_programs_prog_fk REFERENCES svc_programs (program_code),
  CONSTRAINT svc_exam_programs_pk PRIMARY KEY (exam_id, program_code)
);

-- One row per tab in the Google Sheet
CREATE TABLE svc_rooms (
  room_id     NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY
              CONSTRAINT svc_rooms_pk PRIMARY KEY,
  room_name   VARCHAR2(50 CHAR) NOT NULL
              CONSTRAINT svc_rooms_name_uk UNIQUE,
  room_type   VARCHAR2(10 CHAR) NOT NULL
              CONSTRAINT svc_rooms_type_ck CHECK (room_type IN ('ROOM', 'LAB', 'HALL')),
  sort_order  NUMBER(3) NOT NULL
);

-- Invigilators, floor invigilators and coordinators.
-- The two flags decide which dropdown each person appears in.
CREATE TABLE svc_staff (
  staff_id              NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY
                        CONSTRAINT svc_staff_pk PRIMARY KEY,
  title                 VARCHAR2(10 CHAR),
  full_name             VARCHAR2(150 CHAR) NOT NULL
                        CONSTRAINT svc_staff_name_uk UNIQUE,
  email                 VARCHAR2(150 CHAR),
  is_invigilator        VARCHAR2(1 CHAR) DEFAULT 'Y' NOT NULL
                        CONSTRAINT svc_staff_inv_ck CHECK (is_invigilator IN ('Y', 'N')),
  is_floor_invigilator  VARCHAR2(1 CHAR) DEFAULT 'N' NOT NULL
                        CONSTRAINT svc_staff_floor_ck CHECK (is_floor_invigilator IN ('Y', 'N')),
  is_active             VARCHAR2(1 CHAR) DEFAULT 'Y' NOT NULL
                        CONSTRAINT svc_staff_active_ck CHECK (is_active IN ('Y', 'N'))
);

-- Course dropdown. A code can be missing (some courses have none in the
-- timetable) and is not unique, because the timetable gives MSFQ2109 and
-- MSFQ2110 to two courses each.
CREATE TABLE svc_courses (
  course_id       NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY
                  CONSTRAINT svc_courses_pk PRIMARY KEY,
  course_code     VARCHAR2(12 CHAR),
  course_name     VARCHAR2(150 CHAR) NOT NULL,
  specialization  VARCHAR2(80 CHAR) NOT NULL,
  sort_order      NUMBER(4) NOT NULL,
  is_active       VARCHAR2(1 CHAR) DEFAULT 'Y' NOT NULL
                  CONSTRAINT svc_courses_active_ck CHECK (is_active IN ('Y', 'N')),
  CONSTRAINT svc_courses_uk UNIQUE (specialization, course_code, course_name)
);

-- Students who appear on a warning or absentee list
CREATE TABLE svc_students (
  student_id  NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY
              CONSTRAINT svc_students_pk PRIMARY KEY,
  student_no  VARCHAR2(20 CHAR)
              CONSTRAINT svc_students_no_uk UNIQUE,
  full_name   VARCHAR2(150 CHAR) NOT NULL
);

-- The four ticks in the Comments row of the sheet
CREATE TABLE svc_violation_types (
  violation_code  VARCHAR2(20 CHAR)
                  CONSTRAINT svc_violation_types_pk PRIMARY KEY,
  label_en        VARCHAR2(50 CHAR) NOT NULL,
  label_ar        VARCHAR2(50 CHAR) NOT NULL,
  sort_order      NUMBER(2) NOT NULL
);

-- One row per room, per period (the Morning and Afternoon blocks)
CREATE TABLE svc_sessions (
  session_id            NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY
                        CONSTRAINT svc_sessions_pk PRIMARY KEY,
  exam_id               NUMBER NOT NULL
                        CONSTRAINT svc_sessions_exam_fk REFERENCES svc_exams (exam_id),
  room_id               NUMBER NOT NULL
                        CONSTRAINT svc_sessions_room_fk REFERENCES svc_rooms (room_id),
  period                VARCHAR2(10 CHAR) NOT NULL
                        CONSTRAINT svc_sessions_period_ck CHECK (period IN ('MORNING', 'AFTERNOON')),
  exam_date             DATE,
  course_id             NUMBER
                        CONSTRAINT svc_sessions_course_fk REFERENCES svc_courses (course_id),
  no_present            NUMBER(4)
                        CONSTRAINT svc_sessions_present_ck CHECK (no_present >= 0),
  invigilator1_id       NUMBER
                        CONSTRAINT svc_sessions_inv1_fk  REFERENCES svc_staff (staff_id),
  invigilator2_id       NUMBER
                        CONSTRAINT svc_sessions_inv2_fk  REFERENCES svc_staff (staff_id),
  floor_invigilator_id  NUMBER
                        CONSTRAINT svc_sessions_floor_fk REFERENCES svc_staff (staff_id),
  coordinator_id        NUMBER
                        CONSTRAINT svc_sessions_coord_fk REFERENCES svc_staff (staff_id),
  comments              VARCHAR2(2000 CHAR),
  updated_at            TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  updated_by            VARCHAR2(100 CHAR),
  CONSTRAINT svc_sessions_uk UNIQUE (exam_id, room_id, period, exam_date),
  -- the same person cannot be Invigilator (1) and Invigilator (2)
  CONSTRAINT svc_sessions_inv_diff_ck CHECK (invigilator2_id IS NULL OR invigilator2_id <> invigilator1_id)
);

-- Warning 1 / 2 / 3 / Cheating report. One row per student per session;
-- escalating a student moves the row to the next level.
CREATE TABLE svc_incidents (
  incident_id     NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY
                  CONSTRAINT svc_incidents_pk PRIMARY KEY,
  session_id      NUMBER NOT NULL
                  CONSTRAINT svc_incidents_session_fk
                  REFERENCES svc_sessions (session_id) ON DELETE CASCADE,
  student_id      NUMBER NOT NULL
                  CONSTRAINT svc_incidents_student_fk REFERENCES svc_students (student_id),
  incident_level  VARCHAR2(20 CHAR) DEFAULT 'WARNING_1' NOT NULL
                  CONSTRAINT svc_incidents_level_ck
                  CHECK (incident_level IN ('WARNING_1', 'WARNING_2', 'WARNING_3', 'CHEATING_REPORT')),
  violation_code  VARCHAR2(20 CHAR)
                  CONSTRAINT svc_incidents_type_fk
                  REFERENCES svc_violation_types (violation_code),
  notes           VARCHAR2(1000 CHAR),
  recorded_at     TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  recorded_by     VARCHAR2(100 CHAR),
  CONSTRAINT svc_incidents_uk UNIQUE (session_id, student_id)
);

-- Names of the absent students
CREATE TABLE svc_absentees (
  session_id  NUMBER NOT NULL
              CONSTRAINT svc_absentees_session_fk
              REFERENCES svc_sessions (session_id) ON DELETE CASCADE,
  student_id  NUMBER NOT NULL
              CONSTRAINT svc_absentees_student_fk REFERENCES svc_students (student_id),
  CONSTRAINT svc_absentees_pk PRIMARY KEY (session_id, student_id)
);

-- Ticked boxes in the Comments row (Copying, Sharing answers, Mobile, Talking)
CREATE TABLE svc_session_flags (
  session_id      NUMBER NOT NULL
                  CONSTRAINT svc_flags_session_fk
                  REFERENCES svc_sessions (session_id) ON DELETE CASCADE,
  violation_code  VARCHAR2(20 CHAR) NOT NULL
                  CONSTRAINT svc_flags_type_fk
                  REFERENCES svc_violation_types (violation_code),
  CONSTRAINT svc_session_flags_pk PRIMARY KEY (session_id, violation_code)
);

-- Colour themes the users can pick from
CREATE TABLE svc_themes (
  theme_code    VARCHAR2(20 CHAR)
                CONSTRAINT svc_themes_pk PRIMARY KEY,
  theme_name    VARCHAR2(50 CHAR) NOT NULL,
  primary_hex   VARCHAR2(7 CHAR) NOT NULL,
  banner_hex    VARCHAR2(7 CHAR) NOT NULL,
  warning1_hex  VARCHAR2(7 CHAR) NOT NULL,
  warning2_hex  VARCHAR2(7 CHAR) NOT NULL,
  warning3_hex  VARCHAR2(7 CHAR) NOT NULL,
  cheating_hex  VARCHAR2(7 CHAR) NOT NULL,
  notice_hex    VARCHAR2(7 CHAR) NOT NULL,
  absent_hex    VARCHAR2(7 CHAR) NOT NULL,
  is_default    VARCHAR2(1 CHAR) DEFAULT 'N' NOT NULL
                CONSTRAINT svc_themes_default_ck CHECK (is_default IN ('Y', 'N')),
  CONSTRAINT svc_themes_hex_ck CHECK (
        REGEXP_LIKE(primary_hex,  '^#[0-9A-Fa-f]{6}$')
    AND REGEXP_LIKE(banner_hex,   '^#[0-9A-Fa-f]{6}$')
    AND REGEXP_LIKE(warning1_hex, '^#[0-9A-Fa-f]{6}$')
    AND REGEXP_LIKE(warning2_hex, '^#[0-9A-Fa-f]{6}$')
    AND REGEXP_LIKE(warning3_hex, '^#[0-9A-Fa-f]{6}$')
    AND REGEXP_LIKE(cheating_hex, '^#[0-9A-Fa-f]{6}$')
    AND REGEXP_LIKE(notice_hex,   '^#[0-9A-Fa-f]{6}$')
    AND REGEXP_LIKE(absent_hex,   '^#[0-9A-Fa-f]{6}$')
  )
);

-- Each user's chosen theme and light/dark mode
CREATE TABLE svc_user_prefs (
  app_user    VARCHAR2(100 CHAR)
              CONSTRAINT svc_user_prefs_pk PRIMARY KEY,
  theme_code  VARCHAR2(20 CHAR) NOT NULL
              CONSTRAINT svc_user_prefs_theme_fk REFERENCES svc_themes (theme_code),
  color_mode  VARCHAR2(5 CHAR) DEFAULT 'AUTO' NOT NULL
              CONSTRAINT svc_user_prefs_mode_ck CHECK (color_mode IN ('AUTO', 'LIGHT', 'DARK'))
);

-- Portal users and their role. APP_USER is the APEX login name in capitals.
-- Only OWNER and ADMIN can see and download the end-of-day report.
CREATE TABLE svc_app_users (
  app_user   VARCHAR2(100 CHAR)
             CONSTRAINT svc_app_users_pk PRIMARY KEY
             CONSTRAINT svc_app_users_upper_ck CHECK (app_user = UPPER(app_user)),
  staff_id   NUMBER
             CONSTRAINT svc_app_users_staff_fk REFERENCES svc_staff (staff_id),
  app_role   VARCHAR2(20 CHAR) NOT NULL
             CONSTRAINT svc_app_users_role_ck
             CHECK (app_role IN ('OWNER', 'ADMIN', 'FLOOR_INVIGILATOR', 'INVIGILATOR')),
  is_active  VARCHAR2(1 CHAR) DEFAULT 'Y' NOT NULL
             CONSTRAINT svc_app_users_active_ck CHECK (is_active IN ('Y', 'N'))
);

-- Staff chat: one row per message
CREATE TABLE svc_chat_messages (
  message_id  NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY
              CONSTRAINT svc_chat_messages_pk PRIMARY KEY,
  app_user    VARCHAR2(100 CHAR) NOT NULL,
  body        VARCHAR2(1000 CHAR) NOT NULL,
  posted_at   TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL
);
CREATE INDEX svc_chat_posted_ix ON svc_chat_messages (posted_at);


-- =====================================================================
-- 3. INDEXES AND TRIGGER
-- =====================================================================
CREATE INDEX svc_students_name_ix  ON svc_students  (UPPER(full_name));
CREATE INDEX svc_sessions_room_ix  ON svc_sessions  (room_id, period);
CREATE INDEX svc_incidents_stud_ix ON svc_incidents (student_id);
CREATE INDEX svc_absentees_stud_ix ON svc_absentees (student_id);

CREATE OR REPLACE TRIGGER svc_sessions_biu
  BEFORE INSERT OR UPDATE ON svc_sessions
  FOR EACH ROW
BEGIN
  :new.updated_at := SYSTIMESTAMP;
  :new.updated_by := COALESCE(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER);
END;
/


-- =====================================================================
-- 4. VIEWS
-- =====================================================================

-- Everything the dashboard and each room sheet needs, one row per session
CREATE OR REPLACE VIEW svc_v_session_summary AS
SELECT s.session_id,
       s.exam_id,
       e.exam_type_code,
       et.label_en                                AS exam_name,
       (SELECT LISTAGG(p.label_en, ' - ') WITHIN GROUP (ORDER BY p.sort_order)
        FROM   svc_exam_programs ep
        JOIN   svc_programs      p ON p.program_code = ep.program_code
        WHERE  ep.exam_id = e.exam_id)            AS programs,
       TO_CHAR(e.exam_month, 'fmMonth YYYY', 'NLS_DATE_LANGUAGE=ENGLISH') AS exam_month,
       e.academic_year,
       e.term_no,
       s.room_id,
       r.room_name,
       r.room_type,
       r.sort_order,
       s.period,
       s.exam_date,
       TO_CHAR(s.exam_date, 'fmDay', 'NLS_DATE_LANGUAGE=ENGLISH') AS exam_day,
       s.course_id,
       c.course_code,
       c.course_name,
       NVL(s.no_present, 0)                       AS no_present,
       NVL(a.no_absent, 0)                        AS no_absent,
       NVL(s.no_present, 0) + NVL(a.no_absent, 0) AS total_students,
       NVL(i.warning_1, 0)                        AS warning_1,
       NVL(i.warning_2, 0)                        AS warning_2,
       NVL(i.warning_3, 0)                        AS warning_3,
       NVL(i.cheating_reports, 0)                 AS cheating_reports,
       inv1.full_name                             AS invigilator_1,
       inv2.full_name                             AS invigilator_2,
       flr.full_name                              AS floor_invigilator,
       crd.full_name                              AS coordinator,
       s.comments,
       CASE
         WHEN s.course_id       IS NOT NULL
          AND s.no_present      IS NOT NULL
          AND s.invigilator1_id IS NOT NULL         THEN 'COMPLETE'
         WHEN s.course_id            IS NOT NULL
           OR s.no_present           IS NOT NULL
           OR s.invigilator1_id      IS NOT NULL
           OR s.invigilator2_id      IS NOT NULL
           OR s.floor_invigilator_id IS NOT NULL
           OR s.coordinator_id       IS NOT NULL
           OR s.comments             IS NOT NULL
           OR a.no_absent > 0
           OR i.session_id           IS NOT NULL    THEN 'IN PROGRESS'
         ELSE 'NOT STARTED'
       END                                        AS session_status,
       s.updated_at,
       s.updated_by
FROM   svc_sessions   s
JOIN   svc_exams      e  ON e.exam_id         = s.exam_id
JOIN   svc_exam_types et ON et.exam_type_code = e.exam_type_code
JOIN   svc_rooms      r  ON r.room_id         = s.room_id
LEFT JOIN (SELECT session_id, COUNT(*) AS no_absent
           FROM   svc_absentees
           GROUP  BY session_id) a
       ON a.session_id = s.session_id
LEFT JOIN (SELECT session_id,
                  COUNT(CASE WHEN incident_level = 'WARNING_1'       THEN 1 END) AS warning_1,
                  COUNT(CASE WHEN incident_level = 'WARNING_2'       THEN 1 END) AS warning_2,
                  COUNT(CASE WHEN incident_level = 'WARNING_3'       THEN 1 END) AS warning_3,
                  COUNT(CASE WHEN incident_level = 'CHEATING_REPORT' THEN 1 END) AS cheating_reports
           FROM   svc_incidents
           GROUP  BY session_id) i
       ON i.session_id = s.session_id
LEFT JOIN svc_courses c   ON c.course_id    = s.course_id
LEFT JOIN svc_staff inv1 ON inv1.staff_id = s.invigilator1_id
LEFT JOIN svc_staff inv2 ON inv2.staff_id = s.invigilator2_id
LEFT JOIN svc_staff flr  ON flr.staff_id  = s.floor_invigilator_id
LEFT JOIN svc_staff crd  ON crd.staff_id  = s.coordinator_id;

-- Warnings and cheating reports with names, for reports and the Warnings tab
CREATE OR REPLACE VIEW svc_v_incidents AS
SELECT i.incident_id,
       i.session_id,
       s.exam_id,
       r.room_name,
       r.sort_order,
       s.period,
       s.exam_date,
       st.full_name AS student_name,
       i.incident_level,
       CASE i.incident_level
         WHEN 'WARNING_1' THEN 'Warning 1'
         WHEN 'WARNING_2' THEN 'Warning 2'
         WHEN 'WARNING_3' THEN 'Warning 3'
         ELSE 'Cheating report'
       END          AS level_label,
       v.label_en   AS violation_en,
       v.label_ar   AS violation_ar,
       i.notes,
       i.recorded_at,
       i.recorded_by
FROM   svc_incidents i
JOIN   svc_sessions  s  ON s.session_id  = i.session_id
JOIN   svc_rooms     r  ON r.room_id     = s.room_id
JOIN   svc_students  st ON st.student_id = i.student_id
LEFT JOIN svc_violation_types v ON v.violation_code = i.violation_code;

-- Staff chat with the sender's name from the staff list
CREATE OR REPLACE VIEW svc_v_chat AS
SELECT m.message_id,
       m.app_user,
       COALESCE(st.full_name, INITCAP(REPLACE(LOWER(m.app_user), '.', ' '))) AS author,
       m.body,
       m.posted_at
FROM   svc_chat_messages m
LEFT JOIN svc_app_users u  ON u.app_user  = m.app_user
LEFT JOIN svc_staff     st ON st.staff_id = u.staff_id;

-- Academic year dropdown: 2026-2027 onwards, always five years ahead of today
CREATE OR REPLACE VIEW svc_v_academic_years AS
SELECT TO_CHAR(2025 + LEVEL) || '-' || TO_CHAR(2026 + LEVEL) AS academic_year,
       2025 + LEVEL                                            AS start_year
FROM   dual
CONNECT BY LEVEL <= GREATEST(10, EXTRACT(YEAR FROM SYSDATE) - 2026 + 6);

-- Month dropdown: September to August of each academic year
CREATE OR REPLACE VIEW svc_v_exam_months AS
SELECT y.academic_year,
       ADD_MONTHS(TO_DATE(y.start_year || '-09-01', 'YYYY-MM-DD'), m.n - 1) AS exam_month,
       TO_CHAR(ADD_MONTHS(TO_DATE(y.start_year || '-09-01', 'YYYY-MM-DD'), m.n - 1),
               'fmMonth YYYY', 'NLS_DATE_LANGUAGE=ENGLISH')                 AS month_label
FROM   svc_v_academic_years y
CROSS JOIN (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 12) m;


-- =====================================================================
-- 5. PL/SQL PACKAGE
-- =====================================================================
CREATE OR REPLACE PACKAGE svc_exam_pkg AS

  -- Called when someone changes the exam dropdowns. Finds the exam for this
  -- exam type + academic year + term, or creates it with a Morning and an
  -- Afternoon sheet for every room. Returns the exam id.
  --   p_exam_type_code : MIDTERM or FINAL
  --   p_academic_year  : '2026-2027' or later
  --   p_term_no        : 1, 2 or 3
  --   p_exam_month     : first day of the month (optional)
  --   p_programs       : colon-separated codes, e.g. 'PREPARATORY:POST_PREPARATORY'
  --                      (the value an APEX checkbox group returns; optional)
  FUNCTION open_exam (p_exam_type_code IN VARCHAR2,
                      p_academic_year  IN VARCHAR2,
                      p_term_no        IN NUMBER,
                      p_exam_month     IN DATE     DEFAULT NULL,
                      p_programs       IN VARCHAR2 DEFAULT NULL) RETURN NUMBER;

  -- Finds a student by name, or adds them. Returns the student id.
  FUNCTION get_student_id (p_full_name IN VARCHAR2) RETURN NUMBER;

  -- First call gives Warning 1. Calling again for the same student
  -- in the same session moves them up one level.
  PROCEDURE record_warning (p_session_id     IN NUMBER,
                            p_student_name   IN VARCHAR2,
                            p_violation_code IN VARCHAR2 DEFAULT NULL,
                            p_notes          IN VARCHAR2 DEFAULT NULL);

  -- Warning 1 -> Warning 2 -> Warning 3 -> Cheating report
  PROCEDURE escalate (p_incident_id IN NUMBER);

  PROCEDURE mark_absent (p_session_id   IN NUMBER,
                         p_student_name IN VARCHAR2);

  -- CSS variables for a theme (default theme when the code is NULL)
  FUNCTION theme_css (p_theme_code IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2;

  -- CSS variables for the theme a user picked
  FUNCTION user_theme_css (p_app_user IN VARCHAR2) RETURN VARCHAR2;

  PROCEDURE save_user_theme (p_app_user   IN VARCHAR2,
                             p_theme_code IN VARCHAR2,
                             p_color_mode IN VARCHAR2 DEFAULT 'AUTO');

  -- OWNER, ADMIN, FLOOR_INVIGILATOR, INVIGILATOR, or NULL for unknown users
  FUNCTION user_role (p_app_user IN VARCHAR2) RETURN VARCHAR2;

  -- TRUE only for active OWNER and ADMIN users.
  -- Used by the APEX authorization scheme "Administrators only".
  FUNCTION is_admin (p_app_user IN VARCHAR2) RETURN BOOLEAN;

  -- Staff chat. Everyone signed in can post; people delete their own
  -- messages, administrators can delete any message or clear the chat.
  PROCEDURE post_message (p_body IN VARCHAR2);
  PROCEDURE delete_message (p_message_id IN NUMBER);
  PROCEDURE clear_chat;

END svc_exam_pkg;
/

CREATE OR REPLACE PACKAGE BODY svc_exam_pkg AS

  FUNCTION current_app_user RETURN VARCHAR2 IS
  BEGIN
    RETURN COALESCE(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER);
  END current_app_user;

  FUNCTION open_exam (p_exam_type_code IN VARCHAR2,
                      p_academic_year  IN VARCHAR2,
                      p_term_no        IN NUMBER,
                      p_exam_month     IN DATE     DEFAULT NULL,
                      p_programs       IN VARCHAR2 DEFAULT NULL) RETURN NUMBER IS
    l_exam_id svc_exams.exam_id%TYPE;
    l_ar      svc_exams.notice_ar%TYPE;
    l_en      svc_exams.notice_en%TYPE;
  BEGIN
    SELECT MIN(exam_id)
    INTO   l_exam_id
    FROM   svc_exams
    WHERE  exam_type_code = p_exam_type_code
    AND    academic_year  = p_academic_year
    AND    term_no        = p_term_no;

    IF l_exam_id IS NULL THEN
      -- carry the notice over from the most recent exam
      BEGIN
        SELECT notice_ar, notice_en
        INTO   l_ar, l_en
        FROM  (SELECT notice_ar, notice_en
               FROM   svc_exams
               ORDER  BY created_at DESC, exam_id DESC)
        WHERE  ROWNUM = 1;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          NULL;  -- first exam: no notice to copy yet
      END;

      INSERT INTO svc_exams (exam_type_code, exam_month, academic_year, term_no, notice_ar, notice_en)
      VALUES (p_exam_type_code, TRUNC(p_exam_month, 'MM'), p_academic_year, p_term_no, l_ar, l_en)
      RETURNING exam_id INTO l_exam_id;

      INSERT INTO svc_sessions (exam_id, room_id, period)
      SELECT l_exam_id, r.room_id, p.period
      FROM   svc_rooms r
      CROSS JOIN (SELECT 'MORNING'   AS period FROM dual UNION ALL
                  SELECT 'AFTERNOON' AS period FROM dual) p;
    ELSIF p_exam_month IS NOT NULL THEN
      UPDATE svc_exams
      SET    exam_month = TRUNC(p_exam_month, 'MM')
      WHERE  exam_id = l_exam_id;
    END IF;

    IF p_programs IS NOT NULL THEN
      DELETE FROM svc_exam_programs WHERE exam_id = l_exam_id;

      INSERT INTO svc_exam_programs (exam_id, program_code)
      SELECT DISTINCT l_exam_id, TRIM(REGEXP_SUBSTR(p_programs, '[^:]+', 1, LEVEL))
      FROM   dual
      CONNECT BY REGEXP_SUBSTR(p_programs, '[^:]+', 1, LEVEL) IS NOT NULL;
    END IF;

    RETURN l_exam_id;
  END open_exam;

  FUNCTION get_student_id (p_full_name IN VARCHAR2) RETURN NUMBER IS
    l_name svc_students.full_name%TYPE;
    l_id   svc_students.student_id%TYPE;
  BEGIN
    l_name := TRIM(REGEXP_REPLACE(p_full_name, '[[:space:]]+', ' '));
    IF l_name IS NULL THEN
      RAISE_APPLICATION_ERROR(-20001, 'Enter the student''s full name.');
    END IF;

    SELECT MIN(student_id)
    INTO   l_id
    FROM   svc_students
    WHERE  UPPER(full_name) = UPPER(l_name);

    IF l_id IS NULL THEN
      INSERT INTO svc_students (full_name)
      VALUES (l_name)
      RETURNING student_id INTO l_id;
    END IF;

    RETURN l_id;
  END get_student_id;

  PROCEDURE escalate (p_incident_id IN NUMBER) IS
  BEGIN
    UPDATE svc_incidents
    SET    incident_level = CASE incident_level
                              WHEN 'WARNING_1' THEN 'WARNING_2'
                              WHEN 'WARNING_2' THEN 'WARNING_3'
                              ELSE 'CHEATING_REPORT'
                            END,
           recorded_at    = SYSTIMESTAMP,
           recorded_by    = current_app_user
    WHERE  incident_id = p_incident_id;

    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'Warning record ' || p_incident_id || ' was not found.');
    END IF;
  END escalate;

  PROCEDURE record_warning (p_session_id     IN NUMBER,
                            p_student_name   IN VARCHAR2,
                            p_violation_code IN VARCHAR2 DEFAULT NULL,
                            p_notes          IN VARCHAR2 DEFAULT NULL) IS
    l_student_id  svc_students.student_id%TYPE;
    l_incident_id svc_incidents.incident_id%TYPE;
  BEGIN
    l_student_id := get_student_id(p_student_name);

    SELECT MIN(incident_id)
    INTO   l_incident_id
    FROM   svc_incidents
    WHERE  session_id = p_session_id
    AND    student_id = l_student_id;

    IF l_incident_id IS NULL THEN
      INSERT INTO svc_incidents (session_id, student_id, violation_code, notes, recorded_by)
      VALUES (p_session_id, l_student_id, p_violation_code, p_notes, current_app_user);
    ELSE
      escalate(l_incident_id);
      UPDATE svc_incidents
      SET    violation_code = NVL(p_violation_code, violation_code),
             notes          = NVL(p_notes, notes)
      WHERE  incident_id = l_incident_id;
    END IF;
  END record_warning;

  PROCEDURE mark_absent (p_session_id   IN NUMBER,
                         p_student_name IN VARCHAR2) IS
    l_student_id svc_students.student_id%TYPE;
  BEGIN
    l_student_id := get_student_id(p_student_name);

    INSERT INTO svc_absentees (session_id, student_id)
    SELECT p_session_id, l_student_id
    FROM   dual
    WHERE  NOT EXISTS (SELECT 1
                       FROM   svc_absentees
                       WHERE  session_id = p_session_id
                       AND    student_id = l_student_id);
  END mark_absent;

  FUNCTION theme_css (p_theme_code IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
    l_css VARCHAR2(2000);
  BEGIN
    SELECT ':root{'
        || '--svc-primary:'   || primary_hex  || ';'
        || '--svc-banner:'    || banner_hex   || ';'
        || '--svc-warning-1:' || warning1_hex || ';'
        || '--svc-warning-2:' || warning2_hex || ';'
        || '--svc-warning-3:' || warning3_hex || ';'
        || '--svc-cheating:'  || cheating_hex || ';'
        || '--svc-notice:'    || notice_hex   || ';'
        || '--svc-absent:'    || absent_hex   || ';'
        -- Universal Theme variables, so buttons and the header follow the theme
        || '--ut-palette-primary:'         || primary_hex || ';'
        || '--ut-header-background-color:' || primary_hex || ';'
        || '}'
    INTO   l_css
    FROM  (SELECT t.*
           FROM   svc_themes t
           WHERE  t.theme_code = p_theme_code
              OR  t.is_default = 'Y'
           ORDER  BY CASE WHEN t.theme_code = p_theme_code THEN 0 ELSE 1 END)
    WHERE  ROWNUM = 1;

    RETURN l_css;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN NULL;
  END theme_css;

  FUNCTION user_theme_css (p_app_user IN VARCHAR2) RETURN VARCHAR2 IS
    l_code svc_user_prefs.theme_code%TYPE;
  BEGIN
    SELECT MAX(theme_code)
    INTO   l_code
    FROM   svc_user_prefs
    WHERE  app_user = UPPER(p_app_user);

    RETURN theme_css(l_code);
  END user_theme_css;

  PROCEDURE save_user_theme (p_app_user   IN VARCHAR2,
                             p_theme_code IN VARCHAR2,
                             p_color_mode IN VARCHAR2 DEFAULT 'AUTO') IS
  BEGIN
    MERGE INTO svc_user_prefs t
    USING (SELECT UPPER(p_app_user) AS app_user FROM dual) src
    ON (t.app_user = src.app_user)
    WHEN MATCHED THEN
      UPDATE SET t.theme_code = p_theme_code,
                 t.color_mode = NVL(p_color_mode, 'AUTO')
    WHEN NOT MATCHED THEN
      INSERT (app_user, theme_code, color_mode)
      VALUES (src.app_user, p_theme_code, NVL(p_color_mode, 'AUTO'));
  END save_user_theme;

  FUNCTION user_role (p_app_user IN VARCHAR2) RETURN VARCHAR2 IS
    l_role svc_app_users.app_role%TYPE;
  BEGIN
    SELECT MAX(app_role)
    INTO   l_role
    FROM   svc_app_users
    WHERE  app_user  = UPPER(p_app_user)
    AND    is_active = 'Y';

    RETURN l_role;
  END user_role;

  FUNCTION is_admin (p_app_user IN VARCHAR2) RETURN BOOLEAN IS
  BEGIN
    RETURN NVL(user_role(p_app_user), 'NONE') IN ('OWNER', 'ADMIN');
  END is_admin;

  PROCEDURE post_message (p_body IN VARCHAR2) IS
    l_body svc_chat_messages.body%TYPE;
  BEGIN
    l_body := SUBSTR(TRIM(p_body), 1, 1000);
    IF l_body IS NULL THEN
      RETURN;  -- nothing to send
    END IF;
    INSERT INTO svc_chat_messages (app_user, body)
    VALUES (UPPER(current_app_user), l_body);
  END post_message;

  PROCEDURE delete_message (p_message_id IN NUMBER) IS
  BEGIN
    DELETE FROM svc_chat_messages
    WHERE  message_id = p_message_id
    AND   (app_user = UPPER(current_app_user) OR is_admin(current_app_user));

    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20020, 'You can delete only your own messages.');
    END IF;
  END delete_message;

  PROCEDURE clear_chat IS
  BEGIN
    IF NOT is_admin(current_app_user) THEN
      RAISE_APPLICATION_ERROR(-20021, 'Only the administrator can clear the chat.');
    END IF;
    DELETE FROM svc_chat_messages;
  END clear_chat;

END svc_exam_pkg;
/


-- =====================================================================
-- 6. REFERENCE DATA
-- =====================================================================
INSERT INTO svc_exam_types (exam_type_code, label_en, label_ar, sort_order)
SELECT 'MIDTERM', 'Midterm Exam', 'الاختبار النصفي',  1 FROM dual UNION ALL
SELECT 'FINAL',   'Final Exam',   'الاختبار النهائي', 2 FROM dual;

INSERT INTO svc_programs (program_code, label_en, label_ar, sort_order)
SELECT 'PREPARATORY',      'Preparatory',      'البرنامج التحضيري', 1 FROM dual UNION ALL
SELECT 'POST_PREPARATORY', 'Post-Preparatory', 'ما بعد التحضيري',   2 FROM dual;

-- Same order as the tabs in the Google Sheet
INSERT INTO svc_rooms (room_name, room_type, sort_order)
SELECT 'Room 1',           'ROOM',  1 FROM dual UNION ALL
SELECT 'Room 2',           'ROOM',  2 FROM dual UNION ALL
SELECT 'Room 3',           'ROOM',  3 FROM dual UNION ALL
SELECT 'Room 4',           'ROOM',  4 FROM dual UNION ALL
SELECT 'Room 5',           'ROOM',  5 FROM dual UNION ALL
SELECT 'Room 6',           'ROOM',  6 FROM dual UNION ALL
SELECT 'Room 7',           'ROOM',  7 FROM dual UNION ALL
SELECT 'Room 13',          'ROOM',  8 FROM dual UNION ALL
SELECT 'Room 17',          'ROOM',  9 FROM dual UNION ALL
SELECT 'Room 12',          'ROOM', 10 FROM dual UNION ALL
SELECT 'Room 101',         'ROOM', 11 FROM dual UNION ALL
SELECT 'Room 102',         'ROOM', 12 FROM dual UNION ALL
SELECT 'Room 103',         'ROOM', 13 FROM dual UNION ALL
SELECT 'Room 104',         'ROOM', 14 FROM dual UNION ALL
SELECT 'Room 105',         'ROOM', 15 FROM dual UNION ALL
SELECT 'Room 106',         'ROOM', 16 FROM dual UNION ALL
SELECT 'Lab 1',            'LAB',  17 FROM dual UNION ALL
SELECT 'Lab 2',            'LAB',  18 FROM dual UNION ALL
SELECT 'Lab 3',            'LAB',  19 FROM dual UNION ALL
SELECT 'Lab 4',            'LAB',  20 FROM dual UNION ALL
SELECT 'Old Drawing Hall', 'HALL', 21 FROM dual UNION ALL
SELECT 'New Drawing Hall', 'HALL', 22 FROM dual UNION ALL
SELECT 'Chemistry Lab',    'LAB',  23 FROM dual UNION ALL
SELECT 'Physics Lab',      'LAB',  24 FROM dual;

-- Staff: placeholder names. Replace them with your own staff list, or add
-- people from the admin Staff page after the script has run.
INSERT INTO svc_staff (title, full_name, is_invigilator, is_floor_invigilator)
SELECT NULL, 'Invigilator 01', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 02', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 03', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 04', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 05', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 06', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 07', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 08', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 09', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 10', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 11', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 12', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 13', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 14', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 15', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 16', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 17', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 18', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 19', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 20', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 21', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 22', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 23', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 24', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 25', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 26', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 27', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 28', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 29', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 30', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 31', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 32', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 33', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 34', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 35', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 36', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 37', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 38', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 39', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 40', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 41', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 42', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 43', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 44', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 45', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 46', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 47', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 48', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 49', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 50', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 51', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 52', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 53', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 54', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 55', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 56', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 57', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 58', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 59', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 60', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 61', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 62', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 63', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Invigilator 64', 'Y', 'N' FROM dual UNION ALL
SELECT NULL, 'Floor Invigilator 01', 'N', 'Y' FROM dual UNION ALL
SELECT NULL, 'Floor Invigilator 02', 'N', 'Y' FROM dual UNION ALL
SELECT NULL, 'Floor Invigilator 03', 'N', 'Y' FROM dual UNION ALL
SELECT NULL, 'Floor Invigilator 04', 'N', 'Y' FROM dual UNION ALL
SELECT NULL, 'Floor Invigilator 05', 'N', 'Y' FROM dual UNION ALL
SELECT NULL, 'Floor Invigilator 06', 'N', 'Y' FROM dual UNION ALL
SELECT NULL, 'Floor Invigilator 07', 'N', 'Y' FROM dual UNION ALL
SELECT NULL, 'Floor Invigilator 08', 'N', 'Y' FROM dual UNION ALL
SELECT NULL, 'Floor Invigilator 09', 'N', 'Y' FROM dual UNION ALL
SELECT NULL, 'Floor Invigilator 10', 'N', 'Y' FROM dual UNION ALL
SELECT NULL, 'Floor Invigilator 11', 'N', 'Y' FROM dual UNION ALL
SELECT NULL, 'Floor Invigilator 12', 'N', 'Y' FROM dual UNION ALL
SELECT NULL, 'Floor Invigilator 13', 'N', 'Y' FROM dual UNION ALL
SELECT NULL, 'Floor Invigilator 14', 'N', 'Y' FROM dual UNION ALL
SELECT NULL, 'Floor Invigilator 15', 'N', 'Y' FROM dual UNION ALL
SELECT NULL, 'Floor Invigilator 16', 'N', 'Y' FROM dual UNION ALL
SELECT NULL, 'Sample Coordinator', 'N', 'N' FROM dual;

-- Courses from the timetable (Soft Skills and Oman: State and Human removed)
INSERT INTO svc_courses (course_code, course_name, specialization, sort_order)
SELECT NULL        , 'English Level 1', 'Foundation', 1 FROM dual UNION ALL
SELECT NULL        , 'English Level 2', 'Foundation', 2 FROM dual UNION ALL
SELECT NULL        , 'English Level 3', 'Foundation', 3 FROM dual UNION ALL
SELECT NULL        , 'Computing Skills', 'Foundation', 4 FROM dual UNION ALL
SELECT NULL        , 'Math for Foundation', 'Foundation', 5 FROM dual UNION ALL
SELECT NULL        , 'Engineering Drawing 1', 'Foundation', 6 FROM dual UNION ALL
SELECT NULL        , 'Engineering Drawing 2', 'Foundation', 7 FROM dual UNION ALL
SELECT 'CHEM1101'  , 'Chemistry 1', 'Shared courses', 8 FROM dual UNION ALL
SELECT 'CHEM1202'  , 'Chemistry 2', 'Shared courses', 9 FROM dual UNION ALL
SELECT 'MTCL1101'  , 'Calculus', 'Shared courses', 10 FROM dual UNION ALL
SELECT 'MTEN1202'  , 'Engineering Math', 'Shared courses', 11 FROM dual UNION ALL
SELECT 'MTST1101'  , 'Statistics', 'Shared courses', 12 FROM dual UNION ALL
SELECT 'PHYS1101'  , 'Physics 1', 'Shared courses', 13 FROM dual UNION ALL
SELECT 'PHYS1202'  , 'Physics 2', 'Shared courses', 14 FROM dual UNION ALL
SELECT 'INTE1202'  , 'Introduction to Programming (C++)', 'Shared courses', 15 FROM dual UNION ALL
SELECT 'TWENG1101' , 'Technical Writing', 'Shared courses', 16 FROM dual UNION ALL
SELECT 'TCENG1202' , 'Technical Communication', 'Shared courses', 17 FROM dual UNION ALL
SELECT 'PSENG1303' , 'Public Speaking', 'Shared courses', 18 FROM dual UNION ALL
SELECT 'ENTRP1101' , 'Entrepreneurship 1', 'Shared courses', 19 FROM dual UNION ALL
SELECT 'ENTRP1202' , 'Entrepreneurship 2', 'Shared courses', 20 FROM dual UNION ALL
SELECT 'EELIE1101' , 'Health & Safety Precautions', 'Industrial Electricity', 21 FROM dual UNION ALL
SELECT 'EELIE1102' , 'Basic Electricity (AC/DC) & Electrical Code', 'Industrial Electricity', 22 FROM dual UNION ALL
SELECT 'EELIE1203' , 'Tools, Instruments, Electric Wires and Cables Work', 'Industrial Electricity', 23 FROM dual UNION ALL
SELECT 'EELIE1204' , 'Basic Electronics', 'Industrial Electricity', 24 FROM dual UNION ALL
SELECT 'EELIE1305' , 'Electrical Circuits & Protection Devices', 'Industrial Electricity', 25 FROM dual UNION ALL
SELECT 'EELIE1306' , 'Three Phase Principles', 'Industrial Electricity', 26 FROM dual UNION ALL
SELECT 'EELIE2107' , 'Industrial Transformers', 'Industrial Electricity', 27 FROM dual UNION ALL
SELECT 'EELIE2108' , 'Industrial Motors and Controllers', 'Industrial Electricity', 28 FROM dual UNION ALL
SELECT 'EELIE2209' , 'Industrial Switchboards', 'Industrial Electricity', 29 FROM dual UNION ALL
SELECT 'EELIE2210' , 'Graduation Project 1', 'Industrial Electricity', 30 FROM dual UNION ALL
SELECT 'EELIE2211' , 'Power Electronics', 'Industrial Electricity', 31 FROM dual UNION ALL
SELECT 'EELIE2312' , 'PLC & Regulation Systems', 'Industrial Electricity', 32 FROM dual UNION ALL
SELECT 'EELIE2313' , 'Electrical General Maintenance', 'Industrial Electricity', 33 FROM dual UNION ALL
SELECT 'EELIE2314' , 'Graduation Project 2', 'Industrial Electricity', 34 FROM dual UNION ALL
SELECT 'EECIM1101' , 'Basic Electricity and System', 'Electronic Instrument Maintenance', 35 FROM dual UNION ALL
SELECT 'EECIM1102' , 'Basic Electronics and Circuits', 'Electronic Instrument Maintenance', 36 FROM dual UNION ALL
SELECT 'EECIM1203' , 'Fundamental Digital Electronics and Circuits', 'Electronic Instrument Maintenance', 37 FROM dual UNION ALL
SELECT 'EECIM1204' , 'Installation, Service and Maintenance of Audio-Video Systems', 'Electronic Instrument Maintenance', 38 FROM dual UNION ALL
SELECT 'EECIM1305' , 'Switched Mode Power, Auto-volt and Uninterruptible Power Supply Systems', 'Electronic Instrument Maintenance', 39 FROM dual UNION ALL
SELECT 'EECIM1306' , 'Electronic Devices Servicing I', 'Electronic Instrument Maintenance', 40 FROM dual UNION ALL
SELECT 'EECIM2107' , 'Personal Computer & Multimedia Devices', 'Electronic Instrument Maintenance', 41 FROM dual UNION ALL
SELECT 'EECIM2108' , 'Computer System Data Communication and Internet', 'Electronic Instrument Maintenance', 42 FROM dual UNION ALL
SELECT 'EECIM2209' , 'Graduation Project 1', 'Electronic Instrument Maintenance', 43 FROM dual UNION ALL
SELECT 'EECIM2210' , 'Security and Alarm System', 'Electronic Instrument Maintenance', 44 FROM dual UNION ALL
SELECT 'EECIM2311' , 'Electronic Devices Servicing II', 'Electronic Instrument Maintenance', 45 FROM dual UNION ALL
SELECT 'EECIM2312' , 'Graduation Project 2', 'Electronic Instrument Maintenance', 46 FROM dual UNION ALL
SELECT 'ECBID1101' , 'Fundamentals of Design', 'Interior Design', 47 FROM dual UNION ALL
SELECT 'ECBID1102' , 'Architectural Drawing', 'Interior Design', 48 FROM dual UNION ALL
SELECT 'ECBID1203' , 'Drawing Skills 1', 'Interior Design', 49 FROM dual UNION ALL
SELECT 'ECBID1404' , 'Design Studio (1): Residential Design', 'Interior Design', 50 FROM dual UNION ALL
SELECT 'ECBID1305' , 'Drawing Skills 2', 'Interior Design', 51 FROM dual UNION ALL
SELECT 'ECBID1306' , 'Computer for Interior Design 1', 'Interior Design', 52 FROM dual UNION ALL
SELECT 'ECBID1307' , 'History of Design 1', 'Interior Design', 53 FROM dual UNION ALL
SELECT 'ECBID2108' , 'Design Studio (2): Commercial Design', 'Interior Design', 54 FROM dual UNION ALL
SELECT 'ECBID2109' , 'History of Design 2', 'Interior Design', 55 FROM dual UNION ALL
SELECT 'ECBID2110' , 'Computer for Interior Design 2', 'Interior Design', 56 FROM dual UNION ALL
SELECT 'ECBID2211' , 'Design Studio (3): Administrative Design', 'Interior Design', 57 FROM dual UNION ALL
SELECT 'ECBID2212' , 'Quantity Survey', 'Interior Design', 58 FROM dual UNION ALL
SELECT 'ECBID2213' , 'Project 1', 'Interior Design', 59 FROM dual UNION ALL
SELECT 'ECBID2214' , 'Entrepreneurship 1', 'Interior Design', 60 FROM dual UNION ALL
SELECT 'ECBID2314' , 'Architectural Models', 'Interior Design', 61 FROM dual UNION ALL
SELECT 'ECBID2315' , 'Project 2', 'Interior Design', 62 FROM dual UNION ALL
SELECT 'ITPH1202'  , 'Introduction to Photoshop CS6', 'Interior Design', 63 FROM dual UNION ALL
SELECT 'MTID1101'  , 'Math for Design', 'Interior Design', 64 FROM dual UNION ALL
SELECT 'GBIO1101'  , 'General Biology', 'Food Safety and Quality Control', 65 FROM dual UNION ALL
SELECT 'BCHEM1101' , 'Biochemistry', 'Food Safety and Quality Control', 66 FROM dual UNION ALL
SELECT 'MSFQ1101'  , 'Food Microbiology', 'Food Safety and Quality Control', 67 FROM dual UNION ALL
SELECT 'MSFQ1102'  , 'Occupational Safety and First Aid', 'Food Safety and Quality Control', 68 FROM dual UNION ALL
SELECT 'MSFQ1202'  , 'Oceanography', 'Food Safety and Quality Control', 69 FROM dual UNION ALL
SELECT 'MSFQ1203'  , 'Marine Biology', 'Food Safety and Quality Control', 70 FROM dual UNION ALL
SELECT 'MSFQ1305'  , 'Food Quality Control', 'Food Safety and Quality Control', 71 FROM dual UNION ALL
SELECT 'MSFQ1306'  , 'Food Legislation', 'Food Safety and Quality Control', 72 FROM dual UNION ALL
SELECT 'MSFQ1307'  , 'Food Safety', 'Food Safety and Quality Control', 73 FROM dual UNION ALL
SELECT 'MSFQ2108'  , 'Advanced Seafood Safety', 'Food Safety and Quality Control', 74 FROM dual UNION ALL
SELECT 'MSFQ2109'  , 'Seafood Processing Technology 1', 'Food Safety and Quality Control', 75 FROM dual UNION ALL
SELECT 'MSFQ2109'  , 'Seafood Processing Technology 2', 'Food Safety and Quality Control', 76 FROM dual UNION ALL
SELECT 'MSFQ2110'  , 'Scientific Instrument', 'Food Safety and Quality Control', 77 FROM dual UNION ALL
SELECT 'MSFQ2110'  , 'Field Work 2', 'Food Safety and Quality Control', 78 FROM dual UNION ALL
SELECT 'MSFQ2111'  , 'Graduation Project', 'Food Safety and Quality Control', 79 FROM dual UNION ALL
SELECT 'MSFQ2317'  , 'Fishing Gears & Methods', 'Food Safety and Quality Control', 80 FROM dual UNION ALL
SELECT 'MSFQ2318'  , 'Marine Navigation', 'Food Safety and Quality Control', 81 FROM dual UNION ALL
SELECT 'MSFQ2319'  , 'Marine Engine', 'Food Safety and Quality Control', 82 FROM dual UNION ALL
SELECT 'MSFQ2320'  , 'Field Work 3', 'Food Safety and Quality Control', 83 FROM dual UNION ALL
SELECT 'TCENG1201' , 'Technical Communication', 'Food Safety and Quality Control', 84 FROM dual UNION ALL
SELECT 'PSENG1301' , 'Public Speaking', 'Food Safety and Quality Control', 85 FROM dual UNION ALL
SELECT 'BBSSM2302' , 'Sales Management', 'Selling & Marketing', 86 FROM dual UNION ALL
SELECT 'BBSSM2204' , 'Graduation Project', 'Selling & Marketing', 87 FROM dual UNION ALL
SELECT 'INBS1202'  , 'E-Commerce', 'Selling & Marketing', 88 FROM dual UNION ALL
SELECT NULL        , 'Principles of Marketing', 'Selling & Marketing', 89 FROM dual UNION ALL
SELECT NULL        , 'Economics Issues', 'Selling & Marketing', 90 FROM dual UNION ALL
SELECT NULL        , 'Introduction to Business', 'Selling & Marketing', 91 FROM dual UNION ALL
SELECT NULL        , 'Statistics', 'Selling & Marketing', 92 FROM dual UNION ALL
SELECT NULL        , 'Marketing Communication', 'Selling & Marketing', 93 FROM dual UNION ALL
SELECT NULL        , 'Business Ethics', 'Selling & Marketing', 94 FROM dual UNION ALL
SELECT NULL        , 'Business Math', 'Selling & Marketing', 95 FROM dual UNION ALL
SELECT NULL        , 'Consumer Behavior', 'Selling & Marketing', 96 FROM dual UNION ALL
SELECT NULL        , 'Advertising & Promotion', 'Selling & Marketing', 97 FROM dual UNION ALL
SELECT NULL        , 'Introduction to Selling', 'Selling & Marketing', 98 FROM dual UNION ALL
SELECT NULL        , 'Principles of Management', 'Selling & Marketing', 99 FROM dual UNION ALL
SELECT NULL        , 'Service Marketing', 'Selling & Marketing', 100 FROM dual UNION ALL
SELECT NULL        , 'Retailing Management', 'Selling & Marketing', 101 FROM dual UNION ALL
SELECT NULL        , 'Professional Selling', 'Selling & Marketing', 102 FROM dual UNION ALL
SELECT NULL        , 'Retail Pricing Strategies', 'Selling & Marketing', 103 FROM dual UNION ALL
SELECT NULL        , 'Business Research', 'Selling & Marketing', 104 FROM dual UNION ALL
SELECT NULL        , 'Consumer''s Relationship Management', 'Selling & Marketing', 105 FROM dual UNION ALL
SELECT NULL        , 'Entrepreneurship (General)', 'Selling & Marketing', 106 FROM dual UNION ALL
SELECT NULL        , 'Introduction to Business', 'Warehousing & Logistics Management', 107 FROM dual UNION ALL
SELECT NULL        , 'Statistics', 'Warehousing & Logistics Management', 108 FROM dual UNION ALL
SELECT NULL        , 'Principles of Management', 'Warehousing & Logistics Management', 109 FROM dual UNION ALL
SELECT NULL        , 'Supply Chain Management', 'Warehousing & Logistics Management', 110 FROM dual UNION ALL
SELECT NULL        , 'اللغة الإنجليزية أ', 'Other courses', 111 FROM dual UNION ALL
SELECT NULL        , 'تقنية المعلومات أ', 'Other courses', 112 FROM dual UNION ALL
SELECT NULL        , 'ريادة الأعمال', 'Other courses', 113 FROM dual UNION ALL
SELECT NULL        , 'علوم مهنة', 'Other courses', 114 FROM dual;

INSERT INTO svc_violation_types (violation_code, label_en, label_ar, sort_order)
SELECT 'COPYING', 'Copying',         'نسخ',             1 FROM dual UNION ALL
SELECT 'SHARING', 'Sharing answers', 'تبادل الإجابات',  2 FROM dual UNION ALL
SELECT 'MOBILE',  'Mobile',          'استخدام الهاتف',  3 FROM dual UNION ALL
SELECT 'TALKING', 'Talking',         'التحدث',          4 FROM dual;

INSERT INTO svc_themes (theme_code, theme_name, primary_hex, banner_hex, warning1_hex, warning2_hex,
                        warning3_hex, cheating_hex, notice_hex, absent_hex, is_default)
SELECT 'SHEET',        'Sheet Classic', '#3E7C87', '#19D3E0', '#F2A43A', '#8AB4F0', '#E53935', '#E9B824', '#16BFD1', '#F4D514', 'Y' FROM dual UNION ALL
SELECT 'KHAREEF',      'Khareef Green', '#2D7A4E', '#6DBE8C', '#E9A23B', '#86B7DE', '#D64545', '#CFA72E', '#3FB58F', '#E9D45E', 'N' FROM dual UNION ALL
SELECT 'FRANKINCENSE', 'Frankincense',  '#8A5A2C', '#D2A86A', '#E39E48', '#A2B9D4', '#C6463B', '#D9B23C', '#C49A62', '#EAD27C', 'N' FROM dual UNION ALL
SELECT 'ARABIAN_SEA',  'Arabian Sea',   '#1F4F8A', '#4A98D6', '#F0A94B', '#93BCEE', '#E0473F', '#E4B530', '#2CA9CC', '#EFD55E', 'N' FROM dual UNION ALL
SELECT 'SLATE',        'Slate',         '#3B4553', '#8796A8', '#E2A55A', '#A9BCD5', '#D2554F', '#CDAA48', '#7D9AAE', '#DCCB7C', 'N' FROM dual;

-- The person running this script becomes the portal OWNER.
-- Check it afterwards with: SELECT * FROM svc_app_users;
-- If it is not your APEX login name, update it, for example:
--   UPDATE svc_app_users SET app_user = 'YOUR.LOGIN' WHERE app_role = 'OWNER';
-- Add other people the same way, for example:
--   INSERT INTO svc_app_users (app_user, app_role) VALUES ('ALI.R', 'FLOOR_INVIGILATOR');
INSERT INTO svc_app_users (app_user, app_role)
VALUES (UPPER(COALESCE(SYS_CONTEXT('APEX$SESSION', 'APP_USER'), USER)), 'OWNER');

-- The current exam: Midterm Exam, Preparatory - Post-Preparatory,
-- November 2026, academic year 2026-2027, Term 1 (creates all 48 room sheets)
DECLARE
  l_exam_id svc_exams.exam_id%TYPE;
BEGIN
  l_exam_id := svc_exam_pkg.open_exam(p_exam_type_code => 'MIDTERM',
                                      p_academic_year  => '2026-2027',
                                      p_term_no        => 1,
                                      p_exam_month     => DATE '2026-11-01',
                                      p_programs       => 'PREPARATORY:POST_PREPARATORY');
  UPDATE svc_exams
  SET    notice_ar = 'يسمح للطالب بالذهاب إلى دورة المياه في أول 15 دقيقة من بدء الاختبار',
         notice_en = 'Students are allowed to go to washrooms during the first 15 minutes of the exam commencement.'
  WHERE  exam_id = l_exam_id;
END;
/


-- =====================================================================
-- 7. SAMPLE DATA FOR ROOM 13 (Morning) - placeholder student names; replace with your own
-- =====================================================================
UPDATE svc_sessions s
SET    s.invigilator1_id      = (SELECT staff_id FROM svc_staff WHERE full_name = 'Invigilator 01'),
       s.floor_invigilator_id = (SELECT staff_id FROM svc_staff WHERE full_name = 'Floor Invigilator 01'),
       s.coordinator_id       = (SELECT staff_id FROM svc_staff WHERE full_name = 'Sample Coordinator')
WHERE  s.period  = 'MORNING'
AND    s.room_id = (SELECT room_id FROM svc_rooms WHERE room_name = 'Room 13');

DECLARE
  l_session_id svc_sessions.session_id%TYPE;
BEGIN
  SELECT s.session_id
  INTO   l_session_id
  FROM   svc_sessions s
  JOIN   svc_rooms    r ON r.room_id = s.room_id
  WHERE  r.room_name = 'Room 13'
  AND    s.period    = 'MORNING';

  svc_exam_pkg.record_warning(l_session_id, 'Sample Student 1');
  svc_exam_pkg.record_warning(l_session_id, 'Sample Student 2');
  svc_exam_pkg.record_warning(l_session_id, 'Sample Student 3');

  svc_exam_pkg.mark_absent(l_session_id, 'Sample Student 4');
END;
/

COMMIT;


-- =====================================================================
-- 8. END-OF-DAY REPORT EXPORT (administrators only)
-- Needs Oracle APEX 20.2 or later (APEX_DATA_EXPORT). It is a separate
-- package, so the rest of the script still works without APEX.
-- The admin check runs here on the server as well as on the page, so
-- an invigilator cannot download the report even with a direct link.
-- =====================================================================
CREATE OR REPLACE PACKAGE svc_report_pkg AS

  -- p_dataset : SESSIONS, WARNINGS or ABSENTEES
  -- p_format  : XLSX, CSV or HTML
  PROCEDURE download (p_dataset IN VARCHAR2 DEFAULT 'SESSIONS',
                      p_format  IN VARCHAR2 DEFAULT 'XLSX');

END svc_report_pkg;
/

CREATE OR REPLACE PACKAGE BODY svc_report_pkg AS

  PROCEDURE download (p_dataset IN VARCHAR2 DEFAULT 'SESSIONS',
                      p_format  IN VARCHAR2 DEFAULT 'XLSX') IS
    l_context apex_exec.t_context;
    l_export  apex_data_export.t_export;
    l_sql     VARCHAR2(4000);
  BEGIN
    IF NOT svc_exam_pkg.is_admin(SYS_CONTEXT('APEX$SESSION', 'APP_USER')) THEN
      RAISE_APPLICATION_ERROR(-20010, 'Only the administrator can download the end-of-day report.');
    END IF;

    -- Only the exam chosen in the dropdowns (page item P0_EXAM_ID);
    -- every exam when no exam is chosen.
    l_sql := CASE UPPER(p_dataset)
      WHEN 'WARNINGS' THEN
        'SELECT room_name, period, student_name, level_label, violation_en, violation_ar,'
        || ' notes, recorded_at, recorded_by'
        || ' FROM svc_v_incidents'
        || ' WHERE exam_id = NVL(TO_NUMBER(V(''P0_EXAM_ID'')), exam_id)'
        || ' ORDER BY sort_order, period DESC, student_name'
      WHEN 'ABSENTEES' THEN
        'SELECT r.room_name, s.period, st.full_name AS student_name'
        || ' FROM svc_absentees a'
        || ' JOIN svc_sessions s  ON s.session_id  = a.session_id'
        || ' JOIN svc_rooms r     ON r.room_id     = s.room_id'
        || ' JOIN svc_students st ON st.student_id = a.student_id'
        || ' WHERE s.exam_id = NVL(TO_NUMBER(V(''P0_EXAM_ID'')), s.exam_id)'
        || ' ORDER BY r.sort_order, s.period DESC, st.full_name'
      ELSE
        'SELECT exam_name, programs, exam_month, academic_year, term_no,'
        || ' room_name, room_type, period, exam_date, exam_day, course_code, course_name,'
        || ' no_present, no_absent, total_students, warning_1, warning_2, warning_3,'
        || ' cheating_reports, invigilator_1, invigilator_2, floor_invigilator,'
        || ' coordinator, session_status'
        || ' FROM svc_v_session_summary'
        || ' WHERE exam_id = NVL(TO_NUMBER(V(''P0_EXAM_ID'')), exam_id)'
        || ' ORDER BY sort_order, period DESC'
    END;

    l_context := apex_exec.open_query_context(
                   p_location  => apex_exec.c_location_local_db,
                   p_sql_query => l_sql);
    BEGIN
      l_export := apex_data_export.export(
                    p_context   => l_context,
                    p_format    => CASE UPPER(p_format)
                                     WHEN 'CSV'  THEN apex_data_export.c_format_csv
                                     WHEN 'HTML' THEN apex_data_export.c_format_html
                                     ELSE apex_data_export.c_format_xlsx
                                   END,
                    p_file_name => 'svc_' || LOWER(p_dataset) || '_' || TO_CHAR(SYSDATE, 'YYYY-MM-DD'));
      apex_exec.close(l_context);
    EXCEPTION
      WHEN OTHERS THEN
        apex_exec.close(l_context);
        RAISE;
    END;

    -- Sends the file to the browser and ends the page request
    apex_data_export.download(p_export => l_export);
  END download;

END svc_report_pkg;
/


-- =====================================================================
-- 9. QUICK CHECKS
-- Expected: 24 rooms, 48 sessions, one OWNER, and Room 13 Morning with
-- 3 warnings, 1 absentee and status IN PROGRESS.
-- =====================================================================
SELECT COUNT(*) AS rooms    FROM svc_rooms;
SELECT COUNT(*) AS sessions FROM svc_sessions;
SELECT app_user, app_role   FROM svc_app_users;

SELECT room_name, period, warning_1, no_absent,
       invigilator_1, floor_invigilator, coordinator, session_status
FROM   svc_v_session_summary
WHERE  room_name = 'Room 13'
ORDER  BY period DESC;


/* =====================================================================
   10. BUILDING THE APEX APPLICATION
   ---------------------------------------------------------------------
   a) App Builder > Create > New Application
        Name : SVC Exam Portal
        Theme: Universal Theme (Redwood Light or Vita)
      Add these pages in the wizard:
        Dashboard     Cards on SVC_V_SESSION_SUMMARY
        Room Sheet    Form on SVC_SESSIONS (primary key SESSION_ID)
        All Sessions  Interactive Report on SVC_V_SESSION_SUMMARY
        Warnings      Interactive Report on SVC_V_INCIDENTS

   b) Room navigation (the sheet tabs)
      Shared Components > Lists > Navigation Menu > change to Dynamic,
      using this query (page 2 = Room Sheet):

        SELECT NULL      AS lvl,
               room_name AS label,
               APEX_PAGE.GET_URL(p_page   => 2,
                                 p_items  => 'P2_ROOM_ID,P2_PERIOD',
                                 p_values => room_id || ',MORNING') AS target
        FROM   svc_rooms
        ORDER  BY sort_order

      On page 2 add a Before Header computation for P2_SESSION_ID
      (SQL Query, single value):

        SELECT MAX(session_id)
        FROM   svc_sessions
        WHERE  room_id = :P2_ROOM_ID
        AND    period  = NVL(:P2_PERIOD, 'MORNING')
        AND    exam_id = :P0_EXAM_ID

   c) Section tabs on the Room Sheet
      Add a Region Display Selector region, then these regions with
      "Region Display Selector" set to Yes:
        Session Details  form items (date, course, no. of present)
                         P2_COURSE_ID: Popup LOV (it has a search box):
                           SELECT NVL2(course_code, course_code || ' · ', '')
                                  || course_name AS d,
                                  course_id AS r,
                                  specialization
                           FROM   svc_courses
                           WHERE  is_active = 'Y'
                           ORDER  BY sort_order
        Warnings         Interactive Grid on SVC_INCIDENTS
                         WHERE session_id = :P2_SESSION_ID
        Absentees        Interactive Grid on SVC_ABSENTEES
        Invigilators     P2_INVIGILATOR1_ID, P2_INVIGILATOR2_ID: Select Lists
                           SELECT full_name d, staff_id r FROM svc_staff
                           WHERE  is_invigilator = 'Y' AND is_active = 'Y'
                           ORDER  BY full_name
                         P2_FLOOR_INVIGILATOR_ID: Select List
                           SELECT title || ' ' || full_name d, staff_id r
                           FROM   svc_staff
                           WHERE  is_floor_invigilator = 'Y' AND is_active = 'Y'
                           ORDER  BY full_name
                         P2_COORDINATOR_ID: Select List on all active staff
        Comments         Checkbox group from SVC_VIOLATION_TYPES + COMMENTS
        Notice           Static content from SVC_EXAMS
      Escalate button (PL/SQL process):
        svc_exam_pkg.escalate(:P2_INCIDENT_ID);

   d) Colour themes
      Base look: Shared Components > Themes > Theme Roller.
      Per-user colours: on Page 0 (Global Page) add a Dynamic Content
      region (PL/SQL Function Body returning a CLOB, template Blank):

        RETURN '<style>' || svc_exam_pkg.user_theme_css(:APP_USER) || '</style>';

      Add a "Colours" page with a select list on SVC_THEMES and a
      process that saves the choice:

        svc_exam_pkg.save_user_theme(:APP_USER, :P10_THEME, :P10_MODE);

   e) Administrators only: the end-of-day report
      1. Shared Components > Authorization Schemes > Create
           Name   : Administrators only
           Type   : PL/SQL Function Returning Boolean
           Code   : RETURN svc_exam_pkg.is_admin(:APP_USER);
           Error  : Only the administrator can open the end-of-day report.
           Validate: Once per page view
      2. Create page 20 "Day Report" (Dashboard). In Page > Security set
         Authorization Scheme = Administrators only. This locks the page
         itself, so typing its address does not open it for invigilators.
      3. Navigation Bar List > add entry "Day report", icon fa-bar-chart,
         target page 20, Authorization Scheme = Administrators only.
         The icon is then shown only to OWNER and ADMIN users.
      4. Chart regions on page 20 (Chart type, source SQL Query):
           Session progress (pie/donut):
             SELECT session_status, COUNT(*) AS sessions
             FROM svc_v_session_summary GROUP BY session_status
           Warnings by level (bar):
             SELECT 'Warning 1' AS lvl, SUM(warning_1) AS n FROM svc_v_session_summary UNION ALL
             SELECT 'Warning 2', SUM(warning_2) FROM svc_v_session_summary UNION ALL
             SELECT 'Warning 3', SUM(warning_3) FROM svc_v_session_summary UNION ALL
             SELECT 'Cheating report', SUM(cheating_reports) FROM svc_v_session_summary
           Attendance by room (stacked bar, two series):
             SELECT room_name, SUM(no_present) AS present, SUM(no_absent) AS absent
             FROM svc_v_session_summary GROUP BY room_name, sort_order ORDER BY sort_order
           Warnings by reason (bar):
             SELECT NVL(violation_en, 'Not specified') AS reason, COUNT(*) AS n
             FROM svc_v_incidents GROUP BY NVL(violation_en, 'Not specified')
         Add an Interactive Report on SVC_V_SESSION_SUMMARY below the
         charts; its Actions > Download menu also exports the table.
      5. Download buttons on page 20 (each with Authorization Scheme =
         Administrators only), each running a PL/SQL process:
           Excel   : svc_report_pkg.download('SESSIONS', 'XLSX');
           CSV     : svc_report_pkg.download('SESSIONS', 'CSV');
           Warnings: svc_report_pkg.download('WARNINGS', 'XLSX');

   f) Course and staff lists (administrators only)
      Add two pages with Authorization Scheme = Administrators only:
        Courses  Interactive Grid on SVC_COURSES
        Staff    Interactive Grid on SVC_STAFF (tick Y/N for each list)
      Adding, renaming or switching off a row there updates every
      dropdown, with no change to the pages.

   g) Staff chat
      1. Create page 30 "Staff Chat", Page Mode: Drawer.
      2. Classic Report "Messages" (Static ID: chat), template Comments:
           SELECT author                                  AS user_name,
                  APEX_ESCAPE.HTML(body)                  AS comment_text,
                  TO_CHAR(posted_at, 'DD Mon HH24:MI')    AS comment_date,
                  message_id,
                  CASE WHEN app_user = UPPER(:APP_USER)
                         OR svc_exam_pkg.user_role(:APP_USER) IN ('OWNER', 'ADMIN')
                       THEN 'Y' END                       AS can_delete
           FROM   svc_v_chat
           WHERE  posted_at > SYSTIMESTAMP - INTERVAL '7' DAY
           ORDER  BY posted_at
      3. P30_MESSAGE (Textarea) and a Send button with this process,
         then refresh the report:
           svc_exam_pkg.post_message(:P30_MESSAGE);
      4. Page > JavaScript > Execute when Page Loads (new messages every
         10 seconds):
           setInterval(function () { apex.region('chat').refresh(); }, 10000);
      5. Online now (Classic Report, refresh with the messages):
           SELECT apex_user, MAX(view_date) AS last_seen
           FROM   apex_workspace_activity_log
           WHERE  application_id = :APP_ID
           AND    view_date > SYSDATE - 5 / 1440
           GROUP  BY apex_user
      6. Navigation Bar List > add entry "Chat", icon fa-comments,
         target page 30. Leave its authorization empty so all staff see it.
      7. Delete links: svc_exam_pkg.delete_message(:P30_MESSAGE_ID);
         Clear chat button (Authorization Scheme = Administrators only):
           svc_exam_pkg.clear_chat;

   h) Exam dropdowns (the coloured band at the top of every page)
      On Page 0 (Global Page) add a region "Exam" with these items:
        P0_EXAM_TYPE  Select List
                      SELECT label_en d, exam_type_code r
                      FROM svc_exam_types ORDER BY sort_order
        P0_TERM       Select List, static values: Term 1;1,Term 2;2,Term 3;3
        P0_PROGRAMS   Checkbox Group (several can be ticked)
                      SELECT label_en d, program_code r
                      FROM svc_programs ORDER BY sort_order
        P0_YEAR       Select List
                      SELECT academic_year d, academic_year r
                      FROM svc_v_academic_years ORDER BY start_year
        P0_MONTH      Select List, Cascading LOV parent item P0_YEAR
                      SELECT month_label d, TO_CHAR(exam_month, 'YYYY-MM-DD') r
                      FROM svc_v_exam_months WHERE academic_year = :P0_YEAR
                      ORDER BY exam_month
        P0_EXAM_ID    Hidden
      Dynamic Action on Change of these items > Execute Server-side Code
      (items to submit: all five; items to return: P0_EXAM_ID):

        :P0_EXAM_ID := svc_exam_pkg.open_exam(
                         p_exam_type_code => :P0_EXAM_TYPE,
                         p_academic_year  => :P0_YEAR,
                         p_term_no        => :P0_TERM,
                         p_exam_month     => TO_DATE(:P0_MONTH, 'YYYY-MM-DD'),
                         p_programs       => :P0_PROGRAMS);

      then a Submit Page action so every region shows the chosen exam.
      Choosing an exam that does not exist yet creates it with blank
      Morning and Afternoon sheets for all 24 rooms.
   ===================================================================== */
