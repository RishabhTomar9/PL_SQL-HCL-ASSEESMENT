/*=====================================================
  ENABLE OUTPUT
=====================================================*/
SET SERVEROUTPUT ON;

/*=====================================================
  OPTIONAL CLEANUP (use only if re-running)
=====================================================*/
-- DROP TRIGGER trg_audit_stock_changes;
-- DROP TRIGGER trg_alert_low_stock;
-- DROP TABLE stock_audit;
-- DROP TABLE stock_movements;
-- DROP TABLE products;
-- DROP TABLE product_categories;
-- DROP SEQUENCE categories_seq;
-- DROP SEQUENCE products_seq;
-- DROP SEQUENCE stock_movement_seq;
-- DROP SEQUENCE stock_audit_seq;

/*=====================================================
  1. TABLES
=====================================================*/
CREATE TABLE product_categories (
    category_id   NUMBER PRIMARY KEY,
    category_name VARCHAR2(50) UNIQUE NOT NULL
);

CREATE TABLE products (
    product_id    NUMBER PRIMARY KEY,
    product_name  VARCHAR2(50),
    category_id   NUMBER,
    entry_date    DATE,
    quantity      NUMBER,
    unit_price    NUMBER(10, 2),
    CONSTRAINT fk_cat FOREIGN KEY (category_id)
        REFERENCES product_categories(category_id)
);

CREATE TABLE stock_movements (
    movement_id      NUMBER PRIMARY KEY,
    product_id       NUMBER,
    movement_date    DATE,
    movement_type    VARCHAR2(3), -- 'IN' or 'OUT'
    quantity_changed NUMBER,
    CONSTRAINT fk_prod FOREIGN KEY (product_id)
        REFERENCES products(product_id)
);

CREATE TABLE stock_audit (
    audit_id        NUMBER PRIMARY KEY,
    product_id      NUMBER,
    old_quantity    NUMBER,
    new_quantity    NUMBER,
    change_date     DATE,
    changed_by      VARCHAR2(30)
);

/*=====================================================
  2. SEQUENCES
=====================================================*/
CREATE SEQUENCE categories_seq START WITH 1;
CREATE SEQUENCE products_seq   START WITH 1;
CREATE SEQUENCE stock_movement_seq START WITH 1;
CREATE SEQUENCE stock_audit_seq    START WITH 1;

/*=====================================================
  3. SAMPLE DATA
=====================================================*/
INSERT INTO product_categories VALUES (categories_seq.NEXTVAL,'Electronics');
INSERT INTO product_categories VALUES (categories_seq.NEXTVAL,'Apparel');
INSERT INTO product_categories VALUES (categories_seq.NEXTVAL,'Groceries');
INSERT INTO product_categories VALUES (categories_seq.NEXTVAL,'Furniture');

INSERT INTO products VALUES (products_seq.NEXTVAL,'Laptop',1,SYSDATE-100,50,1200);
INSERT INTO products VALUES (products_seq.NEXTVAL,'T-Shirt',2,SYSDATE-50,200,25);
INSERT INTO products VALUES (products_seq.NEXTVAL,'Apples',3,SYSDATE-5,500,1.5);
INSERT INTO products VALUES (products_seq.NEXTVAL,'Desk Chair',4,SYSDATE-200,20,150);
INSERT INTO products VALUES (products_seq.NEXTVAL,'Smartphone',1,SYSDATE-80,100,800);

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
  5. PACKAGE – INVENTORY LOGIC
=====================================================*/
CREATE OR REPLACE PACKAGE inventory_pkg IS
    FUNCTION check_stock_level(p_product_id NUMBER) RETURN VARCHAR2;
    PROCEDURE record_stock_movement(
        p_product_id NUMBER,
        p_movement_type VARCHAR2,
        p_quantity NUMBER
    );
    PROCEDURE category_stock_report(p_cat_id NUMBER);
END inventory_pkg;
/

CREATE OR REPLACE PACKAGE BODY inventory_pkg IS

FUNCTION check_stock_level(p_product_id NUMBER) RETURN VARCHAR2 IS
    v_quantity NUMBER;
BEGIN
    SELECT quantity INTO v_quantity
    FROM products WHERE product_id = p_product_id;

    IF v_quantity <= 20 THEN
        RETURN 'Low Stock';
    ELSE
        RETURN 'In Stock';
    END IF;
END;

PROCEDURE record_stock_movement(
    p_product_id NUMBER,
    p_movement_type VARCHAR2,
    p_quantity NUMBER
) IS
    v_current_qty NUMBER;
    v_new_qty NUMBER;
BEGIN
    SELECT quantity INTO v_current_qty
    FROM products WHERE product_id = p_product_id;

    IF p_movement_type = 'IN' THEN
        v_new_qty := v_current_qty + p_quantity;
    ELSIF p_movement_type = 'OUT' THEN
        v_new_qty := v_current_qty - p_quantity;
    ELSE
        RAISE_APPLICATION_ERROR(-20001, 'Invalid movement type. Use IN or OUT.');
    END IF;

    IF v_new_qty < 0 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Insufficient stock for this movement.');
    END IF;

    UPDATE products SET quantity = v_new_qty WHERE product_id = p_product_id;

    INSERT INTO stock_movements
    VALUES (stock_movement_seq.NEXTVAL, p_product_id, SYSDATE, p_movement_type, p_quantity);

    print_line('✔ Stock movement recorded for Product ID '||p_product_id||
               ' | New Quantity: '||v_new_qty);
END;

PROCEDURE category_stock_report(p_cat_id NUMBER) IS
    CURSOR c IS
        SELECT p.product_name,
               p.quantity,
               p.unit_price
        FROM products p
        WHERE p.category_id=p_cat_id
        ORDER BY p.product_name;
    v_name product_categories.category_name%TYPE;
BEGIN
    SELECT category_name INTO v_name
    FROM product_categories WHERE category_id=p_cat_id;

    print_line(CHR(10)||'======================================================');
    print_line('CATEGORY STOCK REPORT : '||v_name);
    print_line('======================================================');
    print_line(RPAD('PRODUCT',25)||' | '||
               LPAD('QUANTITY',15)||' | UNIT PRICE');
    print_line(RPAD('-',25,'-')||'-+-'||
               LPAD('-',15,'-')||'-+-'||
               RPAD('-',15,'-'));

    FOR r IN c LOOP
        print_line(RPAD(r.product_name,25)||' | '||
                   LPAD(r.quantity,15)||' | '||
                   TO_CHAR(r.unit_price,'99,99,999.99'));
    END LOOP;

    print_line('======================================================');
END;

END inventory_pkg;
/

/*=====================================================
  6. TRIGGER – STOCK AUDIT
=====================================================*/
CREATE OR REPLACE TRIGGER trg_audit_stock_changes
BEFORE UPDATE OF quantity ON products
FOR EACH ROW
BEGIN
    INSERT INTO stock_audit
    VALUES (
        stock_audit_seq.NEXTVAL,
        :OLD.product_id,
        :OLD.quantity,
        :NEW.quantity,
        SYSDATE,
        USER
    );
END;
/

/*=====================================================
  7. TRIGGER – LOW STOCK ALERT
=====================================================*/
CREATE OR REPLACE TRIGGER trg_alert_low_stock
AFTER UPDATE OF quantity ON products
FOR EACH ROW
WHEN (NEW.quantity < 20)
BEGIN
    print_line('⚠ Low stock warning for Product ID '||:OLD.product_id || '. Current quantity is ' || :NEW.quantity);
END;
/

/*=====================================================
  8. EXECUTION / TEST CASES
=====================================================*/
BEGIN
    inventory_pkg.record_stock_movement(1, 'OUT', 10); -- Sell 10 Laptops
    inventory_pkg.record_stock_movement(2, 'OUT', 50); -- Sell 50 T-shirts
    inventory_pkg.record_stock_movement(3, 'IN', 100);  -- Stock 100 Apples
    inventory_pkg.record_stock_movement(5, 'OUT', 85); -- Sell 85 smartphones, should trigger low stock alert
END;
/

-- Stock level check
DECLARE
    v_status VARCHAR2(20);
BEGIN
    v_status := inventory_pkg.check_stock_level(5);
    print_line('Stock status for product 5: ' || v_status);
END;
/


-- Category Reports
BEGIN
    inventory_pkg.category_stock_report(1);
    inventory_pkg.category_stock_report(2);
    inventory_pkg.category_stock_report(3);
END;
/

-- Audit Log
SELECT * FROM stock_audit;