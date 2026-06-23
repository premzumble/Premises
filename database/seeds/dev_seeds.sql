-- Development Seeds for Premises (PostgreSQL)
-- Version: 1.0.0
-- Description: Inserts realistic seed data for development testing, using static UUIDs.

BEGIN;

-- Clear any existing seed data (optional, run in clean environments)
TRUNCATE TABLE policy_change_history, device_change_requests, faculty_registration_requests, 
               audit_logs, notifications, reason_requests, location_events, attendance_records, 
               attendance_policies, geofences, devices, faculty, admins, departments, 
               organization_settings, organizations CASCADE;

-- =========================================================================
-- 1. ORGANIZATIONS
-- =========================================================================
INSERT INTO organizations (id, name, organization_code, type, domain, logo_url, website, address, contact_number, status)
VALUES 
    ('a0e0a0e0-0000-0000-0000-000000000001', 'Stanford University', 'STANFORD', 'UNIVERSITY', 'stanford.edu', 'https://logo.stanford.edu', 'https://stanford.edu', '450 Serra Mall, Stanford, CA 94305', '+16507232300', 'ACTIVE'),
    ('b0e0b0e0-0000-0000-0000-000000000001', 'Massachusetts Institute of Technology', 'MIT', 'UNIVERSITY', 'mit.edu', 'https://logo.mit.edu', 'https://mit.edu', '77 Massachusetts Ave, Cambridge, MA 02139', '+16172531000', 'ACTIVE');

-- =========================================================================
-- 2. ORGANIZATION SETTINGS
-- =========================================================================
INSERT INTO organization_settings (id, organization_id, faculty_registration_mode, allow_external_emails)
VALUES 
    ('a0e0a0e0-1111-0000-0000-000000000001', 'a0e0a0e0-0000-0000-0000-000000000001', 'ADMIN_APPROVAL', FALSE),
    ('b0e0b0e0-1111-0000-0000-000000000001', 'b0e0b0e0-0000-0000-0000-000000000001', 'AUTO_APPROVE', TRUE);

-- =========================================================================
-- 3. DEPARTMENTS
-- =========================================================================
INSERT INTO departments (id, organization_id, name, description, is_active)
VALUES 
    ('a1d1a1d1-0000-0000-0000-000000000001', 'a0e0a0e0-0000-0000-0000-000000000001', 'Computer Science', 'Department of Computer Science at Stanford', TRUE),
    ('a2d2a2d2-0000-0000-0000-000000000001', 'a0e0a0e0-0000-0000-0000-000000000001', 'Electrical Engineering', 'Department of Electrical Engineering at Stanford', TRUE),
    ('b1d1b1d1-0000-0000-0000-000000000001', 'b0e0b0e0-0000-0000-0000-000000000001', 'Physics', 'Department of Physics at MIT', TRUE),
    ('b2d2b2d2-0000-0000-0000-000000000001', 'b0e0b0e0-0000-0000-0000-000000000001', 'Mathematics', 'Department of Mathematics at MIT', TRUE);

-- =========================================================================
-- 4. ADMINS (Password hashes correspond to 'AdminPassword123' hashed with bcrypt)
-- =========================================================================
INSERT INTO admins (id, organization_id, full_name, email, password_hash, status)
VALUES 
    ('a0ad0ad0-0000-0000-0000-000000000001', 'a0e0a0e0-0000-0000-0000-000000000001', 'Alice Stanford Admin', 'admin@stanford.edu', '$2b$12$K12WqC9o29y.Z7o39ZkU3.sT690m2o6Oq3k5O.lG3bH.gM2Z6Zg4W', 'ACTIVE'),
    ('b0ad0ad0-0000-0000-0000-000000000001', 'b0e0b0e0-0000-0000-0000-000000000001', 'Bob MIT Admin', 'admin@mit.edu', '$2b$12$K12WqC9o29y.Z7o39ZkU3.sT690m2o6Oq3k5O.lG3bH.gM2Z6Zg4W', 'ACTIVE');

-- =========================================================================
-- 5. FACULTY (Password hashes correspond to 'FacultyPassword123')
-- =========================================================================
INSERT INTO faculty (id, organization_id, department_id, full_name, email, password_hash, status, registered_at)
VALUES 
    ('f1ac1ac1-0000-0000-0000-000000000001', 'a0e0a0e0-0000-0000-0000-000000000001', 'a1d1a1d1-0000-0000-0000-000000000001', 'Dr. John Hennessy', 'jhennessy@stanford.edu', '$2b$12$R.S1WqC9o29y.Z7o39ZkU3.sT690m2o6Oq3k5O.lG3bH.gM2Z6Zg4W', 'ACTIVE', '2026-01-15T09:00:00Z'),
    ('f2ac2ac2-0000-0000-0000-000000000001', 'a0e0a0e0-0000-0000-0000-000000000001', 'a1d1a1d1-0000-0000-0000-000000000001', 'Dr. Fei-Fei Li', 'feifeili@stanford.edu', '$2b$12$R.S1WqC9o29y.Z7o39ZkU3.sT690m2o6Oq3k5O.lG3bH.gM2Z6Zg4W', 'PENDING_APPROVAL', NULL),
    ('f3ac3ac3-0000-0000-0000-000000000001', 'b0e0b0e0-0000-0000-0000-000000000001', 'b1d1b1d1-0000-0000-0000-000000000001', 'Dr. Walter Lewin', 'wlewin@mit.edu', '$2b$12$R.S1WqC9o29y.Z7o39ZkU3.sT690m2o6Oq3k5O.lG3bH.gM2Z6Zg4W', 'ACTIVE', '2026-02-10T10:00:00Z');

-- =========================================================================
-- 6. DEVICES
-- =========================================================================
INSERT INTO devices (id, organization_id, faculty_id, device_identifier, device_model, platform, is_active, registered_at)
VALUES 
    -- John Hennessy's active device
    ('d1e1d1e1-0000-0000-0000-000000000001', 'a0e0a0e0-0000-0000-0000-000000000001', 'f1ac1ac1-0000-0000-0000-000000000001', 'uuid-iphone-john-1234', 'iPhone 15 Pro', 'IOS', TRUE, '2026-01-15T09:15:00Z'),
    -- John Hennessy's historical inactive device
    ('d1e1d1e1-9999-0000-0000-000000000001', 'a0e0a0e0-0000-0000-0000-000000000001', 'f1ac1ac1-0000-0000-0000-000000000001', 'uuid-iphone-john-old', 'iPhone 13 mini', 'IOS', FALSE, '2026-01-15T09:00:00Z'),
    -- Walter Lewin's active device
    ('d3e3d3e3-0000-0000-0000-000000000001', 'b0e0b0e0-0000-0000-0000-000000000001', 'f3ac3ac3-0000-0000-0000-000000000001', 'uuid-pixel-walter-5678', 'Google Pixel 8', 'ANDROID', TRUE, '2026-02-10T10:05:00Z');

-- =========================================================================
-- 7. GEOFENCES
-- =========================================================================
INSERT INTO geofences (id, organization_id, name, latitude, longitude, radius_meters, is_active)
VALUES 
    -- Stanford Main Quad Geofence
    ('g1e1g1e1-0000-0000-0000-000000000001', 'a0e0a0e0-0000-0000-0000-000000000001', 'Stanford Main Quad', 37.4275, -122.1697, 500.0, TRUE),
    -- MIT Great Dome Geofence
    ('g2e2g2e2-0000-0000-0000-000000000001', 'b0e0b0e0-0000-0000-0000-000000000001', 'MIT Great Dome', 42.3601, -71.0942, 400.0, TRUE);

-- =========================================================================
-- 8. ATTENDANCE POLICIES
-- =========================================================================
INSERT INTO attendance_policies (id, organization_id, allowed_outside_minutes, reminder_1_minutes, reminder_2_minutes, reminder_3_minutes, evaluation_minutes, start_time, end_time, half_day_cutoff_time, absent_cutoff_time)
VALUES 
    ('p0a0p0a0-0000-0000-0000-000000000001', 'a0e0a0e0-0000-0000-0000-000000000001', 30, 5, 15, 25, 15, '09:00:00', '17:00:00', '13:00:00', '15:00:00'),
    ('p0b0p0b0-0000-0000-0000-000000000001', 'b0e0b0e0-0000-0000-0000-000000000001', 15, 5, 10, 0, 10, '08:30:00', '16:30:00', '12:30:00', '14:30:00');

-- =========================================================================
-- 9. ATTENDANCE RECORDS (Sample record for Dr. John Hennessy on June 19, 2026)
-- =========================================================================
INSERT INTO attendance_records (id, organization_id, faculty_id, attendance_date, first_entry_time, last_exit_time, status, total_inside_minutes, total_outside_minutes)
VALUES 
    ('r1e1r1e1-0000-0000-0000-000000000001', 'a0e0a0e0-0000-0000-0000-000000000001', 'f1ac1ac1-0000-0000-0000-000000000001', '2026-06-19', '2026-06-19T08:55:00Z', '2026-06-19T17:05:00Z', 'PRESENT', 460, 30);

-- =========================================================================
-- 10. LOCATION EVENTS
-- =========================================================================
INSERT INTO location_events (id, organization_id, faculty_id, attendance_record_id, event_type, latitude, longitude, event_time)
VALUES 
    -- John Hennessy arrives at Stanford Quad
    ('e1e1e1e1-0000-0000-0000-000000000001', 'a0e0a0e0-0000-0000-0000-000000000001', 'f1ac1ac1-0000-0000-0000-000000000001', 'r1e1r1e1-0000-0000-0000-000000000001', 'ENTER_CAMPUS', 37.4276, -122.1698, '2026-06-19T08:55:00Z'),
    -- John Hennessy leaves campus for lunch
    ('e1e1e1e1-0000-0000-0000-000000000002', 'a0e0a0e0-0000-0000-0000-000000000001', 'f1ac1ac1-0000-0000-0000-000000000001', 'r1e1r1e1-0000-0000-0000-000000000001', 'EXIT_CAMPUS', 37.4320, -122.1650, '2026-06-19T12:00:00Z'),
    -- John Hennessy returns from lunch
    ('e1e1e1e1-0000-0000-0000-000000000003', 'a0e0a0e0-0000-0000-0000-000000000001', 'f1ac1ac1-0000-0000-0000-000000000001', 'r1e1r1e1-0000-0000-0000-000000000001', 'RETURN_CAMPUS', 37.4274, -122.1695, '2026-06-19T12:30:00Z'),
    -- John Hennessy leaves for the day
    ('e1e1e1e1-0000-0000-0000-000000000004', 'a0e0a0e0-0000-0000-0000-000000000001', 'f1ac1ac1-0000-0000-0000-000000000001', 'r1e1r1e1-0000-0000-0000-000000000001', 'EXIT_CAMPUS', 37.4350, -122.1600, '2026-06-19T17:05:00Z');

-- =========================================================================
-- 11. REASON REQUESTS
-- =========================================================================
INSERT INTO reason_requests (id, organization_id, faculty_id, attendance_record_id, reason_type, notes, submitted_latitude, submitted_longitude, status, reviewed_by, reviewed_at)
VALUES 
    ('q1e1q1e1-0000-0000-0000-000000000001', 'a0e0a0e0-0000-0000-0000-000000000001', 'f1ac1ac1-0000-0000-0000-000000000001', 'r1e1r1e1-0000-0000-0000-000000000001', 'OUTSIDE_GEOFENCE', 'Had to meet research fellows at external site near town center.', 37.4325, -122.1648, 'APPROVED', 'a0ad0ad0-0000-0000-0000-000000000001', '2026-06-19T14:00:00Z');

-- =========================================================================
-- 12. NOTIFICATIONS
-- =========================================================================
INSERT INTO notifications (id, organization_id, faculty_id, type, title, message, status, sent_at, read_at)
VALUES 
    ('n1e1n1e1-0000-0000-0000-000000000001', 'a0e0a0e0-0000-0000-0000-000000000001', 'f1ac1ac1-0000-0000-0000-000000000001', 'EXIT_ALERT', 'Geofence Exit Detected', 'You have left the Stanford Main Quad. Please return or submit an explanation if you remain outside for over 30 minutes.', 'READ', '2026-06-19T12:05:00Z', '2026-06-19T12:07:00Z'),
    ('n1e1n1e1-0000-0000-0000-000000000002', 'a0e0a0e0-0000-0000-0000-000000000001', 'f1ac1ac1-0000-0000-0000-000000000001', 'REMINDER_1', 'Out-of-Geofence Reminder', 'Reminder: You have been outside the geofence for 5 minutes.', 'SENT', '2026-06-19T12:05:00Z', NULL);

-- =========================================================================
-- 13. AUDIT LOGS
-- =========================================================================
INSERT INTO audit_logs (id, organization_id, actor_type, actor_id, action, entity_type, entity_id, old_value, new_value)
VALUES 
    ('l1e1l1e1-0000-0000-0000-000000000001', 'a0e0a0e0-0000-0000-0000-000000000001', 'ADMIN', 'a0ad0ad0-0000-0000-0000-000000000001', 'APPROVE_REASON_REQUEST', 'REASON_REQUEST', 'q1e1q1e1-0000-0000-0000-000000000001', '{"status": "PENDING"}'::jsonb, '{"status": "APPROVED"}'::jsonb),
    ('l1e1l1e1-0000-0000-0000-000000000002', 'a0e0a0e0-0000-0000-0000-000000000001', 'SYSTEM', NULL, 'AUTO_RECORD_DAILY_ABSENCE', 'ATTENDANCE_RECORD', NULL, NULL, '{"status": "ABSENT", "notes": "No check-in detected by end-of-day"}'::jsonb);

-- =========================================================================
-- 14. FACULTY REGISTRATION REQUESTS
-- =========================================================================
INSERT INTO faculty_registration_requests (id, organization_id, faculty_id, status, reviewed_by, reviewed_at)
VALUES 
    ('k1e1k1e1-0000-0000-0000-000000000001', 'a0e0a0e0-0000-0000-0000-000000000001', 'f2ac2ac2-0000-0000-0000-000000000001', 'PENDING', NULL, NULL);

-- =========================================================================
-- 15. DEVICE CHANGE REQUESTS
-- =========================================================================
INSERT INTO device_change_requests (id, organization_id, faculty_id, old_device_id, new_device_identifier, new_device_model, status, reviewed_by, reviewed_at)
VALUES 
    ('c1e1c1e1-0000-0000-0000-000000000001', 'a0e0a0e0-0000-0000-0000-000000000001', 'f1ac1ac1-0000-0000-0000-000000000001', 'd1e1d1e1-9999-0000-0000-000000000001', 'uuid-iphone-john-1234', 'iPhone 15 Pro', 'APPROVED', 'a0ad0ad0-0000-0000-0000-000000000001', '2026-01-15T09:15:00Z');

-- =========================================================================
-- 16. POLICY CHANGE HISTORY
-- =========================================================================
INSERT INTO policy_change_history (id, organization_id, policy_id, changed_by, field_name, old_value, new_value)
VALUES 
    ('h1e1h1e1-0000-0000-0000-000000000001', 'a0e0a0e0-0000-0000-0000-000000000001', 'p0a0p0a0-0000-0000-0000-000000000001', 'a0ad0ad0-0000-0000-0000-000000000001', 'allowed_outside_minutes', '15', '30');

COMMIT;
