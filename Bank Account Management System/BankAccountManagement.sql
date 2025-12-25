/************************************************************************************
*                                                                                   *
*                       BANK ACCOUNT MANAGEMENT SYSTEM                              *
*                                                                                   *
************************************************************************************/

-- DOMAIN: Banking
-- DESCRIPTION: This script creates the tables, sequences, procedures, functions, and triggers
--              for a basic bank account management system.
--
-- FEATURES:
-- 1. Create customer and account
-- 2. Deposit & withdraw money
-- 3. Balance inquiry
-- 4. Transaction history
-- 5. Insufficient balance handling
--
-- PL/SQL CONCEPTS USED:
-- 1. Stored Procedures
-- 2. Functions
-- 3. Triggers
-- 4. Exception Handling
-- 5. Sequences

/************************************************************************************
*                                 TABLE DEFINITIONS                                 *
************************************************************************************/

CREATE TABLE customers (
    customer_id     NUMBER PRIMARY KEY,
    first_name      VARCHAR2(50) NOT NULL,
    last_name       VARCHAR2(50) NOT NULL,
    address         VARCHAR2(100),
    phone_number    VARCHAR2(20)
);

CREATE TABLE accounts (
    account_id      NUMBER PRIMARY KEY,
    customer_id     NUMBER,
    account_type    VARCHAR2(20) CHECK (account_type IN ('SAVINGS', 'CHECKING')),
    balance         NUMBER(15, 2) DEFAULT 0.00,
    CONSTRAINT fk_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE transactions (
    transaction_id      NUMBER PRIMARY KEY,
    account_id          NUMBER,
    transaction_type    VARCHAR2(20) CHECK (transaction_type IN ('DEPOSIT', 'WITHDRAWAL')),
    amount              NUMBER(15, 2),
    transaction_date    DATE,
    CONSTRAINT fk_account FOREIGN KEY (account_id) REFERENCES accounts(account_id)
);

/************************************************************************************
*                               SEQUENCES                                           *
************************************************************************************/

CREATE SEQUENCE customers_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE accounts_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE transactions_seq START WITH 1 INCREMENT BY 1;

/************************************************************************************
*                               STORED PROCEDURES                                   *
************************************************************************************/

-- Procedure to deposit money into an account
CREATE OR REPLACE PROCEDURE deposit (
    p_account_id IN accounts.account_id%TYPE,
    p_amount     IN transactions.amount%TYPE
)
AS
BEGIN
    -- A deposit amount must be positive
    IF p_amount <= 0 THEN
        RAISE_APPLICATION_ERROR(-20010, 'Deposit amount must be positive.');
    END IF;

    UPDATE accounts
    SET balance = balance + p_amount
    WHERE account_id = p_account_id;

    -- If no rows were updated, the account doesn't exist
    IF SQL%NOTFOUND THEN
        RAISE_APPLICATION_ERROR(-20002, 'Account not found.');
    END IF;

    INSERT INTO transactions (transaction_id, account_id, transaction_type, amount, transaction_date)
    VALUES (transactions_seq.NEXTVAL, p_account_id, 'DEPOSIT', p_amount, SYSDATE);

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Deposit of ' || p_amount || ' to account ' || p_account_id || ' successful.');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

-- Procedure to withdraw money from an account
CREATE OR REPLACE PROCEDURE withdraw (
    p_account_id IN accounts.account_id%TYPE,
    p_amount     IN transactions.amount%TYPE
)
AS
    v_balance accounts.balance%TYPE;
BEGIN
    -- A withdrawal amount must be positive
    IF p_amount <= 0 THEN
        RAISE_APPLICATION_ERROR(-20011, 'Withdrawal amount must be positive.');
    END IF;

    -- Lock the row for update to prevent race conditions
    SELECT balance INTO v_balance
    FROM accounts
    WHERE account_id = p_account_id
    FOR UPDATE;

    IF v_balance >= p_amount THEN
        UPDATE accounts
        SET balance = balance - p_amount
        WHERE account_id = p_account_id;

        INSERT INTO transactions (transaction_id, account_id, transaction_type, amount, transaction_date)
        VALUES (transactions_seq.NEXTVAL, p_account_id, 'WITHDRAWAL', p_amount, SYSDATE);

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Withdrawal of ' || p_amount || ' from account ' || p_account_id || ' successful.');
    ELSE
        ROLLBACK; -- Rollback the FOR UPDATE lock
        RAISE_APPLICATION_ERROR(-20001, 'Insufficient balance.');
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20002, 'Account not found.');
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

/************************************************************************************
*                                    FUNCTIONS                                      *
************************************************************************************/

-- Function to get the current balance of an account
CREATE OR REPLACE FUNCTION get_balance (
    p_account_id IN accounts.account_id%TYPE
)
RETURN NUMBER
AS
    v_balance accounts.balance%TYPE;
BEGIN
    SELECT balance INTO v_balance
    FROM accounts
    WHERE account_id = p_account_id;

    RETURN v_balance;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20002, 'Account not found');
END;
/

/************************************************************************************
*                                     TRIGGERS                                      *
************************************************************************************/

-- This trigger is redundant if all balance updates happen through the procedures.
-- However, it can serve as a safeguard against direct table manipulation.
CREATE OR REPLACE TRIGGER trg_log_transactions
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    DBMS_OUTPUT.PUT_LINE('Transaction logged: ID ' || :NEW.transaction_id || ', Type: ' || :NEW.transaction_type || ', Amount: ' || :NEW.amount);
END;
/

/************************************************************************************
*                                    TEST CASES                                     *
************************************************************************************/

SET SERVEROUTPUT ON;

DECLARE
    v_customer_id_1 NUMBER;
    v_account_id_1  NUMBER;
    v_customer_id_2 NUMBER;
    v_account_id_2  NUMBER;
    v_balance       NUMBER;

    PROCEDURE run_test(test_name VARCHAR2, test_code PLS_INTEGER) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('----- RUNNING TEST: ' || test_name || ' -----');
        IF test_code = 1 THEN
            DBMS_OUTPUT.PUT_LINE('Test Passed.');
        ELSE
            DBMS_OUTPUT.PUT_LINE('Test FAILED.');
        END IF;
        DBMS_OUTPUT.PUT_LINE('------------------------------------------');
    END;

BEGIN
    -- Clean up previous test data
    EXECUTE IMMEDIATE 'TRUNCATE TABLE transactions';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE accounts';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE customers';
    
    -- Test Case 1: Create a new customer
    INSERT INTO customers (customer_id, first_name, last_name, address, phone_number)
    VALUES (customers_seq.NEXTVAL, 'John', 'Doe', '123 Main St', '555-1234')
    RETURNING customer_id INTO v_customer_id_1;
    run_test('Create Customer 1', v_customer_id_1);

    -- Test Case 2: Create a new account for the customer
    INSERT INTO accounts (account_id, customer_id, account_type, balance)
    VALUES (accounts_seq.NEXTVAL, v_customer_id_1, 'SAVINGS', 1000)
    RETURNING account_id INTO v_account_id_1;
    run_test('Create Account 1', v_account_id_1);

    -- Test Case 3: Deposit a valid amount
    deposit(v_account_id_1, 500);
    run_test('Deposit valid amount', (get_balance(v_account_id_1) = 1500));

    -- Test Case 4: Withdraw a valid amount
    withdraw(v_account_id_1, 200);
    run_test('Withdraw valid amount', (get_balance(v_account_id_1) = 1300));
    
    -- Test Case 5: Attempt to withdraw more than the balance
    BEGIN
        withdraw(v_account_id_1, 2000);
        run_test('Withdraw insufficient funds', 0); -- Should not reach here
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20001 THEN
                run_test('Withdraw insufficient funds', 1);
            ELSE
                run_test('Withdraw insufficient funds', 0);
            END IF;
    END;
    
    -- Test Case 6: Attempt a transaction on a non-existent account
    BEGIN
        deposit(999, 100);
        run_test('Deposit to non-existent account', 0); -- Should not reach here
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20002 THEN
                run_test('Deposit to non-existent account', 1);
            ELSE
                run_test('Deposit to non-existent account', 0);
            END IF;
    END;

    -- Test Case 7: Verify balance after several transactions
    deposit(v_account_id_1, 100);
    withdraw(v_account_id_1, 50);
    run_test('Verify balance after multiple transactions', (get_balance(v_account_id_1) = 1350));
    
    -- Test Case 8: Create a second customer and account
    INSERT INTO customers (customer_id, first_name, last_name, address, phone_number)
    VALUES (customers_seq.NEXTVAL, 'Jane', 'Smith', '456 Oak Ave', '555-5678')
    RETURNING customer_id INTO v_customer_id_2;
    run_test('Create Customer 2', v_customer_id_2);
    
    INSERT INTO accounts (account_id, customer_id, account_type, balance)
    VALUES (accounts_seq.NEXTVAL, v_customer_id_2, 'CHECKING', 500)
    RETURNING account_id INTO v_account_id_2;
    run_test('Create Account 2', v_account_id_2);

    -- Test Case 9: Withdraw all money from an account
    withdraw(v_account_id_2, 500);
    run_test('Withdraw all money', (get_balance(v_account_id_2) = 0));

    -- Test Case 10: Deposit to a zero-balance account
    deposit(v_account_id_2, 250);
    run_test('Deposit to zero-balance account', (get_balance(v_account_id_2) = 250));

    -- Test Case 11: Attempt to withdraw from a zero-balance account
    withdraw(v_account_id_2, 250); -- Make it zero again
    BEGIN
        withdraw(v_account_id_2, 1);
        run_test('Withdraw from zero-balance account', 0); -- Should not reach here
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20001 THEN
                run_test('Withdraw from zero-balance account', 1);
            ELSE
                run_test('Withdraw from zero-balance account', 0);
            END IF;
    END;
    
    -- Test Case 12: Deposit a large amount
    deposit(v_account_id_1, 10000);
    run_test('Deposit large amount', (get_balance(v_account_id_1) = 11350));
    
    -- Test Case 13: Withdraw a large amount
    withdraw(v_account_id_1, 5000);
    run_test('Withdraw large amount', (get_balance(v_account_id_1) = 6350));
    
    -- Test Case 14: Attempt to deposit a negative amount
    BEGIN
        deposit(v_account_id_1, -100);
        run_test('Deposit negative amount', 0);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20010 THEN
                run_test('Deposit negative amount', 1);
            ELSE
                run_test('Deposit negative amount', 0);
            END IF;
    END;
    
    -- Test Case 15: Attempt to withdraw a negative amount
    BEGIN
        withdraw(v_account_id_1, -100);
        run_test('Withdraw negative amount', 0);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20011 THEN
                run_test('Withdraw negative amount', 1);
            ELSE
                run_test('Withdraw negative amount', 0);
            END IF;
    END;
    
    -- Final Check: Transaction History
    DECLARE
        v_count NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_count FROM transactions WHERE account_id = v_account_id_1;
        DBMS_OUTPUT.PUT_LINE('----- FINAL CHECK: Transaction count for Account 1 should be 6 -----');
        run_test('Transaction History Count', (v_count = 6));
    END;
    
    ROLLBACK; -- Rollback all test changes
END;
/