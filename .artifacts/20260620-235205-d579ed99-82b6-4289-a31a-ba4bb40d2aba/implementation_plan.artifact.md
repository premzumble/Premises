# Implementation Plan - Department-wise Working Hours

Enable each department within an organization to have its own independent working schedule and attendance policies.

## User Review Required

- **Automatic Inheritance**: Faculty will automatically use the schedule of their assigned department. If a department doesn't have a specific schedule set (unlikely after migration), they fallback to the organization's default.
- **Migration Strategy**: Existing organization-wide policies will be copied to every existing department during migration to ensure no disruption.

## Proposed Changes

### Database & Models

#### [geofence.py](file:///E:/Premises/premises/backend/app/models/geofence.py)
- Modify `AttendancePolicy`:
    - Remove `unique=True` from `organization_id`.
    - Add `department_id: Mapped[Optional[uuid.UUID]] = mapped_column(Uuid, ForeignKey("departments.id", ondelete="CASCADE"), nullable=True)`.
    - Add `UniqueConstraint("organization_id", "department_id", name="uniq_org_dept_policy")`.

#### [organization.py](file:///E:/Premises/premises/backend/app/models/organization.py)
- Update `Department` model to include a relationship to `AttendancePolicy`.

---

### Backend Services & Repositories

#### [geofence_repo.py](file:///E:/Premises/premises/backend/app/repositories/geofence_repo.py)
- Add `get_policy_by_dept(org_id, dept_id)` which looks for a department-specific policy or falls back to the org default.

#### [attendance_service.py](file:///E:/Premises/premises/backend/app/services/attendance_service.py)
- Update `register_location_event`: Look up the faculty's department policy instead of the organization's.
- Update `close_all_expired_records`: Iterate over records and resolve the correct policy for each faculty's department.
- Update `evaluate_and_close_record`: Accept policy as an argument (already does, but ensure caller passes correct one).

#### [faculty_service.py](file:///E:/Premises/premises/backend/app/services/faculty_service.py)
- Update `get_dashboard_summary`: Fetch and return the department-specific timings for the faculty's dashboard.

---

### API & Schemas

#### [geofence.py (schemas)](file:///E:/Premises/premises/backend/app/schemas/geofence.py)
- Update `AttendancePolicyResponse` and `AttendancePolicyUpdate` to include `department_id`.

#### [settings.py (api)](file:///E:/Premises/premises/backend/app/api/settings.py)
- Update `get_policy` and `update_policy` to accept an optional `department_id` query parameter.

---

### Frontend (Admin Settings)

#### [settings_screen.dart](file:///E:/Premises/premises/lib/features/settings/screens/settings_screen.dart)
- Update "Working Hours" and "Attendance Policy" tabs:
    - Add a Department selector dropdown at the top.
    - Switching departments reloads the policy settings for that specific department.
    - Saving updates only the selected department's policy.

---

## Verification Plan

### Automated Tests
- `pytest backend/tests/test_department_policy.py`: New test suite to verify:
    - On-time/Late check-in for different departments with different schedules.
    - Migration correctness (copying org defaults to departments).
- `flutter analyze`: Ensure no frontend breakages.

### Manual Verification
1. **Migration**: Run `alembic upgrade head` and verify `attendance_policies` table is populated for all existing departments.
2. **Admin Config**:
    - Set Dept A to 09:00 - 17:00.
    - Set Dept B to 10:00 - 18:00.
    - Verify both persist independently.
3. **Faculty Workflow**:
    - Log in as Faculty in Dept A; verify dashboard shows 09:00 - 17:00.
    - Log in as Faculty in Dept B; verify dashboard shows 10:00 - 18:00.
    - Perform a check-in at 09:30; Verify Dept A is marked LATE/PRESENT and Dept B is still within grace/on-time (if applicable).
