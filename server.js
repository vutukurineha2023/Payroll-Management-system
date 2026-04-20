const express = require('express');
const mysql = require('mysql2');
const cors = require('cors');
const path = require('path');

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// ── DATABASE CONNECTION ──────────────────────────────────────
const db = mysql.createConnection({
  host: 'localhost',
  user: 'root',
  password: 'Neha@221014',
  database: 'Payroll'
});

db.connect(err => {
  if (err) { console.error('DB connection failed:', err.message); return; }
  console.log('✅ Connected to MySQL database: Payroll');
});

// ── AUTH ─────────────────────────────────────────────────────
app.post('/api/login', (req, res) => {
  const { username, password } = req.body;
  const sql = `SELECT u.user_id, u.username, u.role, e.employee_id, e.name, e.designation, e.dept_id
               FROM User u
               LEFT JOIN Employee e ON u.user_id = e.user_id
               WHERE u.username = ? AND u.password = ?`;
  db.query(sql, [username, password], (err, results) => {
    if (err) return res.status(500).json({ error: err.message });
    if (results.length === 0) return res.status(401).json({ error: 'Invalid credentials' });
    res.json({ success: true, user: results[0] });
  });
});

// ── DEPARTMENTS ───────────────────────────────────────────────
app.get('/api/departments', (req, res) => {
  db.query('SELECT * FROM Department', (err, results) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json(results);
  });
});

// ── EMPLOYEES ─────────────────────────────────────────────────
app.get('/api/employees', (req, res) => {
  const sql = `SELECT e.*, d.dept_name, u.username
               FROM Employee e
               LEFT JOIN Department d ON e.dept_id = d.dept_id
               LEFT JOIN User u ON e.user_id = u.user_id`;
  db.query(sql, (err, results) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json(results);
  });
});

app.get('/api/employees/:id', (req, res) => {
  const sql = `SELECT e.*, d.dept_name, u.username,
               sc.hra, sc.da, sc.other_allowances
               FROM Employee e
               LEFT JOIN Department d ON e.dept_id = d.dept_id
               LEFT JOIN User u ON e.user_id = u.user_id
               LEFT JOIN Salary_Components sc ON e.employee_id = sc.employee_id
               WHERE e.employee_id = ?`;
  db.query(sql, [req.params.id], (err, results) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json(results[0] || {});
  });
});

app.post('/api/employees', (req, res) => {
  const { username, password, name, father_name, email, phone, address, designation, date_of_joining, basic_salary, dept_id, hra, da, other_allowances } = req.body;
  db.query('INSERT INTO User (username, password, role) VALUES (?,?,?)', [username, password, 'employee'], (err, uRes) => {
    if (err) return res.status(500).json({ error: err.message });
    const userId = uRes.insertId;
    db.query('INSERT INTO Employee (user_id,name,father_name,email,phone,address,designation,date_of_joining,basic_salary,dept_id) VALUES (?,?,?,?,?,?,?,?,?,?)',
      [userId, name, father_name, email, phone, address, designation, date_of_joining, basic_salary, dept_id],
      (err2, eRes) => {
        if (err2) return res.status(500).json({ error: err2.message });
        const empId = eRes.insertId;
        db.query('INSERT INTO Salary_Components (employee_id,basic,hra,da,other_allowances) VALUES (?,?,?,?,?)',
          [empId, basic_salary, hra || 0, da || 0, other_allowances || 0], () => {});
        res.json({ success: true, employee_id: empId });
      });
  });
});

// ── ATTENDANCE (ADMIN ONLY) ───────────────────────────────────
app.get('/api/attendance', (req, res) => {
  const { month, year, employee_id } = req.query;
  let sql = `SELECT a.*, e.name FROM Attendance a JOIN Employee e ON a.employee_id = e.employee_id WHERE 1=1`;
  const params = [];
  if (employee_id) { sql += ' AND a.employee_id = ?'; params.push(employee_id); }
  if (month) { sql += ' AND MONTH(a.date) = ?'; params.push(month); }
  if (year) { sql += ' AND YEAR(a.date) = ?'; params.push(year); }
  sql += ' ORDER BY a.date DESC';
  db.query(sql, params, (err, results) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json(results);
  });
});

app.post('/api/attendance', (req, res) => {
  const { employee_id, date, status } = req.body;
  const sql = `INSERT INTO Attendance (employee_id, date, status) VALUES (?,?,?)
               ON DUPLICATE KEY UPDATE status = VALUES(status)`;
  db.query(sql, [employee_id, date, status], (err) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json({ success: true });
  });
});

// ── LEAVE REQUESTS ────────────────────────────────────────────
app.get('/api/leaves', (req, res) => {
  const { employee_id } = req.query;
  let sql = `SELECT lr.*, e.name FROM Leave_Request lr JOIN Employee e ON lr.employee_id = e.employee_id`;
  const params = [];
  if (employee_id) { sql += ' WHERE lr.employee_id = ?'; params.push(employee_id); }
  sql += ' ORDER BY lr.leave_id DESC';
  db.query(sql, params, (err, results) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json(results);
  });
});

// EMPLOYEE applies leave
app.post('/api/leaves', (req, res) => {
  const { employee_id, start_date, end_date, reason } = req.body;
  db.query('INSERT INTO Leave_Request (employee_id, start_date, end_date, reason) VALUES (?,?,?,?)',
    [employee_id, start_date, end_date, reason], (err) => {
      if (err) return res.status(500).json({ error: err.message });
      res.json({ success: true });
    });
});

// ADMIN approves/rejects leave
app.put('/api/leaves/:id', (req, res) => {
  const { status } = req.body;
  db.query('UPDATE Leave_Request SET status = ? WHERE leave_id = ?', [status, req.params.id], (err) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json({ success: true });
  });
});

// ── LEAVE BALANCE ─────────────────────────────────────────────
app.get('/api/leave-balance', (req, res) => {
  const { employee_id, month, year } = req.query;
  let sql = `SELECT lb.*, e.name FROM Leave_Balance lb JOIN Employee e ON lb.employee_id = e.employee_id WHERE 1=1`;
  const params = [];
  if (employee_id) { sql += ' AND lb.employee_id = ?'; params.push(employee_id); }
  if (month) { sql += ' AND lb.month = ?'; params.push(month); }
  if (year) { sql += ' AND lb.year = ?'; params.push(year); }
  db.query(sql, params, (err, results) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json(results);
  });
});

// ── OVERTIME ──────────────────────────────────────────────────
app.get('/api/overtime', (req, res) => {
  const { employee_id, month, year } = req.query;
  let sql = `SELECT o.*, e.name FROM Overtime o JOIN Employee e ON o.employee_id = e.employee_id WHERE 1=1`;
  const params = [];
  if (employee_id) { sql += ' AND o.employee_id = ?'; params.push(employee_id); }
  if (month) { sql += ' AND MONTH(o.date) = ?'; params.push(month); }
  if (year) { sql += ' AND YEAR(o.date) = ?'; params.push(year); }
  sql += ' ORDER BY o.date DESC';
  db.query(sql, params, (err, results) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json(results);
  });
});

app.post('/api/overtime', (req, res) => {
  const { employee_id, date, hours } = req.body;
  db.query('INSERT INTO Overtime (employee_id, date, hours) VALUES (?,?,?)', [employee_id, date, hours], (err) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json({ success: true });
  });
});

// ── SALARY COMPONENTS ─────────────────────────────────────────
app.get('/api/salary-components/:id', (req, res) => {
  db.query('SELECT * FROM Salary_Components WHERE employee_id = ?', [req.params.id], (err, results) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json(results[0] || {});
  });
});

app.post('/api/salary-components', (req, res) => {
  const { employee_id, basic, hra, da, other_allowances } = req.body;
  const sql = `INSERT INTO Salary_Components (employee_id,basic,hra,da,other_allowances) VALUES (?,?,?,?,?)
               ON DUPLICATE KEY UPDATE basic=VALUES(basic),hra=VALUES(hra),da=VALUES(da),other_allowances=VALUES(other_allowances)`;
  db.query(sql, [employee_id, basic, hra, da, other_allowances], (err) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json({ success: true });
  });
});

// ── PERFORMANCE ───────────────────────────────────────────────
app.get('/api/performance', (req, res) => {
  const { employee_id, month, year } = req.query;
  let sql = `SELECT p.*, e.name FROM Performance p JOIN Employee e ON p.employee_id = e.employee_id WHERE 1=1`;
  const params = [];
  if (employee_id) { sql += ' AND p.employee_id = ?'; params.push(employee_id); }
  if (month) { sql += ' AND p.month = ?'; params.push(month); }
  if (year) { sql += ' AND p.year = ?'; params.push(year); }
  db.query(sql, params, (err, results) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json(results);
  });
});

app.post('/api/performance', (req, res) => {
  const { employee_id, month, year, score } = req.body;
  const sql = `INSERT INTO Performance (employee_id,month,year,score) VALUES (?,?,?,?)
               ON DUPLICATE KEY UPDATE score=VALUES(score)`;
  db.query(sql, [employee_id, month, year, score], (err) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json({ success: true });
  });
});

// ── TAX SLABS ─────────────────────────────────────────────────
app.get('/api/tax-slabs', (req, res) => {
  db.query('SELECT * FROM Tax_Slabs ORDER BY min_salary', (err, results) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json(results);
  });
});

app.post('/api/tax-slabs', (req, res) => {
  const { min_salary, max_salary, tax_percent } = req.body;
  db.query('INSERT INTO Tax_Slabs (min_salary,max_salary,tax_percent) VALUES (?,?,?)',
    [min_salary, max_salary, tax_percent], (err) => {
      if (err) return res.status(500).json({ error: err.message });
      res.json({ success: true });
    });
});

// ── PAYROLL ───────────────────────────────────────────────────
app.get('/api/payroll', (req, res) => {
  const { employee_id, month, year } = req.query;
  let sql = `SELECT p.*, e.name, e.designation FROM Payroll p JOIN Employee e ON p.employee_id = e.employee_id WHERE 1=1`;
  const params = [];
  if (employee_id) { sql += ' AND p.employee_id = ?'; params.push(employee_id); }
  if (month) { sql += ' AND p.month = ?'; params.push(month); }
  if (year) { sql += ' AND p.year = ?'; params.push(year); }
  sql += ' ORDER BY p.year DESC, p.month DESC';
  db.query(sql, params, (err, results) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json(results);
  });
});

app.post('/api/payroll', (req, res) => {
  const { employee_id, month, year, bonus, deductions } = req.body;
  const sql = `INSERT INTO Payroll (employee_id,month,year,bonus,deductions) VALUES (?,?,?,?,?)`;
  db.query(sql, [employee_id, month, year, bonus || 0, deductions || 0], (err) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json({ success: true });
  });
});

// ── DASHBOARD STATS ───────────────────────────────────────────
app.get('/api/stats', (req, res) => {
  const today = new Date().toISOString().split('T')[0];
  const month = new Date().getMonth() + 1;
  const year = new Date().getFullYear();
  const stats = {};
  db.query('SELECT COUNT(*) as total FROM Employee', (e, r) => {
    stats.totalEmployees = r[0].total;
    db.query(`SELECT COUNT(*) as present FROM Attendance WHERE date=? AND status='Present'`, [today], (e2, r2) => {
      stats.presentToday = r2[0].present;
      db.query(`SELECT COUNT(*) as pending FROM Leave_Request WHERE status='Pending'`, (e3, r3) => {
        stats.pendingLeaves = r3[0].pending;
        db.query(`SELECT IFNULL(SUM(net_salary),0) as total FROM Payroll WHERE month=? AND year=?`, [month, year], (e4, r4) => {
          stats.totalPayroll = r4[0].total;
          db.query('SELECT COUNT(*) as depts FROM Department', (e5, r5) => {
            stats.departments = r5[0].depts;
            res.json(stats);
          });
        });
      });
    });
  });
});

// ── START SERVER ──────────────────────────────────────────────
const PORT = 3000;
app.listen(PORT, () => {
  console.log(`\n🚀 PayrollPro Server running at http://localhost:${PORT}`);
  console.log(`📂 Open http://localhost:${PORT} in your browser\n`);
});
