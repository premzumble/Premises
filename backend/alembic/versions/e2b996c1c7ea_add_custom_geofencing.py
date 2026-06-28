"""add_custom_geofencing

Revision ID: e2b996c1c7ea
Revises: daf886c1b6ff
Create Date: 2026-06-28 15:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e2b996c1c7ea'
down_revision: Union[str, Sequence[str], None] = 'daf886c1b6ff'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Add geofence_type to geofences
    op.add_column('geofences', sa.Column('geofence_type', sa.String(length=50), nullable=False, server_default='circle'))
    
    # 2. Make latitude, longitude, and radius_meters nullable
    op.alter_column('geofences', 'latitude', existing_type=sa.Double(), nullable=True)
    op.alter_column('geofences', 'longitude', existing_type=sa.Double(), nullable=True)
    op.alter_column('geofences', 'radius_meters', existing_type=sa.Double(), nullable=True)
    
    # 3. Create geofence_vertices table
    op.create_table(
        'geofence_vertices',
        sa.Column('id', sa.Uuid(), nullable=False),
        sa.Column('geofence_id', sa.Uuid(), nullable=False),
        sa.Column('sequence_order', sa.Integer(), nullable=False),
        sa.Column('latitude', sa.Double(), nullable=False),
        sa.Column('longitude', sa.Double(), nullable=False),
        sa.ForeignKeyConstraint(['geofence_id'], ['geofences.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )


def downgrade() -> None:
    # 1. Drop geofence_vertices table
    op.drop_table('geofence_vertices')
    
    # 2. Revert nullability of latitude, longitude, and radius_meters
    op.alter_column('geofences', 'latitude', existing_type=sa.Double(), nullable=False)
    op.alter_column('geofences', 'longitude', existing_type=sa.Double(), nullable=False)
    op.alter_column('geofences', 'radius_meters', existing_type=sa.Double(), nullable=False)
    
    # 3. Remove geofence_type
    op.drop_column('geofences', 'geofence_type')
