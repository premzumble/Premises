# Premises PostgreSQL Database Architecture

This directory houses the database design, schema definition, migrations, and seeding utilities for the Premises multi-tenant attendance management system.

## Project Structure

```text
premises/database/
├── schema/
│   └── schema.sql          # Source-of-truth baseline schema definition
├── migrations/
│   └── 001_initial_schema.sql # Baseline migration file
├── seeds/
│   └── dev_seeds.sql       # Seed data for development testing
└── README.md               # Setup and administration guide
```

---

## 1. System Requirements

* **PostgreSQL Version**: PostgreSQL 13 or higher (PostgreSQL 15+ is recommended for optimal JSONB processing and indexing performance).
* **Extensions Required**:
  - `pgcrypto`: Required for generating cryptographic UUIDs via the `gen_random_uuid()` function.

---

## 2. Setting Up the Database Locally

Follow these steps to initialize the database:

### Step 1: Create the Database
Login to your PostgreSQL CLI (`psql`) as superuser and run:

```sql
CREATE DATABASE premises;
```

Alternatively, from your shell command line:
```bash
createdb -U postgres premises
```

### Step 2: Run the Migrations
Apply the initial schema using the SQL migration file. Navigate to this directory (`premises/database`) and execute:

```bash
psql -U postgres -d premises -f migrations/001_initial_schema.sql
```

This script creates the database tables, defines foreign keys (enforcing multi-tenant integrity), registers check constraints, and sets up index mappings.

### Step 3: Seed Development Data (Optional)
To load mock data including pre-configured organizations, policies, departments, admins, faculty, and sample attendance logs for testing:

```bash
psql -U postgres -d premises -f seeds/dev_seeds.sql
```

---

## 3. Testing Schema Integrity & Constraints

### Test A: Single Active Device Rule
The schema strictly enforces that a faculty member can have at most **one active device** at any time.

Attempt to insert a second active device for the same faculty member:
```sql
-- This query will FAIL due to unique index idx_devices_single_active_faculty
INSERT INTO devices (organization_id, faculty_id, device_identifier, device_model, platform, is_active)
VALUES (
    'a0e0a0e0-0000-0000-0000-000000000001', 
    'f1ac1ac1-0000-0000-0000-000000000001', 
    'uuid-iphone-duplicate-test', 
    'iPhone 15 Pro Max', 
    'IOS', 
    TRUE
);
```

### Test B: Multi-Tenant Department Violation
The schema enforces that a faculty member cannot be assigned to a department owned by another organization.

Attempt to register Stanford faculty under an MIT department:
```sql
-- This query will FAIL due to composite foreign key constraint fk_faculty_department
-- (Stanford org_id 'a0e0...001' != MIT department org_id in 'b1d1...001')
INSERT INTO faculty (organization_id, department_id, full_name, email, password_hash, status)
VALUES (
    'a0e0a0e0-0000-0000-0000-000000000001', 
    'b1d1b1d1-0000-0000-0000-000000000001', -- MIT Physics Dept
    'Dr. Cross Tenant', 
    'ctenant@stanford.edu', 
    'hash', 
    'ACTIVE'
);
```

### Test C: Daily Attendance Record Uniqueness
A faculty member can have only one attendance record per day.

Attempt to create duplicate record:
```sql
-- This query will FAIL due to constraint uniq_faculty_attendance_date
INSERT INTO attendance_records (organization_id, faculty_id, attendance_date, status)
VALUES (
    'a0e0a0e0-0000-0000-0000-000000000001', 
    'f1ac1ac1-0000-0000-0000-000000000001', 
    '2026-06-19', -- John Hennessy's existing date
    'PRESENT'
);
```

---

## 4. Query & Index Tuning Guidelines

This database handles high volumes of geo-tracking data. Use the following index optimizations:
* **Tenant Partition Isolation**: All indexes on multi-tenant tables (e.g., `attendance_records`, `location_events`) include `organization_id` as the leading index column to ensure queries do not scan other tenants' data.
* **Location Events Lookups**: The index `idx_location_events_record` speeds up querying sequential events for active attendance tracking maps:
  ```sql
  SELECT event_type, latitude, longitude, event_time 
  FROM location_events 
  WHERE attendance_record_id = 'r1e1r1e1-0000-0000-0000-000000000001' 
  ORDER BY event_time ASC;
  ```
* **Audit Trail Pagination**: `idx_audit_logs_org` utilizes a composite key `(organization_id, created_at DESC)` to feed real-time admin dashboard feeds without full table scans.
