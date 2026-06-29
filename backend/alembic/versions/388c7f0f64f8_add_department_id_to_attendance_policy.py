"""add_department_id_to_attendance_policy

Revision ID: 388c7f0f64f8
Revises: e2b996c1c7ea
Create Date: 2026-06-28 22:23:44.647342

"""
from typing import Sequence, Union
import uuid
from datetime import datetime

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '388c7f0f64f8'
down_revision: Union[str, Sequence[str], None] = 'e2b996c1c7ea'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema and perform safe data migration."""
    # 1. Add department_id column
    op.add_column('attendance_policies', sa.Column('department_id', sa.Uuid(), nullable=True))

    # 2. Update constraints
    # Remove the old unique constraint on organization_id (one per org)
    op.drop_constraint(op.f('attendance_policies_organization_id_key'), 'attendance_policies', type_='unique')
    # Add new composite unique constraint (one per org OR one per org+dept)
    op.create_unique_constraint('uniq_org_dept_policy', 'attendance_policies', ['organization_id', 'department_id'])
    op.create_foreign_key(None, 'attendance_policies', 'departments', ['department_id'], ['id'], ondelete='CASCADE')

    # 3. Data Migration: Copy organization-wide policies to every existing department
    connection = op.get_bind()

    # Fetch all organizations and their default policies
    org_policies = connection.execute(
        sa.text("SELECT * FROM attendance_policies WHERE department_id IS NULL")
    ).fetchall()

    # Convert list of rows to a map for easy lookup
    policy_map = {p.organization_id: p for p in org_policies}

    # Fetch all active departments
    departments = connection.execute(
        sa.text("SELECT id, organization_id FROM departments WHERE is_active = true")
    ).fetchall()

    # Create copies for each department
    for dept in departments:
        if dept.organization_id in policy_map:
            p = policy_map[dept.organization_id]

            # Check if a policy already exists for this department
            existing = connection.execute(
                sa.text("SELECT id FROM attendance_policies WHERE organization_id = :org_id AND department_id = :dept_id"),
                {"org_id": dept.organization_id, "dept_id": dept.id}
            ).fetchone()

            if not existing:
                now = datetime.utcnow()
                # Insert new policy record copying from organization default
                connection.execute(
                    sa.text("""
                        INSERT INTO attendance_policies (
                            id, organization_id, department_id,
                            allowed_outside_minutes, reminder_1_minutes, reminder_2_minutes, reminder_3_minutes,
                            evaluation_minutes, start_time, end_time, half_day_cutoff_time, absent_cutoff_time,
                            created_at, updated_at
                        ) VALUES (
                            :id, :org_id, :dept_id,
                            :allowed, :r1, :r2, :r3,
                            :eval, :start, :end, :half, :absent,
                            :created, :updated
                        )
                    """),
                    {
                        "id": uuid.uuid4(),
                        "org_id": dept.organization_id,
                        "dept_id": dept.id,
                        "allowed": p.allowed_outside_minutes,
                        "r1": p.reminder_1_minutes,
                        "r2": p.reminder_2_minutes,
                        "r3": p.reminder_3_minutes,
                        "eval": p.evaluation_minutes,
                        "start": p.start_time,
                        "end": p.end_time,
                        "half": p.half_day_cutoff_time,
                        "absent": p.absent_cutoff_time,
                        "created": now,
                        "updated": now
                    }
                )


def downgrade() -> None:
    """Downgrade schema."""
    # 1. Delete all department-specific policies
    connection = op.get_bind()
    connection.execute(sa.text("DELETE FROM attendance_policies WHERE department_id IS NOT NULL"))

    # 2. Revert schema changes
    op.drop_constraint(None, 'attendance_policies', type_='foreignkey')
    op.drop_constraint('uniq_org_dept_policy', 'attendance_policies', type_='unique')
    op.create_unique_constraint(op.f('attendance_policies_organization_id_key'), 'attendance_policies', ['organization_id'], postgresql_nulls_not_distinct=False)
    op.drop_column('attendance_policies', 'department_id')
