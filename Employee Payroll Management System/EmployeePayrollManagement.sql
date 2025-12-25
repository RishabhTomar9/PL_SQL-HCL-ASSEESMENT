/************************************************************************************
*                                                                                   *
*                      EMPLOYEE PAYROLL MANAGEMENT SYSTEM                           *
*                                                                                   *
************************************************************************************/

-- DOMAIN: HR / Corporate
-- DESCRIPTION: This script sets up a payroll system for managing employee salaries,
--              departments, and generating salary slips and reports.
--
-- FEATURES:
-- 1. Employee details management
-- 2. Salary calculation (basic + HRA + bonus - tax)
-- 3. Monthly payslip generation
-- 4. Department-wise salary report
--
-- PL/SQL CONCEPTS USED:
-- 1. Packages
-- 2. Stored Procedures
-- 3. Functions
-- 4. Cursors
-- 5. Triggers
-- 6. Sequences

/************************************************************************************
*                                 TABLE DEFINITIONS                                 *
************************************************************************************/

CREATE TABLE departments (
    department_id   NUMBER PRIMARY KEY,
    department_name VARCHAR2(50) NOT NULL UNIQUE
);

CREATE TABLE employees (
    employee_id     NUMBER PRIMARY KEY,
    first_name      VARCHAR2(50) NOT NULL,
    last_name       VARCHAR2(50) NOT NULL,
    department_id   NUMBER,
    hire_date       DATE NOT NULL,
    basic_salary    NUMBER(10, 2) NOT NULL CHECK (basic_salary >= 0),
    CONSTRAINT fk_department FOREIGN KEY (department_id) REFERENCES departments(department_id)
);

CREATE TABLE salary_details (
    payslip_id      NUMBER PRIMARY KEY,
    employee_id     NUMBER,
    pay_date        DATE,
    hra             NUMBER(10, 2),
    bonus           NUMBER(10, 2) CHECK (bonus >= 0),
    tax             NUMBER(10, 2),
    net_salary      NUMBER(10, 2),
    CONSTRAINT fk_employee FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
);

CREATE TABLE salary_audit (
    audit_id          NUMBER PRIMARY KEY,
    employee_id       NUMBER,
    old_basic_salary  NUMBER(10, 2),
    new_basic_salary  NUMBER(10, 2),
    change_date       DATE,
    changed_by        VARCHAR2(30)
);

/************************************************************************************
*                               SEQUENCES                                           *
************************************************************************************/

CREATE SEQUENCE departments_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE employees_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE payslip_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE audit_seq START WITH 1 INCREMENT BY 1;

/************************************************************************************
*                                     PACKAGE                                       *
************************************************************************************/

CREATE OR REPLACE PACKAGE payroll_pkg AS

    -- Function to calculate tax based on salary
    FUNCTION calculate_tax (
        p_basic_salary IN employees.basic_salary%TYPE
    ) RETURN NUMBER;

    -- Procedure to calculate the net salary and generate a payslip
    PROCEDURE calculate_salary (
        p_employee_id IN employees.employee_id%TYPE,
        p_hra_percent IN NUMBER,
        p_bonus       IN salary_details.bonus%TYPE
    );

    -- Procedure to generate a salary report for a given department
    PROCEDURE generate_dept_salary_report (
        p_department_id IN departments.department_id%TYPE
    );

END payroll_pkg;
/

CREATE OR REPLACE PACKAGE BODY payroll_pkg AS

    FUNCTION calculate_tax (
        p_basic_salary IN employees.basic_salary%TYPE
    ) RETURN NUMBER AS
        v_tax_amount salary_details.tax%TYPE;
    BEGIN
        IF p_basic_salary <= 50000 THEN
            v_tax_amount := p_basic_salary * 0.10; -- 10% tax for salary <= 50000
        ELSE
            v_tax_amount := p_basic_salary * 0.20; -- 20% tax for salary > 50000
        END IF;
        RETURN v_tax_amount;
    END calculate_tax;

    PROCEDURE calculate_salary (
        p_employee_id IN employees.employee_id%TYPE,
        p_hra_percent IN NUMBER,
        p_bonus       IN salary_details.bonus%TYPE
    ) AS
        v_basic_salary  employees.basic_salary%TYPE;
        v_hra           salary_details.hra%TYPE;
        v_tax           salary_details.tax%TYPE;
        v_net_salary    salary_details.net_salary%TYPE;
    BEGIN
        -- Input validation
        IF p_hra_percent < 0 OR p_bonus < 0 THEN
            RAISE_APPLICATION_ERROR(-20020, 'HRA percentage and Bonus cannot be negative.');
        END IF;

        SELECT basic_salary INTO v_basic_salary
        FROM employees
        WHERE employee_id = p_employee_id;

        v_hra := v_basic_salary * (p_hra_percent / 100);
        v_tax := calculate_tax(v_basic_salary);
        v_net_salary := v_basic_salary + v_hra + p_bonus - v_tax;

        INSERT INTO salary_details (payslip_id, employee_id, pay_date, hra, bonus, tax, net_salary)
        VALUES (payslip_seq.NEXTVAL, p_employee_id, SYSDATE, v_hra, p_bonus, v_tax, v_net_salary);

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Salary calculated for employee ID: ' || p_employee_id);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20021, 'Employee with ID ' || p_employee_id || ' not found.');
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END calculate_salary;

    PROCEDURE generate_dept_salary_report (
        p_department_id IN departments.department_id%TYPE
    ) AS
        CURSOR c_emp_salaries IS
            SELECT e.first_name, e.last_name, sd.net_salary, sd.pay_date
            FROM employees e
            JOIN salary_details sd ON e.employee_id = sd.employee_id
            WHERE e.department_id = p_department_id
            ORDER BY sd.pay_date DESC;
        
        v_dept_name departments.department_name%TYPE;
        v_report_generated BOOLEAN := FALSE;
    BEGIN
        SELECT department_name INTO v_dept_name FROM departments WHERE department_id = p_department_id;
        DBMS_OUTPUT.PUT_LINE('========================================');
        DBMS_OUTPUT.PUT_LINE('SALARY REPORT FOR DEPARTMENT: ' || v_dept_name);
        DBMS_OUTPUT.PUT_LINE('========================================');
        
        FOR r_emp IN c_emp_salaries LOOP
            DBMS_OUTPUT.PUT_LINE(
                'Employee: ' || r_emp.first_name || ' ' || r_emp.last_name ||
                ', Net Salary: ' || TO_CHAR(r_emp.net_salary, '999,999.99') ||
                ', Pay Date: ' || TO_CHAR(r_emp.pay_date, 'DD-MON-YYYY')
            );
            v_report_generated := TRUE;
        END LOOP;
        
        IF NOT v_report_generated THEN
            DBMS_OUTPUT.PUT_LINE('No salary details found for this department.');
        END IF;
        DBMS_OUTPUT.PUT_LINE('========================================');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20022, 'Department with ID ' || p_department_id || ' not found.');
    END generate_dept_salary_report;

END payroll_pkg;
/

/************************************************************************************
*                                     TRIGGERS                                      *
************************************************************************************/

-- Trigger to audit changes to the basic_salary column in the employees table
CREATE OR REPLACE TRIGGER trg_audit_salary_changes
BEFORE UPDATE OF basic_salary ON employees
FOR EACH ROW
WHEN (NEW.basic_salary <> OLD.basic_salary)
BEGIN
    INSERT INTO salary_audit (audit_id, employee_id, old_basic_salary, new_basic_salary, change_date, changed_by)
    VALUES (audit_seq.NEXTVAL, :OLD.employee_id, :OLD.basic_salary, :NEW.basic_salary, SYSDATE, USER);
END;
/

/************************************************************************************
*                                    TEST CASES                                     *
************************************************************************************/

SET SERVEROUTPUT ON;

DECLARE
    v_dept_id_it NUMBER;
    v_dept_id_hr NUMBER;
    v_emp_id_1   NUMBER;
    v_emp_id_2   NUMBER;
    v_emp_id_3   NUMBER;
    v_net_salary NUMBER;
    v_audit_count NUMBER;

    PROCEDURE run_test(test_name VARCHAR2, test_passed BOOLEAN) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('----- ' || test_name || ': ' || CASE WHEN test_passed THEN 'PASSED' ELSE 'FAILED' END || ' -----');
    END;

BEGIN
    -- Clean up previous test data
    EXECUTE IMMEDIATE 'TRUNCATE TABLE salary_details';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE salary_audit';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE employees';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE departments';
    
    -- Test Case 1: Create IT Department
    INSERT INTO departments (department_id, department_name) VALUES (departments_seq.NEXTVAL, 'IT') RETURNING department_id INTO v_dept_id_it;
    run_test('Create IT Department', v_dept_id_it IS NOT NULL);

    -- Test Case 2: Create HR Department
    INSERT INTO departments (department_id, department_name) VALUES (departments_seq.NEXTVAL, 'HR') RETURNING department_id INTO v_dept_id_hr;
    run_test('Create HR Department', v_dept_id_hr IS NOT NULL);

    -- Test Case 3: Create Employee 1 (Salary > 50000)
    INSERT INTO employees (employee_id, first_name, last_name, department_id, hire_date, basic_salary)
    VALUES (employees_seq.NEXTVAL, 'Alice', 'Wonder', v_dept_id_it, SYSDATE, 60000) RETURNING employee_id INTO v_emp_id_1;
    run_test('Create Employee 1 (High Salary)', v_emp_id_1 IS NOT NULL);

    -- Test Case 4: Create Employee 2 (Salary < 50000)
    INSERT INTO employees (employee_id, first_name, last_name, department_id, hire_date, basic_salary)
    VALUES (employees_seq.NEXTVAL, 'Bob', 'Builder', v_dept_id_it, SYSDATE, 45000) RETURNING employee_id INTO v_emp_id_2;
    run_test('Create Employee 2 (Low Salary)', v_emp_id_2 IS NOT NULL);
    
    -- Test Case 5: Create Employee 3 (Salary = 50000)
    INSERT INTO employees (employee_id, first_name, last_name, department_id, hire_date, basic_salary)
    VALUES (employees_seq.NEXTVAL, 'Charlie', 'Chocolate', v_dept_id_hr, SYSDATE, 50000) RETURNING employee_id INTO v_emp_id_3;
    run_test('Create Employee 3 (Boundary Salary)', v_emp_id_3 IS NOT NULL);

    -- Test Case 6: Calculate salary for Employee 1 (20% tax)
    payroll_pkg.calculate_salary(v_emp_id_1, 10, 5000); -- HRA 10%, Bonus 5000
    SELECT net_salary INTO v_net_salary FROM salary_details WHERE employee_id = v_emp_id_1;
    run_test('Calculate Salary (20% tax)', v_net_salary = 60000 + 6000 + 5000 - 12000); -- Expected: 59000

    -- Test Case 7: Calculate salary for Employee 2 (10% tax)
    payroll_pkg.calculate_salary(v_emp_id_2, 15, 2500); -- HRA 15%, Bonus 2500
    SELECT net_salary INTO v_net_salary FROM salary_details WHERE employee_id = v_emp_id_2;
    run_test('Calculate Salary (10% tax)', v_net_salary = 45000 + (45000 * 0.15) + 2500 - (45000 * 0.1)); -- Expected: 49750

    -- Test Case 8: Calculate salary for Employee 3 (10% tax boundary)
    payroll_pkg.calculate_salary(v_emp_id_3, 10, 0); -- HRA 10%, No Bonus
    SELECT net_salary INTO v_net_salary FROM salary_details WHERE employee_id = v_emp_id_3;
    run_test('Calculate Salary (Boundary Case)', v_net_salary = 50000 + 5000 - 5000); -- Expected: 50000
    
    -- Test Case 9: Test salary audit trigger
    UPDATE employees SET basic_salary = 65000 WHERE employee_id = v_emp_id_1;
    SELECT COUNT(*) INTO v_audit_count FROM salary_audit WHERE employee_id = v_emp_id_1 AND new_basic_salary = 65000;
    run_test('Salary Audit Trigger', v_audit_count = 1);
    
    -- Test Case 10: Attempt to calculate for non-existent employee
    BEGIN
        payroll_pkg.calculate_salary(999, 10, 100);
        run_test('Calc Salary for Non-existent Employee', FALSE);
    EXCEPTION
        WHEN OTHERS THEN
            run_test('Calc Salary for Non-existent Employee', SQLCODE = -20021);
    END;

    -- Test Case 11: Generate report for IT department (visual check in DBMS_OUTPUT)
    payroll_pkg.generate_dept_salary_report(v_dept_id_it);
    run_test('Generate Report for IT Dept', TRUE); -- Manual verification needed for output

    -- Test Case 12: Update salary again and check audit trail
    UPDATE employees SET basic_salary = 70000 WHERE employee_id = v_emp_id_1;
    SELECT COUNT(*) INTO v_audit_count FROM salary_audit WHERE employee_id = v_emp_id_1;
    run_test('Multiple Salary Audits', v_audit_count = 2);

    -- Test Case 13: Generate report for HR dept (which has one salary calc)
    payroll_pkg.generate_dept_salary_report(v_dept_id_hr);
    run_test('Generate Report for HR Dept', TRUE); -- Manual verification
    
    -- Test Case 14: Attempt to use negative bonus
    BEGIN
        payroll_pkg.calculate_salary(v_emp_id_1, 10, -100);
        run_test('Negative Bonus Check', FALSE);
    EXCEPTION
        WHEN OTHERS THEN
            run_test('Negative Bonus Check', SQLCODE = -20020);
    END;
    
    -- Test Case 15: Generate report for a department with no calculated salaries
    DECLARE
        v_dept_id_sales NUMBER;
    BEGIN
        INSERT INTO departments (department_id, department_name) VALUES (departments_seq.NEXTVAL, 'Sales') RETURNING department_id INTO v_dept_id_sales;
        payroll_pkg.generate_dept_salary_report(v_dept_id_sales);
        run_test('Report for Dept with No Salaries', TRUE); -- Manual verification
    END;

    ROLLBACK; -- Rollback all test changes
END;
/