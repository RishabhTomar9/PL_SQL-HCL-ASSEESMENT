/*=====================================================
  ENABLE OUTPUT
=====================================================*/
SET SERVEROUTPUT ON;

/*=====================================================
  OPTIONAL CLEANUP (use only if re-running)
=====================================================*/
-- DROP TRIGGER trg_audit_grade_changes;
-- DROP TRIGGER trg_notify_on_fail;
-- DROP TABLE grade_audit;
-- DROP TABLE exam_results;
-- DROP TABLE students;
-- DROP TABLE subjects;
-- DROP SEQUENCE subjects_seq;
-- DROP SEQUENCE students_seq;
-- DROP SEQUENCE results_seq;
-- DROP SEQUENCE grade_audit_seq;

/*=====================================================
  1. TABLES
=====================================================*/
CREATE TABLE subjects (
    subject_id   NUMBER PRIMARY KEY,
    subject_name VARCHAR2(50) UNIQUE NOT NULL,
    max_marks    NUMBER DEFAULT 100
);

CREATE TABLE students (
    student_id    NUMBER PRIMARY KEY,
    first_name    VARCHAR2(50),
    last_name     VARCHAR2(50),
    enrollment_date DATE
);

CREATE TABLE exam_results (
    result_id   NUMBER PRIMARY KEY,
    student_id  NUMBER,
    subject_id  NUMBER,
    exam_date   DATE,
    marks_obtained NUMBER,
    grade       VARCHAR2(2),
    CONSTRAINT fk_student FOREIGN KEY (student_id)
        REFERENCES students(student_id),
    CONSTRAINT fk_subject FOREIGN KEY (subject_id)
        REFERENCES subjects(subject_id)
);

CREATE TABLE grade_audit (
    audit_id        NUMBER PRIMARY KEY,
    result_id       NUMBER,
    student_id      NUMBER,
    subject_id      NUMBER,
    old_marks       NUMBER,
    new_marks       NUMBER,
    change_date     DATE,
    changed_by      VARCHAR2(30)
);

/*=====================================================
  2. SEQUENCES
=====================================================*/
CREATE SEQUENCE subjects_seq START WITH 1;
CREATE SEQUENCE students_seq START WITH 1;
CREATE SEQUENCE results_seq  START WITH 1;
CREATE SEQUENCE grade_audit_seq START WITH 1;

/*=====================================================
  3. SAMPLE DATA
=====================================================*/
INSERT INTO subjects (subject_id, subject_name) VALUES (subjects_seq.NEXTVAL, 'Mathematics');
INSERT INTO subjects (subject_id, subject_name) VALUES (subjects_seq.NEXTVAL, 'Science');
INSERT INTO subjects (subject_id, subject_name) VALUES (subjects_seq.NEXTVAL, 'History');
INSERT INTO subjects (subject_id, subject_name) VALUES (subjects_seq.NEXTVAL, 'English');

INSERT INTO students VALUES (students_seq.NEXTVAL, 'Peter', 'Jones', SYSDATE - 500);
INSERT INTO students VALUES (students_seq.NEXTVAL, 'Mary', 'Jane', SYSDATE - 450);
INSERT INTO students VALUES (students_seq.NEXTVAL, 'Clark', 'Kent', SYSDATE - 600);
INSERT INTO students VALUES (students_seq.NEXTVAL, 'Lois', 'Lane', SYSDATE - 550);

COMMIT;

/*=====================================================
  4. HELPER PROCEDURE (FORMATTED OUTPUT)
=====================================================*/
CREATE OR REPLACE PROCEDURE print_line(p_text VARCHAR2) IS
BEGIN
    DBMS_OUTPUT.PUT_LINE(p_text);
END;
/

/*=====================================================
  5. PACKAGE – EXAM LOGIC
=====================================================*/
CREATE OR REPLACE PACKAGE exam_pkg IS
    FUNCTION calculate_grade(p_marks NUMBER, p_max_marks NUMBER) RETURN VARCHAR2;
    PROCEDURE record_exam_result(
        p_student_id NUMBER,
        p_subject_id NUMBER,
        p_marks      NUMBER
    );
    PROCEDURE student_report_card(p_student_id NUMBER);
END exam_pkg;
/

CREATE OR REPLACE PACKAGE BODY exam_pkg IS

FUNCTION calculate_grade(p_marks NUMBER, p_max_marks NUMBER) RETURN VARCHAR2 IS
    v_percentage NUMBER;
BEGIN
    v_percentage := (p_marks / p_max_marks) * 100;
    IF v_percentage >= 90 THEN RETURN 'A+';
    ELSIF v_percentage >= 80 THEN RETURN 'A';
    ELSIF v_percentage >= 70 THEN RETURN 'B';
    ELSIF v_percentage >= 60 THEN RETURN 'C';
    ELSIF v_percentage >= 50 THEN RETURN 'D';
    ELSIF v_percentage >= 40 THEN RETURN 'E';
    ELSE RETURN 'F';
    END IF;
END;

PROCEDURE record_exam_result(
    p_student_id NUMBER,
    p_subject_id NUMBER,
    p_marks      NUMBER
) IS
    v_max_marks subjects.max_marks%TYPE;
    v_grade     exam_results.grade%TYPE;
BEGIN
    SELECT max_marks INTO v_max_marks FROM subjects WHERE subject_id = p_subject_id;

    IF p_marks > v_max_marks OR p_marks < 0 THEN
        RAISE_APPLICATION_ERROR(-20010, 'Marks obtained are invalid.');
    END IF;

    v_grade := calculate_grade(p_marks, v_max_marks);

    INSERT INTO exam_results
    VALUES (results_seq.NEXTVAL, p_student_id, p_subject_id, SYSDATE, p_marks, v_grade);

    print_line('✔ Result recorded for Student ID '||p_student_id||
               ' in Subject ID '||p_subject_id||' | Grade: '||v_grade);
END;

PROCEDURE student_report_card(p_student_id NUMBER) IS
    CURSOR c IS
        SELECT s.subject_name, r.marks_obtained, r.grade, r.exam_date
        FROM exam_results r
        JOIN subjects s ON r.subject_id = s.subject_id
        WHERE r.student_id = p_student_id
        ORDER BY s.subject_name;
    v_student_name VARCHAR2(101);
BEGIN
    SELECT first_name || ' ' || last_name INTO v_student_name
    FROM students WHERE student_id = p_student_id;

    print_line(CHR(10)||'======================================================');
    print_line('STUDENT REPORT CARD : '||v_student_name);
    print_line('======================================================');
    print_line(RPAD('SUBJECT',25)||' | '||
               LPAD('MARKS',10)||' | '||
               LPAD('GRADE',10)||' | DATE');
    print_line(RPAD('-',25,'-')||'-+-'||
               LPAD('-',10,'-')||'-+-'||
               LPAD('-',10,'-')||'-+-'||
               RPAD('-',10,'-'));

    FOR r IN c LOOP
        print_line(RPAD(r.subject_name,25)||' | '||
                   LPAD(r.marks_obtained,10)||' | '||
                   LPAD(r.grade,10)||' | '||
                   TO_CHAR(r.exam_date, 'DD-MON-YYYY'));
    END LOOP;

    print_line('======================================================');
END;

END exam_pkg;
/

/*=====================================================
  6. TRIGGER – GRADE CHANGE AUDIT
=====================================================*/
CREATE OR REPLACE TRIGGER trg_audit_grade_changes
BEFORE UPDATE OF marks_obtained ON exam_results
FOR EACH ROW
BEGIN
    INSERT INTO grade_audit
    VALUES (
        grade_audit_seq.NEXTVAL,
        :OLD.result_id,
        :OLD.student_id,
        :OLD.subject_id,
        :OLD.marks_obtained,
        :NEW.marks_obtained,
        SYSDATE,
        USER
    );
END;
/

/*=====================================================
  7. TRIGGER – NOTIFY ON FAILURE
=====================================================*/
CREATE OR REPLACE TRIGGER trg_notify_on_fail
AFTER INSERT ON exam_results
FOR EACH ROW
WHEN (NEW.grade = 'F')
BEGIN
    print_line('⚠ Student ID '||:NEW.student_id || ' has failed in Subject ID ' || :NEW.subject_id);
END;
/


/*=====================================================
  8. EXECUTION / TEST CASES
=====================================================*/
-- Record initial results
BEGIN
    exam_pkg.record_exam_result(1, 1, 85); -- Peter, Math
    exam_pkg.record_exam_result(1, 2, 72); -- Peter, Science
    exam_pkg.record_exam_result(2, 1, 91); -- Mary, Math
    exam_pkg.record_exam_result(2, 4, 88); -- Mary, English
    exam_pkg.record_exam_result(3, 3, 35); -- Clark, History (should trigger fail notification)
    exam_pkg.record_exam_result(3, 4, 55); -- Clark, English
END;
/

-- Correct a result, firing the audit trigger
UPDATE exam_results SET marks_obtained = 42 WHERE result_id = 5;
COMMIT;
/

-- Regenerate a result for Clark in History after re-evaluation
BEGIN
    exam_pkg.record_exam_result(3, 3, 42); -- Re-record result
END;
/

-- Generate report cards
BEGIN
    exam_pkg.student_report_card(1); -- Peter's report
    exam_pkg.student_report_card(2); -- Mary's report
    exam_pkg.student_report_card(3); -- Clark's report
END;
/

-- Audit Log
SELECT * FROM grade_audit;
