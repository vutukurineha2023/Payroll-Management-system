# PayrollPro — Employee Payroll Management System
## Full Stack: Node.js + Express + MySQL + HTML/CSS/JS

---

## SETUP INSTRUCTIONS

### Step 1: Install Node.js
Download from https://nodejs.org (LTS version)

### Step 2: Open terminal in this folder and install dependencies
```
npm install
```

### Step 3: Make sure MySQL Workbench is running
- Database name: Payroll
- Password: Neha@221014
- (Already set in server.js)

### Step 4: Run the server
```
node server.js
```

### Step 5: Open browser
Go to: http://localhost:3000

---

## LOGIN CREDENTIALS
| Role     | Username | Password  |
|----------|----------|-----------|
| Admin    | admin1   | admin123  |
| Employee | emp1     | emp123    |
| Employee | emp2     | emp234    |

---

## ROLE-BASED ACCESS

### ADMIN CAN:
- View dashboard with live stats
- Add/view employees
- Mark attendance (employees cannot)
- Approve/Reject leave requests (not apply)
- Add overtime records
- Update salary components (HRA, DA, allowances)
- Add performance scores
- Manage tax slabs
- Generate payroll (auto-calculated by MySQL trigger)
- View payslips for all employees

### EMPLOYEE CAN:
- View personal dashboard
- View their own attendance (read-only, marked by admin)
- Apply for leave (admin cannot)
- View leave balance and history
- View their own payroll and payslips

---

## PROJECT STRUCTURE
```
payroll_app/
├── server.js          ← Node.js backend (API)
├── package.json       ← Dependencies
├── public/
│   └── index.html     ← Frontend (HTML + CSS + JS)
└── README.md
```

---

## API ENDPOINTS
| Method | Endpoint                   | Description              |
|--------|----------------------------|--------------------------|
| POST   | /api/login                 | User login               |
| GET    | /api/employees             | List all employees       |
| POST   | /api/employees             | Add new employee         |
| GET    | /api/departments           | List departments         |
| GET    | /api/attendance            | Get attendance records   |
| POST   | /api/attendance            | Mark attendance (admin)  |
| GET    | /api/leaves                | Get leave requests       |
| POST   | /api/leaves                | Apply leave (employee)   |
| PUT    | /api/leaves/:id            | Approve/Reject (admin)   |
| GET    | /api/leave-balance         | Get leave balance        |
| GET    | /api/overtime              | Get overtime records     |
| POST   | /api/overtime              | Add overtime (admin)     |
| GET    | /api/salary-components/:id | Get salary components    |
| POST   | /api/salary-components     | Update salary components |
| GET    | /api/performance           | Get performance scores   |
| POST   | /api/performance           | Add performance score    |
| GET    | /api/tax-slabs             | Get tax slabs            |
| POST   | /api/tax-slabs             | Add tax slab             |
| GET    | /api/payroll               | Get payroll records      |
| POST   | /api/payroll               | Generate payroll         |
| GET    | /api/stats                 | Dashboard statistics     |

---

## SALARY AUTO-CALCULATION (MySQL Trigger)
When payroll is generated, the MySQL trigger `calculate_salary_final` automatically:
1. Fetches basic salary + HRA + DA + Other Allowances
2. Calculates per-day rate = basic / days in month
3. Counts Present + Leave days and Half-days from Attendance
4. Adds Overtime pay = hours × (per_day / 8)
5. Fetches Performance score → applies bonus (>90=₹6000, 75-90=₹4000, 60-74=₹2000)
6. Looks up tax slab and applies tax percentage
7. Calculates Net Salary = Total Earnings - Tax - Deductions
