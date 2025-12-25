/*=====================================================
  ENABLE OUTPUT
=====================================================*/
SET SERVEROUTPUT ON;

/*=====================================================
  OPTIONAL CLEANUP (use only if re-running)
=====================================================*/
-- DROP TRIGGER trg_audit_salary_changes;
-- DROP TRIGGER trg_reset_salary_data;
-- DROP TABLE salary_audit;
-- DROP TABLE salary_details;
-- DROP TABLE employees;
-- DROP TABLE departments;
-- DROP SEQUENCE departments_seq;
-- DROP SEQUENCE employees_seq;
-- DROP SEQUENCE payslip_seq;
-- DROP SEQUENCE audit_seq;

/*=====================================================
  1. TABLES
=====================================================*/
CREATE TABLE departments (
    department_id   NUMBER PRIMARY KEY,
    department_name VARCHAR2(50) UNIQUE NOT NULL
);

CREATE TABLE employees (
    employee_id    NUMBER PRIMARY KEY,
    first_name     VARCHAR2(50),
    last_name      VARCHAR2(50),
    department_id  NUMBER,
    hire_date      DATE,
    basic_salary   NUMBER(10,2),
    CONSTRAINT fk_dept FOREIGN KEY (department_id)
        REFERENCES departments(department_id)
);

CREATE TABLE salary_details (
    payslip_id   NUMBER PRIMARY KEY,
    employee_id  NUMBER,
    pay_date     DATE,
    hra          NUMBER,
    bonus        NUMBER,
    tax          NUMBER,
    net_salary   NUMBER,
    CONSTRAINT fk_emp FOREIGN KEY (employee_id)
        REFERENCES employees(employee_id)
);

CREATE TABLE salary_audit (
    audit_id          NUMBER PRIMARY KEY,
    employee_id       NUMBER,
    old_basic_salary  NUMBER,
    new_basic_salary  NUMBER,
    change_date       DATE,
    changed_by        VARCHAR2(30)
);

/*=====================================================
  2. SEQUENCES
=====================================================*/
CREATE SEQUENCE departments_seq START WITH 1;
CREATE SEQUENCE employees_seq   START WITH 1;
CREATE SEQUENCE payslip_seq     START WITH 1;
CREATE SEQUENCE audit_seq       START WITH 1;

/*=====================================================
  3. SAMPLE DATA
=====================================================*/
INSERT INTO departments VALUES (departments_seq.NEXTVAL,'IT');
INSERT INTO departments VALUES (departments_seq.NEXTVAL,'HR');
INSERT INTO departments VALUES (departments_seq.NEXTVAL,'SALES');
INSERT INTO departments VALUES (departments_seq.NEXTVAL,'FINANCE');

INSERT INTO employees VALUES (employees_seq.NEXTVAL,'Alice','Wonder',1,SYSDATE-300,60000);
INSERT INTO employees VALUES (employees_seq.NEXTVAL,'Bob','Builder',1,SYSDATE-200,45000);
INSERT INTO employees VALUES (employees_seq.NEXTVAL,'Charlie','Brown',2,SYSDATE-400,50000);
INSERT INTO employees VALUES (employees_seq.NEXTVAL,'Diana','Prince',3,SYSDATE-150,70000);
INSERT INTO employees VALUES (employees_seq.NEXTVAL,'Ethan','Hunt',4,SYSDATE-600,80000);

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
  5. PACKAGE – PAYROLL LOGIC
=====================================================*/
CREATE OR REPLACE PACKAGE payroll_pkg IS
    FUNCTION calculate_tax(p_basic NUMBER) RETURN NUMBER;
    PROCEDURE calculate_salary(
        p_emp_id NUMBER,
        p_hra_pct NUMBER,
        p_bonus NUMBER
    );
    PROCEDURE department_report(p_dept_id NUMBER);
END payroll_pkg;
/

CREATE OR REPLACE PACKAGE BODY payroll_pkg IS

FUNCTION calculate_tax(p_basic NUMBER) RETURN NUMBER IS
BEGIN
    IF p_basic <= 50000 THEN
        RETURN p_basic * 0.10;
    ELSE
        RETURN p_basic * 0.20;
    END IF;
END;

PROCEDURE calculate_salary(
    p_emp_id NUMBER,
    p_hra_pct NUMBER,
    p_bonus NUMBER
) IS
    v_basic NUMBER;
    v_hra   NUMBER;
    v_tax   NUMBER;
    v_net   NUMBER;
BEGIN
    SELECT basic_salary INTO v_basic
    FROM employees WHERE employee_id = p_emp_id;

    v_hra := v_basic * (p_hra_pct/100);
    v_tax := calculate_tax(v_basic);
    v_net := v_basic + v_hra + p_bonus - v_tax;

    INSERT INTO salary_details
    VALUES (payslip_seq.NEXTVAL,p_emp_id,SYSDATE,v_hra,p_bonus,v_tax,v_net);

    print_line('✔ Salary calculated for Employee ID '||p_emp_id||
               ' | Net Salary: ₹'||v_net);
END;

PROCEDURE department_report(p_dept_id NUMBER) IS
    CURSOR c IS
        SELECT e.first_name||' '||e.last_name emp,
               s.net_salary,
               s.pay_date
        FROM employees e
        JOIN salary_details s ON e.employee_id=s.employee_id
        WHERE e.department_id=p_dept_id
        ORDER BY s.pay_date;
    v_name departments.department_name%TYPE;
BEGIN
    SELECT department_name INTO v_name
    FROM departments WHERE department_id=p_dept_id;

    print_line(CHR(10)||'==============================================');
    print_line('DEPARTMENT SALARY REPORT : '||v_name);
    print_line('==============================================');
    print_line(RPAD('EMPLOYEE',25)||' | '||
               LPAD('NET SALARY',15)||' | DATE');
    print_line(RPAD('-',25,'-')||'-+-'||
               LPAD('-',15,'-')||'-+-'||
               RPAD('-',10,'-'));

    FOR r IN c LOOP
        print_line(RPAD(r.emp,25)||' | '||
                   LPAD(TO_CHAR(r.net_salary,'99,99,999'),15)||' | '||
                   TO_CHAR(r.pay_date,'DD-MON-YYYY'));
    END LOOP;

    print_line('==============================================');
END;

END payroll_pkg;
/

/*=====================================================
  6. TRIGGER – SALARY AUDIT
=====================================================*/
CREATE OR REPLACE TRIGGER trg_audit_salary_changes
BEFORE UPDATE OF basic_salary ON employees
FOR EACH ROW
BEGIN
    INSERT INTO salary_audit
    VALUES (
        audit_seq.NEXTVAL,
        :OLD.employee_id,
        :OLD.basic_salary,
        :NEW.basic_salary,
        SYSDATE,
        USER
    );
END;
/

/*=====================================================
  7. TRIGGER – RESET PAYROLL ON SALARY UPDATE
=====================================================*/
CREATE OR REPLACE TRIGGER trg_reset_salary_data
AFTER UPDATE OF basic_salary ON employees
FOR EACH ROW
BEGIN
    DELETE FROM salary_details
    WHERE employee_id = :OLD.employee_id;

    print_line('⚠ Payroll reset for Employee ID '||:OLD.employee_id);
END;
/

/*=====================================================
  8. EXECUTION / TEST CASES
=====================================================*/
BEGIN
    payroll_pkg.calculate_salary(1,10,5000);
    payroll_pkg.calculate_salary(2,10,2000);
    payroll_pkg.calculate_salary(3,12,3000);
    payroll_pkg.calculate_salary(4,15,10000);
    payroll_pkg.calculate_salary(5,20,15000);
END;
/

-- Salary update to test triggers
UPDATE employees SET basic_salary=65000 WHERE employee_id=1;
COMMIT;

-- Recalculate after reset
BEGIN
    payroll_pkg.calculate_salary(1,10,5000);
END;
/

-- Department Reports
BEGIN
    payroll_pkg.department_report(1);
    payroll_pkg.department_report(2);
    payroll_pkg.department_report(3);
    payroll_pkg.department_report(4);
END;
/

-- Audit Log
SELECT * FROM salary_audit;
