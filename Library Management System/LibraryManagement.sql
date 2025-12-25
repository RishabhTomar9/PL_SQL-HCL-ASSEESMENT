-- Library Management System
-- Domain: Education / Institution

-- Tables
CREATE TABLE members (
    member_id NUMBER PRIMARY KEY,
    member_name VARCHAR2(100),
    join_date DATE
);

CREATE TABLE books (
    book_id NUMBER PRIMARY KEY,
    book_title VARCHAR2(200),
    author VARCHAR2(100),
    total_copies NUMBER,
    available_copies NUMBER
);

CREATE TABLE issue_return (
    issue_id NUMBER PRIMARY KEY,
    book_id NUMBER,
    member_id NUMBER,
    issue_date DATE,
    due_date DATE,
    return_date DATE,
    fine NUMBER,
    FOREIGN KEY (book_id) REFERENCES books(book_id),
    FOREIGN KEY (member_id) REFERENCES members(member_id)
);

-- Sequences
CREATE SEQUENCE members_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE books_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE issue_return_seq START WITH 1 INCREMENT BY 1;

-- Package
CREATE OR REPLACE PACKAGE library_pkg AS
    FUNCTION calculate_fine (p_due_date IN DATE, p_return_date IN DATE) RETURN NUMBER;
    PROCEDURE issue_book (p_book_id IN NUMBER, p_member_id IN NUMBER);
    PROCEDURE return_book (p_issue_id IN NUMBER);
    PROCEDURE generate_overdue_report;
END library_pkg;
/

CREATE OR REPLACE PACKAGE BODY library_pkg AS
    FUNCTION calculate_fine (p_due_date IN DATE, p_return_date IN DATE) RETURN NUMBER AS
        v_days_overdue NUMBER;
    BEGIN
        v_days_overdue := p_return_date - p_due_date;
        IF v_days_overdue > 0 THEN
            RETURN v_days_overdue * 1; -- Assuming a fine of $1 per day
        ELSE
            RETURN 0;
        END IF;
    END calculate_fine;

    PROCEDURE issue_book (p_book_id IN NUMBER, p_member_id IN NUMBER) AS
        v_available_copies NUMBER;
    BEGIN
        SELECT available_copies INTO v_available_copies
        FROM books
        WHERE book_id = p_book_id;

        IF v_available_copies > 0 THEN
            INSERT INTO issue_return (issue_id, book_id, member_id, issue_date, due_date)
            VALUES (issue_return_seq.NEXTVAL, p_book_id, p_member_id, SYSDATE, SYSDATE + 14); -- 14 days due date

            UPDATE books
            SET available_copies = available_copies - 1
            WHERE book_id = p_book_id;

            COMMIT;
        ELSE
            RAISE_APPLICATION_ERROR(-20005, 'Book not available.');
        END IF;
    END issue_book;

    PROCEDURE return_book (p_issue_id IN NUMBER) AS
        v_due_date DATE;
        v_book_id NUMBER;
        v_fine NUMBER;
    BEGIN
        SELECT due_date, book_id INTO v_due_date, v_book_id
        FROM issue_return
        WHERE issue_id = p_issue_id;

        v_fine := calculate_fine(v_due_date, SYSDATE);

        UPDATE issue_return
        SET return_date = SYSDATE, fine = v_fine
        WHERE issue_id = p_issue_id;

        UPDATE books
        SET available_copies = available_copies + 1
        WHERE book_id = v_book_id;

        COMMIT;
    END return_book;

    PROCEDURE generate_overdue_report AS
        CURSOR c_overdue IS
            SELECT m.member_name, b.book_title, ir.due_date
            FROM issue_return ir
            JOIN members m ON ir.member_id = m.member_id
            JOIN books b ON ir.book_id = b.book_id
            WHERE ir.return_date IS NULL AND ir.due_date < SYSDATE;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('Overdue Books Report');
        DBMS_OUTPUT.PUT_LINE('--------------------');
        FOR overdue_rec IN c_overdue LOOP
            DBMS_OUTPUT.PUT_LINE('Member: ' || overdue_rec.member_name || ' | Book: ' || overdue_rec.book_title || ' | Due Date: ' || overdue_rec.due_date);
        END LOOP;
    END generate_overdue_report;

END library_pkg;
/

-- Triggers
CREATE OR REPLACE TRIGGER trg_auto_update_fine
BEFORE UPDATE ON issue_return
FOR EACH ROW
WHEN (NEW.return_date IS NOT NULL AND OLD.return_date IS NULL)
DECLARE
    v_fine NUMBER;
BEGIN
    v_fine := library_pkg.calculate_fine(:OLD.due_date, :NEW.return_date);
    :NEW.fine := v_fine;
END;
/


-- Example Usage:
-- INSERT MEMBERS
INSERT INTO members (member_id, member_name, join_date) VALUES (members_seq.NEXTVAL, 'Member One', SYSDATE);

-- INSERT BOOKS
INSERT INTO books (book_id, book_title, author, total_copies, available_copies)
VALUES (books_seq.NEXTVAL, 'The PL/SQL Journey', 'Author A', 5, 5);
INSERT INTO books (book_id, book_title, author, total_copies, available_copies)
VALUES (books_seq.NEXTVAL, 'Advanced Oracle', 'Author B', 3, 3);


-- ISSUE A BOOK
BEGIN
    library_pkg.issue_book(1, 1);
END;
/
-- Check issue
SELECT * FROM issue_return;

-- To test overdue, we need to update the due_date to past
-- UPDATE issue_return SET due_date = SYSDATE - 1 WHERE issue_id = 1;
-- COMMIT;


-- RETURN A BOOK (after due date to see fine)
-- BEGIN
--     library_pkg.return_book(1);
-- END;
-- /


-- GENERATE OVERDUE REPORT
BEGIN
    DBMS_OUTPUT.ENABLE;
    library_pkg.generate_overdue_report;
END;
/


-- CHECK AVAILABILITY
SELECT book_title, available_copies FROM books WHERE book_id = 1;
