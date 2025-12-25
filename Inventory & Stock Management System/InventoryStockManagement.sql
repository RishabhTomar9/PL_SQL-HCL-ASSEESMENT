-- Inventory & Stock Management System
-- Domain: Retail / Warehouse

-- Tables
CREATE TABLE suppliers (
    supplier_id NUMBER PRIMARY KEY,
    supplier_name VARCHAR2(100),
    contact_person VARCHAR2(100)
);

CREATE TABLE products (
    product_id NUMBER PRIMARY KEY,
    product_name VARCHAR2(100),
    supplier_id NUMBER,
    quantity_on_hand NUMBER,
    reorder_level NUMBER,
    FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id)
);

CREATE TABLE stock_transactions (
    transaction_id NUMBER PRIMARY KEY,
    product_id NUMBER,
    transaction_type VARCHAR2(10), -- 'IN' or 'OUT'
    quantity NUMBER,
    transaction_date DATE,
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- Sequences
CREATE SEQUENCE suppliers_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE products_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE stock_transactions_seq START WITH 1 INCREMENT BY 1;

-- Procedures
CREATE OR REPLACE PROCEDURE stock_in (
    p_product_id IN NUMBER,
    p_quantity IN NUMBER
) AS
BEGIN
    INSERT INTO stock_transactions (transaction_id, product_id, transaction_type, quantity, transaction_date)
    VALUES (stock_transactions_seq.NEXTVAL, p_product_id, 'IN', p_quantity, SYSDATE);
    
    COMMIT;
END;
/

CREATE OR REPLACE PROCEDURE stock_out (
    p_product_id IN NUMBER,
    p_quantity IN NUMBER
) AS
    v_quantity_on_hand NUMBER;
BEGIN
    SELECT quantity_on_hand INTO v_quantity_on_hand FROM products WHERE product_id = p_product_id;

    IF v_quantity_on_hand >= p_quantity THEN
        INSERT INTO stock_transactions (transaction_id, product_id, transaction_type, quantity, transaction_date)
        VALUES (stock_transactions_seq.NEXTVAL, p_product_id, 'OUT', p_quantity, SYSDATE);
        COMMIT;
    ELSE
        RAISE_APPLICATION_ERROR(-20003, 'Not enough stock available.');
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20004, 'Product not found.');
END;
/

-- Functions
CREATE OR REPLACE FUNCTION get_available_stock (
    p_product_id IN NUMBER
) RETURN NUMBER AS
    v_quantity_on_hand NUMBER;
BEGIN
    SELECT quantity_on_hand INTO v_quantity_on_hand
    FROM products
    WHERE product_id = p_product_id;
    
    RETURN v_quantity_on_hand;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20004, 'Product not found.');
END;
/

-- Triggers
CREATE OR REPLACE TRIGGER trg_update_stock_on_transaction
AFTER INSERT ON stock_transactions
FOR EACH ROW
BEGIN
    IF :NEW.transaction_type = 'IN' THEN
        UPDATE products
        SET quantity_on_hand = quantity_on_hand + :NEW.quantity
        WHERE product_id = :NEW.product_id;
    ELSIF :NEW.transaction_type = 'OUT' THEN
        UPDATE products
        SET quantity_on_hand = quantity_on_hand - :NEW.quantity
        WHERE product_id = :NEW.product_id;
    END IF;
END;
/

-- Low-stock Alert (using a procedure with a cursor)
CREATE OR REPLACE PROCEDURE check_low_stock AS
    CURSOR c_low_stock IS
        SELECT product_id, product_name, quantity_on_hand, reorder_level
        FROM products
        WHERE quantity_on_hand < reorder_level;
BEGIN
    DBMS_OUTPUT.PUT_LINE('Low Stock Report');
    DBMS_OUTPUT.PUT_LINE('----------------');
    FOR prod_rec IN c_low_stock LOOP
        DBMS_OUTPUT.PUT_LINE('Product: ' || prod_rec.product_name || ' | Current Stock: ' || prod_rec.quantity_on_hand || ' | Reorder Level: ' || prod_rec.reorder_level);
    END LOOP;
END;
/


-- Example Usage:
-- INSERT SUPPLIER
INSERT INTO suppliers (supplier_id, supplier_name, contact_person) VALUES (suppliers_seq.NEXTVAL, 'Supplier X', 'John Smith');

-- INSERT PRODUCT
INSERT INTO products (product_id, product_name, supplier_id, quantity_on_hand, reorder_level)
VALUES (products_seq.NEXTVAL, 'Laptop', 1, 50, 10);
INSERT INTO products (product_id, product_name, supplier_id, quantity_on_hand, reorder_level)
VALUES (products_seq.NEXTVAL, 'Mouse', 1, 100, 20);


-- STOCK IN
BEGIN
    stock_in(1, 20); -- Add 20 Laptops
END;
/

-- STOCK OUT (Sale)
BEGIN
    stock_out(2, 5); -- Sell 5 Mouses
END;
/

-- CHECK AVAILABLE STOCK
SELECT get_available_stock(1) FROM DUAL;

-- RUN LOW-STOCK ALERT
BEGIN
    DBMS_OUTPUT.ENABLE;
    stock_out(1, 60); -- Sell 60 laptops to make it low stock
    check_low_stock;
END;
/

-- VIEW TRANSACTIONS
SELECT p.product_name, st.transaction_type, st.quantity, st.transaction_date
FROM stock_transactions st
JOIN products p ON st.product_id = p.product_id;
