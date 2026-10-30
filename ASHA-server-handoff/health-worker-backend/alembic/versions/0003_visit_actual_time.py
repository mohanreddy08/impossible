"""visit actual_visit_time (time of day the worker went)

Revision ID: 0003
Revises: 0002
"""
from alembic import op
import sqlalchemy as sa


revision = '0003'
down_revision = '0002'
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table('visits', schema=None) as batch_op:
        batch_op.add_column(sa.Column('actual_visit_time', sa.Time(), nullable=True))


def downgrade():
    with op.batch_alter_table('visits', schema=None) as batch_op:
        batch_op.drop_column('actual_visit_time')
