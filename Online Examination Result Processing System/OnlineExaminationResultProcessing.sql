/************************************************************************************
*                                                                                   *
*               ONLINE EXAMINATION RESULT PROCESSING SYSTEM                         *
*                                                                                   *
************************************************************************************/

-- DOMAIN: Education
-- DESCRIPTION: This script manages student examination results, including calculating
--              grades, determining pass/fail status, and generating ranks.
--
-- FEATURES:
-- 1. Store student marks for various subjects.
-- 2. Calculate grades based on total marks.
-- 3. Determine pass/fail status.
-- 4. Generate student ranks.
-- 5. Real-time result updates upon mark entry.
--
-- PL/SQL CONCEPTS USED:
-- 1. Functions
-- 2. Stored Procedures
-- 3. Cursors
-- 4. Triggers
-- 5. Exception Handling
-- 6. MERGE statement

/************************************************************************************
*                                 TABLE DEFINITIONS                                 *
************************************************************************************/

CREATE TABLE students (
    student_id      NUMBER PRIMARY KEY,
    student_name    VARCHAR2(100) NOT NULL
);

CREATE TABLE subjects (
    subject_id      NUMBER PRIMARY KEY,
    subject_name    VARCHAR2(100) NOT NULL UNIQUE
);

CREATE TABLE marks (
    mark_id         NUMBER PRIMARY KEY,
    student_id      NUMBER NOT NULL,
    subject_id      NUMBER NOT NULL,
    marks_obtained  NUMBER NOT NULL CHECK (marks_obtained BETWEEN 0 AND 100),
    CONSTRAINT fk_student_marks FOREIGN KEY (student_id) REFERENCES students(student_id),
    CONSTRAINT fk_subject_marks FOREIGN KEY (subject_id) REFERENCES subjects(subject_id),
    CONSTRAINT uq_student_subject UNIQUE (student_id, subject_id)
);

CREATE TABLE results (
    result_id       NUMBER PRIMARY KEY,
    student_id      NUMBER NOT NULL UNIQUE,
    total_marks     NUMBER,
    percentage      NUMBER(5, 2),
    grade           VARCHAR2(2),
    status          VARCHAR2(10) CHECK (status IN ('PASS', 'FAIL')),
    rank            NUMBER,
    CONSTRAINT fk_student_results FOREIGN KEY (student_id) REFERENCES students(student_id)
);

/************************************************************************************
*                               SEQUENCES                                           *
************************************************************************************/

CREATE SEQUENCE students_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE subjects_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE marks_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE results_seq START WITH 1 INCREMENT BY 1;

/************************************************************************************
*                                    FUNCTIONS                                      *
************************************************************************************/

-- Function to calculate grade based on percentage
CREATE OR REPLACE FUNCTION calculate_grade (p_percentage IN NUMBER) RETURN VARCHAR2 AS
BEGIN
    IF p_percentage >= 90 THEN RETURN 'A+';
    ELSIF p_percentage >= 80 THEN RETURN 'A';
    ELSIF p_percentage >= 70 THEN RETURN 'B';
    ELSIF p_percentage >= 60 THEN RETURN 'C';
    ELSIF p_percentage >= 50 THEN RETURN 'D';
    ELSE RETURN 'F';
    END IF;
END;
/

/************************************************************************************
*                               STORED PROCEDURES                                   *
************************************************************************************/

-- Procedure to perform a full batch processing of results for all students
CREATE OR REPLACE PROCEDURE process_all_results AS
    CURSOR c_students IS SELECT student_id FROM students;
    v_total_marks   results.total_marks%TYPE;
    v_num_subjects  NUMBER;
    v_percentage    results.percentage%TYPE;
    v_grade         results.grade%TYPE;
    v_status        results.status%TYPE;
BEGIN
    FOR rec IN c_students LOOP
        SELECT NVL(SUM(marks_obtained), 0), COUNT(subject_id)
        INTO v_total_marks, v_num_subjects
        FROM marks
        WHERE student_id = rec.student_id;

        IF v_num_subjects > 0 THEN
            v_percentage := (v_total_marks / (v_num_subjects * 100)) * 100;
        ELSE
            v_percentage := 0;
        END IF;

        v_grade := calculate_grade(v_percentage);
        v_status := CASE WHEN v_grade = 'F' THEN 'FAIL' ELSE 'PASS' END;

        MERGE INTO results r
        USING (SELECT rec.student_id AS student_id FROM dual) s ON (r.student_id = s.student_id)
        WHEN MATCHED THEN
            UPDATE SET total_marks = v_total_marks, percentage = v_percentage, grade = v_grade, status = v_status
        WHEN NOT MATCHED THEN
            INSERT (result_id, student_id, total_marks, percentage, grade, status)
            VALUES (results_seq.NEXTVAL, rec.student_id, v_total_marks, v_percentage, v_grade, v_status);
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Batch result processing complete.');
END;
/

-- Procedure to generate ranks based on total marks
CREATE OR REPLACE PROCEDURE generate_ranks AS
    CURSOR c_results IS
        SELECT result_id, total_marks
        FROM results
        ORDER BY total_marks DESC;
    v_rank NUMBER := 0;
    v_last_marks NUMBER := -1;
    v_counter NUMBER := 1;
BEGIN
    FOR rec IN c_results LOOP
        IF rec.total_marks <> v_last_marks THEN
            v_rank := v_counter;
        END IF;
        
        UPDATE results SET rank = v_rank WHERE result_id = rec.result_id;
        
        v_last_marks := rec.total_marks;
        v_counter := v_counter + 1;
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Rank generation complete.');
END;
/

/************************************************************************************
*                                     TRIGGERS                                      *
************************************************************************************/

-- Trigger to automatically update (or insert) a student's result in real-time
-- when a mark is inserted or updated.
CREATE OR REPLACE TRIGGER trg_auto_update_result
AFTER INSERT OR UPDATE OR DELETE ON marks
FOR EACH ROW
DECLARE
    v_student_id    students.student_id%TYPE;
    v_total_marks   results.total_marks%TYPE;
    v_num_subjects  NUMBER;
    v_percentage    results.percentage%TYPE;
    v_grade         results.grade%TYPE;
    v_status        results.status%TYPE;
BEGIN
    IF INSERTING OR UPDATING THEN
        v_student_id := :NEW.student_id;
    ELSIF DELETING THEN
        v_student_id := :OLD.student_id;
    END IF;
    
    -- Recalculate totals for the affected student
    SELECT NVL(SUM(marks_obtained), 0), COUNT(subject_id)
    INTO v_total_marks, v_num_subjects
    FROM marks
    WHERE student_id = v_student_id;

    IF v_num_subjects > 0 THEN
        v_percentage := (v_total_marks / (v_num_subjects * 100)) * 100;
    ELSE
        v_percentage := 0;
    END IF;

    v_grade := calculate_grade(v_percentage);
    v_status := CASE WHEN v_grade = 'F' THEN 'FAIL' ELSE 'PASS' END;
    
    -- Merge the new result into the results table
    MERGE INTO results r
    USING (SELECT v_student_id AS student_id FROM dual) s ON (r.student_id = s.student_id)
    WHEN MATCHED THEN
        UPDATE SET total_marks = v_total_marks, percentage = v_percentage, grade = v_grade, status = v_status
    WHEN NOT MATCHED THEN
        INSERT (result_id, student_id, total_marks, percentage, grade, status)
        VALUES (results_seq.NEXTVAL, v_student_id, v_total_marks, v_percentage, v_grade, v_status);
END;
/


/************************************************************************************
*                                    TEST CASES                                     *
************************************************************************************/
SET SERVEROUTPUT ON;

DECLARE
    v_stud_id_1 NUMBER; v_stud_id_2 NUMBER; v_stud_id_3 NUMBER; v_stud_id_4 NUMBER;
    v_subj_id_1 NUMBER; v_subj_id_2 NUMBER;
    v_res         results%ROWTYPE;

    PROCEDURE run_test(test_name VARCHAR2, test_passed BOOLEAN) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('----- ' || test_name || ': ' || CASE WHEN test_passed THEN 'PASSED' ELSE 'FAILED' END || ' -----');
    END;
    
    FUNCTION get_result(p_stud_id NUMBER) RETURN results%ROWTYPE IS
        l_res results%ROWTYPE;
    BEGIN
        SELECT * INTO l_res FROM results WHERE student_id = p_stud_id;
        RETURN l_res;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;
    END;

BEGIN
    -- Clean up previous test data
    EXECUTE IMMEDIATE 'TRUNCATE TABLE marks';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE results';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE students';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE subjects';
    
    -- Test Case 1 & 2: Create Subjects
    INSERT INTO subjects(subject_id, subject_name) VALUES (subjects_seq.NEXTVAL, 'Math') RETURNING subject_id INTO v_subj_id_1;
    run_test('Create Subject 1', v_subj_id_1 IS NOT NULL);
    INSERT INTO subjects(subject_id, subject_name) VALUES (subjects_seq.NEXTVAL, 'Science') RETURNING subject_id INTO v_subj_id_2;
    run_test('Create Subject 2', v_subj_id_2 IS NOT NULL);

    -- Test Case 3-5: Create Students
    INSERT INTO students(student_id, student_name) VALUES(students_seq.NEXTVAL, 'Alice') RETURNING student_id INTO v_stud_id_1;
    INSERT INTO students(student_id, student_name) VALUES(students_seq.NEXTVAL, 'Bob') RETURNING student_id INTO v_stud_id_2;
    INSERT INTO students(student_id, student_name) VALUES(students_seq.NEXTVAL, 'Charlie') RETURNING student_id INTO v_stud_id_3;
    INSERT INTO students(student_id, student_name) VALUES(students_seq.NEXTVAL, 'David') RETURNING student_id INTO v_stud_id_4;
    run_test('Create Students', v_stud_id_1 > 0 AND v_stud_id_2 > 0 AND v_stud_id_3 > 0);

    -- Test Case 6: Insert marks (triggers should fire)
    INSERT INTO marks(mark_id, student_id, subject_id, marks_obtained) VALUES(marks_seq.NEXTVAL, v_stud_id_1, v_subj_id_1, 95); -- A+
    INSERT INTO marks(mark_id, student_id, subject_id, marks_obtained) VALUES(marks_seq.NEXTVAL, v_stud_id_1, v_subj_id_2, 85);
    v_res := get_result(v_stud_id_1);
    run_test('Auto-calc for Student 1 (A+ Grade)', v_res.total_marks = 180 AND v_res.grade = 'A+');
    
    -- Test Case 7: Insert more marks
    INSERT INTO marks(mark_id, student_id, subject_id, marks_obtained) VALUES(marks_seq.NEXTVAL, v_stud_id_2, v_subj_id_1, 72); -- B
    INSERT INTO marks(mark_id, student_id, subject_id, marks_obtained) VALUES(marks_seq.NEXTVAL, v_stud_id_2, v_subj_id_2, 78);
    v_res := get_result(v_stud_id_2);
    run_test('Auto-calc for Student 2 (B Grade)', v_res.total_marks = 150 AND v_res.grade = 'B');

    -- Test Case 8: Insert marks for a failing grade
    INSERT INTO marks(mark_id, student_id, subject_id, marks_obtained) VALUES(marks_seq.NEXTVAL, v_stud_id_3, v_subj_id_1, 40); -- F
    INSERT INTO marks(mark_id, student_id, subject_id, marks_obtained) VALUES(marks_seq.NEXTVAL, v_stud_id_3, v_subj_id_2, 35);
    v_res := get_result(v_stud_id_3);
    run_test('Auto-calc for Student 3 (F Grade)', v_res.status = 'FAIL' AND v_res.grade = 'F');
    
    -- Test Case 9: Create a tie in total marks
    INSERT INTO marks(mark_id, student_id, subject_id, marks_obtained) VALUES(marks_seq.NEXTVAL, v_stud_id_4, v_subj_id_1, 70); -- Tie with Student 2
    INSERT INTO marks(mark_id, student_id, subject_id, marks_obtained) VALUES(marks_seq.NEXTVAL, v_stud_id_4, v_subj_id_2, 80);
    v_res := get_result(v_stud_id_4);
    run_test('Auto-calc for Student 4 (Tie)', v_res.total_marks = 150);

    -- Test Case 10: Run batch rank generation
    generate_ranks();
    run_test('Run Rank Generation', TRUE); -- Visual check

    -- Test Case 11: Verify ranking (Student 1 is 1st)
    v_res := get_result(v_stud_id_1);
    run_test('Rank Check: Student 1', v_res.rank = 1);

    -- Test Case 12: Verify ranking for a tie (Student 2 and 4 are 2nd)
    v_res := get_result(v_stud_id_2);
    run_test('Rank Check: Tie Student 2', v_res.rank = 2);
    v_res := get_result(v_stud_id_4);
    run_test('Rank Check: Tie Student 4', v_res.rank = 2);

    -- Test Case 13: Verify ranking (Student 3 is last/4th)
    v_res := get_result(v_stud_id_3);
    run_test('Rank Check: Last Place Student 3', v_res.rank = 4);
    
    -- Test Case 14: Update a mark and check if trigger recalculates correctly
    UPDATE marks SET marks_obtained = 50 WHERE student_id = v_stud_id_2 AND subject_id = v_subj_id_1;
    v_res := get_result(v_stud_id_2);
    run_test('Trigger on UPDATE', v_res.total_marks = 128 AND v_res.grade = 'C');
    
    -- Test Case 15: Attempt to insert mark > 100
    BEGIN
        INSERT INTO marks(mark_id, student_id, subject_id, marks_obtained) VALUES(marks_seq.NEXTVAL, v_stud_id_1, 12345, 101);
        run_test('Check constraint (mark > 100)', FALSE);
    EXCEPTION
        WHEN OTHERS THEN
            run_test('Check constraint (mark > 100)', SQLERRM LIKE '%CK_MARKS_OBTAINED%');
    END;
    
    -- Run batch processing and ranking again after updates
    process_all_results();
    generate_ranks();
    DBMS_OUTPUT.PUT_LINE('--- FINAL RESULTS ---');
    FOR i IN (SELECT s.student_name, r.* FROM results r JOIN students s ON s.student_id = r.student_id ORDER BY r.rank, s.student_name) LOOP
        DBMS_OUTPUT.PUT_LINE('Rank ' || i.rank || ': ' || i.student_name || ' - ' || i.total_marks || ' marks, Grade ' || i.grade);
    END LOOP;
    
    ROLLBACK;
END;
/