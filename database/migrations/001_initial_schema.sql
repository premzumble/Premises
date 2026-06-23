-- Migration: 001_initial_schema
-- Created: 2026-06-20
-- Description: Create all core tables, constraints, and indexes for multi-tenant architecture.

BEGIN;

-- Enable pgcrypto extension for UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =========================================================================
-- 1. ORGANIZATIONS
-- =========================================================================
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    organization_code VARCHAR(50) NOT NULL UNIQUE,
    type VARCHAR(50) NOT NULL,
    domain TEXT UNIQUE,
    logo_url TEXT,
    website TEXT,
    address TEXT,
    contact_number VARCHAR(30),
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED', 'DEACTIVATED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uniq_org_id UNIQUE (id)
);

-- =========================================================================
-- 2. ORGANIZATION SETTINGS
-- =========================================================================
CREATE TABLE organization_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL UNIQUE REFERENCES organizations(id) ON DELETE CASCADE,
    faculty_registration_mode VARCHAR(20) NOT NULL DEFAULT 'ADMIN_APPROVAL' CHECK (faculty_registration_mode IN ('AUTO_APPROVE', 'ADMIN_APPROVAL')),
    allow_external_emails BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================================
-- 3. DEPARTMENTS
-- =========================================================================
CREATE TABLE departments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uniq_org_dept_name UNIQUE (organization_id, name),
    CONSTRAINT uniq_org_dept_id UNIQUE (organization_id, id)
);

-- =========================================================================
-- 4. ADMINS
-- =========================================================================
CREATE TABLE admins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uniq_org_admin_id UNIQUE (organization_id, id)
);

-- =========================================================================
-- 5. FACULTY
-- =========================================================================
CREATE TABLE faculty (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    department_id UUID,
    full_name TEXT NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    status VARCHAR(255) NOT NULL DEFAULT 'PENDING_APPROVAL' CHECK (status IN ('ACTIVE', 'INACTIVE', 'PENDING_APPROVAL')),
    registered_at TIMESTAMPTZ,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_faculty_department FOREIGN KEY (organization_id, department_id) REFERENCES departments(organization_id, id) ON DELETE SET NULL,
    CONSTRAINT uniq_org_faculty_id UNIQUE (organization_id, id)
);

-- =========================================================================
-- 6. DEVICES
-- =========================================================================
CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    faculty_id UUID NOT NULL,
    device_identifier TEXT NOT NULL,
    device_model TEXT,
    platform VARCHAR(10) NOT NULL CHECK (platform IN ('ANDROID', 'IOS')),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    registered_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_device_faculty FOREIGN KEY (organization_id, faculty_id) REFERENCES faculty(organization_id, id) ON DELETE CASCADE,
    CONSTRAINT uniq_org_device_id UNIQUE (organization_id, id)
);

-- Enforce only one active device per faculty member
CREATE UNIQUE INDEX idx_devices_single_active_faculty ON devices(faculty_id) WHERE (is_active = TRUE);

-- =========================================================================
-- 7. GEOFENCES
-- =========================================================================
CREATE TABLE geofences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    radius_meters DOUBLE PRECISION NOT NULL CHECK (radius_meters > 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================================
-- 8. ATTENDANCE POLICIES
-- =========================================================================
CREATE TABLE attendance_policies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL UNIQUE REFERENCES organizations(id) ON DELETE CASCADE,
    allowed_outside_minutes INTEGER NOT NULL DEFAULT 0 CHECK (allowed_outside_minutes >= 0),
    reminder_1_minutes INTEGER NOT NULL DEFAULT 0,
    reminder_2_minutes INTEGER NOT NULL DEFAULT 0,
    reminder_3_minutes INTEGER NOT NULL DEFAULT 0,
    evaluation_minutes INTEGER NOT NULL DEFAULT 15 CHECK (evaluation_minutes > 0),
    start_time TIME NOT NULL DEFAULT '09:00:00',
    end_time TIME NOT NULL DEFAULT '17:00:00',
    half_day_cutoff_time TIME NOT NULL,
    absent_cutoff_time TIME NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uniq_org_policy_id UNIQUE (organization_id, id)
);

-- =========================================================================
-- 9. ATTENDANCE RECORDS
-- =========================================================================
CREATE TABLE attendance_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    faculty_id UUID NOT NULL,
    attendance_date DATE NOT NULL,
    first_entry_time TIMESTAMPTZ,
    last_exit_time TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL DEFAULT 'ABSENT' CHECK (status IN ('PRESENT', 'HALF_DAY', 'ABSENT')),
    total_inside_minutes INTEGER NOT NULL DEFAULT 0 CHECK (total_inside_minutes >= 0),
    total_outside_minutes INTEGER NOT NULL DEFAULT 0 CHECK (total_outside_minutes >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_record_faculty FOREIGN KEY (organization_id, faculty_id) REFERENCES faculty(organization_id, id) ON DELETE CASCADE,
    CONSTRAINT uniq_faculty_attendance_date UNIQUE (faculty_id, attendance_date),
    CONSTRAINT uniq_org_record_id UNIQUE (organization_id, id)
);

-- =========================================================================
-- 10. LOCATION EVENTS
-- =========================================================================
CREATE TABLE location_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    faculty_id UUID NOT NULL,
    attendance_record_id UUID REFERENCES attendance_records(id) ON DELETE CASCADE,
    event_type VARCHAR(20) NOT NULL CHECK (event_type IN ('ENTER_CAMPUS', 'EXIT_CAMPUS', 'RETURN_CAMPUS')),
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    event_time TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_event_faculty FOREIGN KEY (organization_id, faculty_id) REFERENCES faculty(organization_id, id) ON DELETE CASCADE,
    CONSTRAINT fk_event_record FOREIGN KEY (organization_id, attendance_record_id) REFERENCES attendance_records(organization_id, id) ON DELETE CASCADE
);

-- =========================================================================
-- 11. REASON REQUESTS
-- =========================================================================
CREATE TABLE reason_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    faculty_id UUID NOT NULL,
    attendance_record_id UUID REFERENCES attendance_records(id) ON DELETE CASCADE,
    reason_type VARCHAR(50) NOT NULL,
    notes TEXT,
    submitted_latitude DOUBLE PRECISION,
    submitted_longitude DOUBLE PRECISION,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    reviewed_by UUID,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_reason_faculty FOREIGN KEY (organization_id, faculty_id) REFERENCES faculty(organization_id, id) ON DELETE CASCADE,
    CONSTRAINT fk_reason_record FOREIGN KEY (organization_id, attendance_record_id) REFERENCES attendance_records(organization_id, id) ON DELETE CASCADE,
    CONSTRAINT fk_reason_reviewer FOREIGN KEY (organization_id, reviewed_by) REFERENCES admins(organization_id, id) ON DELETE SET NULL
);

-- =========================================================================
-- 12. NOTIFICATIONS
-- =========================================================================
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    faculty_id UUID NOT NULL,
    type VARCHAR(30) NOT NULL CHECK (type IN ('EXIT_ALERT', 'REMINDER_1', 'REMINDER_2', 'REMINDER_3', 'DEVICE_ALERT')),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    read_at TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL DEFAULT 'SENT' CHECK (status IN ('SENT', 'READ', 'FAILED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_notification_faculty FOREIGN KEY (organization_id, faculty_id) REFERENCES faculty(organization_id, id) ON DELETE CASCADE
);

-- =========================================================================
-- 13. AUDIT LOGS
-- =========================================================================
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    actor_type VARCHAR(20) NOT NULL CHECK (actor_type IN ('ADMIN', 'FACULTY', 'SYSTEM')),
    actor_id UUID,
    action TEXT NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_id UUID,
    old_value JSONB,
    new_value JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =========================================================================
-- 14. FACULTY REGISTRATION REQUESTS
-- =========================================================================
CREATE TABLE faculty_registration_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    faculty_id UUID NOT NULL REFERENCES faculty(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    reviewed_by UUID,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_reg_faculty FOREIGN KEY (organization_id, faculty_id) REFERENCES faculty(organization_id, id) ON DELETE CASCADE,
    CONSTRAINT fk_reg_reviewer FOREIGN KEY (organization_id, reviewed_by) REFERENCES admins(organization_id, id) ON DELETE SET NULL
);

-- =========================================================================
-- 15. DEVICE CHANGE REQUESTS
-- =========================================================================
CREATE TABLE device_change_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    faculty_id UUID NOT NULL,
    old_device_id UUID,
    new_device_identifier TEXT NOT NULL,
    new_device_model TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    reviewed_by UUID,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_dev_faculty FOREIGN KEY (organization_id, faculty_id) REFERENCES faculty(organization_id, id) ON DELETE CASCADE,
    CONSTRAINT fk_dev_old_device FOREIGN KEY (organization_id, old_device_id) REFERENCES devices(organization_id, id) ON DELETE SET NULL,
    CONSTRAINT fk_dev_reviewer FOREIGN KEY (organization_id, reviewed_by) REFERENCES admins(organization_id, id) ON DELETE SET NULL
);

-- =========================================================================
-- 16. POLICY CHANGE HISTORY
-- =========================================================================
CREATE TABLE policy_change_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    policy_id UUID NOT NULL,
    changed_by UUID,
    field_name TEXT NOT NULL,
    old_value TEXT,
    new_value TEXT,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_hist_policy FOREIGN KEY (organization_id, policy_id) REFERENCES attendance_policies(organization_id, id) ON DELETE CASCADE,
    CONSTRAINT fk_hist_admin FOREIGN KEY (organization_id, changed_by) REFERENCES admins(organization_id, id) ON DELETE SET NULL
);

-- =========================================================================
-- INDEXES FOR MULTI-TENANT HIGH-CONCURRENCY PERFORMANCE
-- =========================================================================

-- Organization-specific filtering
CREATE INDEX idx_org_settings_org ON organization_settings(organization_id);
CREATE INDEX idx_departments_org ON departments(organization_id);
CREATE INDEX idx_admins_org ON admins(organization_id);
CREATE INDEX idx_faculty_org ON faculty(organization_id, status);
CREATE INDEX idx_devices_org ON devices(organization_id);
CREATE INDEX idx_geofences_org ON geofences(organization_id);
CREATE INDEX idx_attendance_records_org ON attendance_records(organization_id, attendance_date);
CREATE INDEX idx_location_events_org ON location_events(organization_id);
CREATE INDEX idx_reason_requests_org ON reason_requests(organization_id, status);
CREATE INDEX idx_notifications_org ON notifications(organization_id, faculty_id);
CREATE INDEX idx_audit_logs_org ON audit_logs(organization_id, created_at DESC);
CREATE INDEX idx_faculty_reg_requests_org ON faculty_registration_requests(organization_id, status);
CREATE INDEX idx_device_change_requests_org ON device_change_requests(organization_id, status);
CREATE INDEX idx_policy_history_org ON policy_change_history(organization_id);

-- Lookup-specific queries
CREATE INDEX idx_faculty_email ON faculty(email);
CREATE INDEX idx_admins_email ON admins(email);
CREATE INDEX idx_devices_faculty ON devices(faculty_id);
CREATE INDEX idx_attendance_records_faculty_date ON attendance_records(faculty_id, attendance_date DESC);
CREATE INDEX idx_location_events_record ON location_events(attendance_record_id, event_time ASC);
CREATE INDEX idx_reason_requests_record ON reason_requests(attendance_record_id);
CREATE INDEX idx_notifications_faculty ON notifications(faculty_id, status, created_at DESC);

COMMIT;
