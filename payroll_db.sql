CREATE DATABASE Payroll;
USE Payroll;
-- Table to store login credentials for admin and employees
CREATE TABLE User (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE,
    password VARCHAR(100),
    role ENUM('admin','employee')
);
CREATE TABLE Department (
    dept_id INT AUTO_INCREMENT PRIMARY KEY,
    dept_name VARCHAR(50)
);
-- Table to store employee personal and job details
CREATE TABLE Employee (
    employee_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT UNIQUE,
    name VARCHAR(100),
    father_name VARCHAR(100),
    email VARCHAR(100),
    phone VARCHAR(15),
    address TEXT,
    designation VARCHAR(50),
    date_of_joining DATE,
    basic_salary DECIMAL(10,2),
    dept_id INT,
    FOREIGN KEY (user_id) REFERENCES User(user_id),
    FOREIGN KEY (dept_id) REFERENCES Department(dept_id)
);
-- Stores daily attendance marked by admin
CREATE TABLE Attendance (
    attendance_id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT,
    date DATE,
    status ENUM('Present','Absent','Leave','Half-day'),
    UNIQUE(employee_id, date),
    FOREIGN KEY (employee_id) REFERENCES Employee(employee_id)
);
-- Employees apply leave, admin approves/rejects
CREATE TABLE Leave_Request (
    leave_id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT,
    start_date DATE,
    end_date DATE,
    reason TEXT,
    status ENUM('Pending','Approved','Rejected') DEFAULT 'Pending',
    FOREIGN KEY (employee_id) REFERENCES Employee(employee_id)
);
-- Tracks total, used, and remaining leaves
CREATE TABLE Leave_Balance (
    employee_id INT,
    month INT,
    year INT,
    total_leaves INT DEFAULT 5,
    used_leaves INT DEFAULT 0,
    remaining_leaves INT DEFAULT 5,
    PRIMARY KEY (employee_id, month, year),
    FOREIGN KEY (employee_id) REFERENCES Employee(employee_id)
);
SELECT * FROM Leave_Balance;
-- Stores overtime work done by employees
CREATE TABLE Overtime (
    overtime_id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT,
    date DATE,
    hours INT,
    FOREIGN KEY (employee_id) REFERENCES Employee(employee_id)
);
-- Table to store salary components
CREATE TABLE Salary_Components (
    employee_id INT PRIMARY KEY,
    basic DECIMAL(10,2),
    hra DECIMAL(10,2),
    da DECIMAL(10,2),
    other_allowances DECIMAL(10,2),
    FOREIGN KEY (employee_id) REFERENCES Employee(employee_id)
);
-- table to store employee performance and pay accordingly
CREATE TABLE Performance (
    performance_id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT,
    month INT,
    year INT,
    score INT,
    FOREIGN KEY (employee_id) REFERENCES Employee(employee_id)
);
-- tax on monthly salaries
CREATE TABLE Tax_Slabs (
    slab_id INT AUTO_INCREMENT PRIMARY KEY,
    min_salary DECIMAL(10,2),
    max_salary DECIMAL(10,2),
    tax_percent DECIMAL(5,2)
);
-- Stores salary details calculated automatically
CREATE TABLE Payroll (
    payroll_id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id INT,
    month INT,
    year INT,
    basic_salary DECIMAL(10,2),
    attendance_salary DECIMAL(10,2),
    overtime_pay DECIMAL(10,2),
    bonus DECIMAL(10,2),
    deductions DECIMAL(10,2),
    tax DECIMAL(10,2),
    total_earnings DECIMAL(10,2),
    net_salary DECIMAL(10,2),
    UNIQUE(employee_id, month, year),
    FOREIGN KEY (employee_id) REFERENCES Employee(employee_id)
);

DROP TRIGGER IF EXISTS validate_leave_before_insert;

DELIMITER $$

CREATE TRIGGER validate_leave_before_insert
BEFORE INSERT ON Leave_Request
FOR EACH ROW
BEGIN
    DECLARE remaining INT;
    DECLARE days_requested INT;
    DECLARE used INT;
    SET days_requested = DATEDIFF(NEW.end_date, NEW.start_date) + 1;
    -- Get remaining leaves
    SELECT remaining_leaves INTO remaining
    FROM Leave_Balance
    WHERE employee_id = NEW.employee_id
    AND month = MONTH(NEW.start_date)
    AND year = YEAR(NEW.start_date);
    -- ✅ FIX 1: Handle NULL (no record case)
    IF remaining IS NULL THEN
        SET remaining = 5;
    END IF;
    -- ✅ FIX 2: Count already requested leaves (Pending + Approved)
    SELECT IFNULL(SUM(DATEDIFF(end_date,start_date)+1),0)
    INTO used
    FROM Leave_Request
    WHERE employee_id = NEW.employee_id
    AND MONTH(start_date) = MONTH(NEW.start_date)
    AND YEAR(start_date) = YEAR(NEW.start_date)
    AND status IN ('Pending','Approved');
    -- ✅ FINAL VALIDATION
    IF (used + days_requested) > 5 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Leave limit exceeded for this month';
    END IF;
END$$

DELIMITER ;
-- DROP TRIGGER IF EXISTS update_leave_balance;
DELIMITER $$
CREATE TRIGGER update_leave_balance
AFTER UPDATE ON Leave_Request
FOR EACH ROW
BEGIN
    DECLARE days INT;
    DECLARE current_used INT DEFAULT 0;
    DECLARE total INT DEFAULT 5;
    DECLARE req_month INT;
    DECLARE req_year INT;
    -- Run only when status becomes Approved
    IF NEW.status = 'Approved' AND OLD.status <> 'Approved' THEN
        -- ❌ Prevent cross-month leave (IMPORTANT)
        IF MONTH(NEW.start_date) <> MONTH(NEW.end_date) 
           OR YEAR(NEW.start_date) <> YEAR(NEW.end_date) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Leave cannot span multiple months';
        END IF;
        -- Calculate number of leave days
        SET days = DATEDIFF(NEW.end_date, NEW.start_date) + 1;
        -- Get month and year
        SET req_month = MONTH(NEW.start_date);
        SET req_year = YEAR(NEW.start_date);
        -- ✅ Ensure monthly record exists
        IF NOT EXISTS (
            SELECT 1 FROM Leave_Balance 
            WHERE employee_id = NEW.employee_id
            AND month = req_month
            AND year = req_year
        ) THEN
            INSERT INTO Leave_Balance 
            (employee_id, month, year, total_leaves, used_leaves, remaining_leaves)
            VALUES (NEW.employee_id, req_month, req_year, 5, 0, 5);
        END IF;
        -- Get current values
        SELECT used_leaves, total_leaves
        INTO current_used, total
        FROM Leave_Balance
        WHERE employee_id = NEW.employee_id
        AND month = req_month
        AND year = req_year;
        -- ❌ Prevent exceeding leave limit
        IF (current_used + days) > total THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No leaves remaining for this month';
        END IF;
        -- ✅ Correct update
        UPDATE Leave_Balance
        SET 
            used_leaves = current_used + days,
            remaining_leaves = total - (current_used + days)
        WHERE employee_id = NEW.employee_id
        AND month = req_month
        AND year = req_year;
        -- ✅ Update attendance
        UPDATE Attendance
        SET status = 'Leave'
        WHERE employee_id = NEW.employee_id
        AND date BETWEEN NEW.start_date AND NEW.end_date;
    END IF;
END$$
DELIMITER ;
DROP TRIGGER IF EXISTS calculate_salary_final;
-- Trigger to automatically calculate salary before inserting payroll
DELIMITER $$
CREATE TRIGGER calculate_salary_final
BEFORE INSERT ON Payroll
FOR EACH ROW
BEGIN
    -- VARIABLES
    DECLARE basic DECIMAL(10,2) DEFAULT 0;
    DECLARE per_day DECIMAL(10,2);
    DECLARE days_in_month INT;
    DECLARE present_days INT DEFAULT 0;
    DECLARE half_days INT DEFAULT 0;
    DECLARE attendance_salary_calc DECIMAL(10,2);
    DECLARE overtime_hours INT DEFAULT 0;
    DECLARE overtime_pay_calc DECIMAL(10,2);
    DECLARE hra DECIMAL(10,2) DEFAULT 0;
    DECLARE da DECIMAL(10,2) DEFAULT 0;
    DECLARE other DECIMAL(10,2) DEFAULT 0;
    DECLARE perf_score INT DEFAULT 0;
    DECLARE perf_bonus DECIMAL(10,2) DEFAULT 0;
    DECLARE tax_rate DECIMAL(5,2) DEFAULT 0;
    -- ✅ FETCH BASIC + SALARY COMPONENTS USING JOIN
    SELECT e.basic_salary, 
           IFNULL(sc.hra,0), 
           IFNULL(sc.da,0), 
           IFNULL(sc.other_allowances,0)
    INTO basic, hra, da, other
    FROM Employee e
    LEFT JOIN Salary_Components sc
    ON e.employee_id = sc.employee_id
    WHERE e.employee_id = NEW.employee_id;
    -- ✅ DAYS IN MONTH
    SET days_in_month = DAY(LAST_DAY(
        STR_TO_DATE(CONCAT(NEW.year,'-',NEW.month,'-01'), '%Y-%m-%d')
    ));
    SET per_day = basic / days_in_month;
    -- ✅ PRESENT + LEAVE (PAID)
    SELECT COUNT(*) INTO present_days
    FROM Attendance
    WHERE employee_id = NEW.employee_id
    AND MONTH(date)=NEW.month 
    AND YEAR(date)=NEW.year
    AND status IN ('Present','Leave');
    -- HALF DAYS
    SELECT COUNT(*) INTO half_days
    FROM Attendance
    WHERE employee_id = NEW.employee_id
    AND MONTH(date)=NEW.month 
    AND YEAR(date)=NEW.year
    AND status='Half-day';
    -- ATTENDANCE SALARY
    SET attendance_salary_calc =
        (present_days * per_day) +
        (half_days * per_day * 0.5);
    -- ✅ OVERTIME
    SELECT IFNULL(SUM(hours),0) INTO overtime_hours
    FROM Overtime
    WHERE employee_id = NEW.employee_id
    AND MONTH(date)=NEW.month 
    AND YEAR(date)=NEW.year;
    SET overtime_pay_calc = overtime_hours * (per_day/8);
    -- ✅ PERFORMANCE BONUS USING JOIN
    SELECT IFNULL(p.score,0)
    INTO perf_score
    FROM Performance p
    LEFT JOIN Employee e
    ON p.employee_id = e.employee_id
    WHERE p.employee_id = NEW.employee_id
    AND p.month = NEW.month 
    AND p.year = NEW.year
    LIMIT 1;
    IF perf_score > 90 THEN
        SET perf_bonus = 6000;
    ELSEIF perf_score >= 75 THEN
        SET perf_bonus = 4000;
    ELSEIF perf_score >= 60 THEN
        SET perf_bonus = 2000;
    ELSE
        SET perf_bonus = 0;
    END IF;
    -- STORE VALUES
    SET NEW.basic_salary = basic;
    SET NEW.attendance_salary = attendance_salary_calc;
    SET NEW.overtime_pay = overtime_pay_calc;
    -- TOTAL EARNINGS
    SET NEW.total_earnings =
        attendance_salary_calc + overtime_pay_calc + hra + da + other + NEW.bonus + perf_bonus;
    -- ✅ TAX USING SLAB
    SELECT IFNULL(ts.tax_percent,0)
    INTO tax_rate
    FROM Tax_Slabs ts
    WHERE NEW.total_earnings BETWEEN ts.min_salary AND ts.max_salary
    LIMIT 1;
    SET NEW.tax = (NEW.total_earnings * tax_rate) / 100;
    -- FINAL NET SALARY
    SET NEW.net_salary =
        NEW.total_earnings - NEW.tax - NEW.deductions;
END$$
DELIMITER ;
DELIMITER $$
CREATE EVENT monthly_leave_reset
ON SCHEDULE EVERY 1 MONTH
STARTS '2025-10-01 00:00:00'
DO
BEGIN
    INSERT INTO Leave_Balance (employee_id, month, year, total_leaves, used_leaves, remaining_leaves)
    SELECT 
        employee_id,
        MONTH(CURRENT_DATE),
        YEAR(CURRENT_DATE),
        5,0,5
    FROM Employee;
END$$
DELIMITER ;
INSERT INTO Department (dept_name)
VALUES ('IT'),('HR'),('Finance');
INSERT INTO User (username, password, role)
VALUES 
('admin1','admin123','admin'),
('emp1','emp123','employee'),
('emp2','emp234','employee');
INSERT INTO Employee 
(user_id, name, father_name, email, phone, address, designation, date_of_joining, basic_salary, dept_id)
VALUES
(2, 'Mohan Kumar', 'Suresh Kumar', 'mohan@gmail.com', '9876543210', 'Hyderabad', 'Developer', '2023-06-15', 30000, 1),
(3, 'Pooja Sharma', 'Ramesh Sharma', 'pooja@gmail.com', '9123456780', 'Bangalore', 'Designer', '2024-01-10', 25000, 2);
INSERT INTO Leave_Balance (employee_id, month, year)
VALUES
(1, 9, 2025),
(2, 9, 2025);
INSERT INTO Attendance (employee_id, date, status)
VALUES
-- Mohan
(1, '2025-09-01', 'Present'),
(1, '2025-09-02', 'Present'),
(1, '2025-09-03', 'Half-day'),
(1, '2025-09-04', 'Absent'),
-- Pooja
(2, '2025-09-01', 'Present'),
(2, '2025-09-02', 'Half-day'),
(2, '2025-09-03', 'Present');
INSERT INTO Overtime (employee_id, date, hours)
VALUES
(1, '2025-09-01', 4),
(1, '2025-09-02', 2),
(2, '2025-09-01', 3);
INSERT INTO Salary_Components 
(employee_id, basic, hra, da, other_allowances)
VALUES
(1, 30000, 8000, 4000, 2000),
(2, 25000, 6000, 3000, 1500);
INSERT INTO Performance 
(employee_id, month, year, score)
VALUES
(1, 9, 2025, 95),
(2, 9, 2025, 80);
INSERT INTO Tax_Slabs (min_salary, max_salary, tax_percent)
VALUES
(0, 10000, 5),
(10001, 25000, 10),
(25001, 50000, 20),
(50001, 9999999, 30);
UPDATE Leave_Balance
SET used_leaves = 0,
    remaining_leaves = total_leaves
WHERE employee_id > 0;
TRUNCATE TABLE Leave_Request;
INSERT INTO Leave_Request (employee_id, start_date, end_date, reason)
VALUES
(1,'2025-09-10','2025-09-12','Medical Leave'),
(2,'2025-09-15','2025-09-16','Personal');
-- checking not enough leave balance
INSERT INTO Leave_Request(employee_id,start_date,end_date,reason)
VALUES
(1,'2025-09-13','2025-09-19','Paid leave');
UPDATE Leave_Request SET status='Approved' WHERE leave_id=1;
UPDATE Leave_Request SET status='Approved' WHERE leave_id=2;
SELECT * FROM Leave_Request;
SELECT * FROM Leave_Balance;
TRUNCATE TABLE Payroll;
INSERT INTO Payroll 
(employee_id, month, year, bonus, deductions)
VALUES
(1, 9, 2025, 5000, 2000),
(2, 9, 2025, 3000, 1500);
SELECT * FROM Payroll;
SELECT * FROM Tax_Slabs;
-- View for admin to see all leave requests
CREATE OR REPLACE VIEW admin_leave_requests AS
SELECT 
    lr.leave_id,e.employee_id,e.name,lr.start_date,lr.end_date,lr.reason,lr.status
FROM Leave_Request lr
JOIN Employee e 
ON lr.employee_id = e.employee_id;
SELECT * FROM admin_leave_requests;
-- view for employee to see respective leave history 
CREATE OR REPLACE VIEW employee_leave_history AS
SELECT 
    leave_id,employee_id,start_date,end_date,reason,status
FROM Leave_Request;
SELECT * FROM employee_leave_history WHERE employee_id = 1;
-- View for admin to see all payroll data
CREATE OR REPLACE VIEW admin_payroll_view AS
SELECT 
    p.payroll_id,e.employee_id,e.name,p.month,p.year,p.basic_salary,p.attendance_salary,p.overtime_pay,p.bonus,p.deductions,p.tax,
    p.total_earnings,p.net_salary
FROM Payroll p
JOIN Employee e 
ON p.employee_id = e.employee_id;
SELECT * FROM admin_payroll_view;
-- view for employee to see all the respective payroll history data
CREATE OR REPLACE VIEW employee_payroll_history AS
SELECT 
    payroll_id,employee_id,month,year,basic_salary,attendance_salary,overtime_pay,bonus,deductions,tax,total_earnings,net_salary
FROM Payroll;
SELECT * FROM employee_payroll_history WHERE employee_id = 2;
-- view for employee to view his daily attendence as marked by admin
CREATE OR REPLACE VIEW employee_attendance_detailed AS
SELECT 
    a.employee_id,e.name,a.date,a.status
FROM Attendance a
JOIN Employee e 
ON a.employee_id = e.employee_id;
SELECT * FROM employee_attendance_detailed WHERE employee_id = 1;
-- to view an employee with highest salary in the company
SELECT e.employee_id, e.name, p.net_salary
FROM Payroll p
JOIN Employee e 
ON p.employee_id = e.employee_id
WHERE p.net_salary = (SELECT MAX(net_salary) FROM Payroll);
-- to view the total salary distributed by company to all the employees
SELECT SUM(net_salary) AS total_salary_paid
FROM Payroll;
-- to view total no.of used leaves by all the employees
SELECT e.employee_id, e.name, lb.used_leaves
FROM Leave_Balance lb
JOIN Employee e 
ON lb.employee_id = e.employee_id;
-- avg salary
SELECT AVG(basic_salary) AS avg_basic_salary
FROM Employee;
-- counting no.of employees per department
SELECT d.dept_name, COUNT(e.employee_id) AS employee_count
FROM Department d
LEFT JOIN Employee e ON d.dept_id = e.dept_id
GROUP BY d.dept_id, d.dept_name;
-- overtime hours 
SELECT e.name, SUM(o.hours) AS total_ot_hours
FROM Employee e
JOIN Overtime o ON e.employee_id = o.employee_id
WHERE MONTH(o.date) = 9 AND YEAR(o.date) = 2025
GROUP BY e.employee_id, e.name;
-- no overtime
SELECT e.name
FROM Employee e
WHERE e.employee_id NOT IN (
    SELECT DISTINCT employee_id FROM Overtime
);

CREATE OR REPLACE VIEW admin_emp_attendance_summary AS
SELECT a.employee_id, e.name,
       MONTH(a.date) AS month, YEAR(a.date) AS year,
       COUNT(CASE WHEN a.status = 'Present'  THEN 1 END) AS present_days,
       COUNT(CASE WHEN a.status = 'Absent'   THEN 1 END) AS absent_days,
       COUNT(CASE WHEN a.status = 'Leave'    THEN 1 END) AS leave_days,
       COUNT(CASE WHEN a.status = 'Half-day' THEN 1 END) AS half_days
FROM Attendance a
JOIN Employee e ON a.employee_id = e.employee_id
GROUP BY a.employee_id, e.name, MONTH(a.date), YEAR(a.date);



