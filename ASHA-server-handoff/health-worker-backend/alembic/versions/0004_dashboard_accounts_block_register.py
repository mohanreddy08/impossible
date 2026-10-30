"""website accounts, per-phone API keys, admin audit, settings, block register (villages, ASHAs, members, house profiles), Q&A audit

Revision ID: 0004
Revises: 0003
"""
from alembic import op
import sqlalchemy as sa


revision = '0004'
down_revision = '0003'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('admin_audit',
    sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    sa.Column('at', sa.DateTime(), nullable=False),
    sa.Column('actor', sa.String(length=64), nullable=False),
    sa.Column('action', sa.String(length=32), nullable=False),
    sa.Column('target', sa.String(length=64), nullable=True),
    sa.Column('details', sa.JSON(), nullable=True),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('admin_audit', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_admin_audit_action'), ['action'], unique=False)
        batch_op.create_index(batch_op.f('ix_admin_audit_actor'), ['actor'], unique=False)
        batch_op.create_index(batch_op.f('ix_admin_audit_at'), ['at'], unique=False)

    op.create_table('app_settings',
    sa.Column('key', sa.String(length=64), nullable=False),
    sa.Column('value', sa.String(length=512), nullable=False),
    sa.Column('updated_at', sa.DateTime(), nullable=False),
    sa.Column('updated_by', sa.String(length=64), nullable=True),
    sa.PrimaryKeyConstraint('key')
    )
    op.create_table('ashas',
    sa.Column('worker_id', sa.String(length=32), nullable=False),
    sa.Column('name', sa.String(length=64), nullable=False),
    sa.Column('villages', sa.JSON(), nullable=False),
    sa.Column('source', sa.String(length=16), nullable=False),
    sa.PrimaryKeyConstraint('worker_id')
    )
    op.create_table('phone_keys',
    sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    sa.Column('key_id', sa.String(length=16), nullable=False),
    sa.Column('key_hash', sa.String(length=64), nullable=False),
    sa.Column('label', sa.String(length=64), nullable=False),
    sa.Column('worker_id', sa.String(length=32), nullable=False),
    sa.Column('created_by', sa.String(length=64), nullable=False),
    sa.Column('created_at', sa.DateTime(), nullable=False),
    sa.Column('revoked_at', sa.DateTime(), nullable=True),
    sa.Column('revoked_by', sa.String(length=64), nullable=True),
    sa.Column('last_seen_at', sa.DateTime(), nullable=True),
    sa.Column('last_sync_at', sa.DateTime(), nullable=True),
    sa.Column('last_installation_hash', sa.String(length=64), nullable=True),
    sa.Column('client_agent', sa.String(length=96), nullable=True),
    sa.Column('pushes', sa.Integer(), nullable=False),
    sa.Column('ops_received', sa.Integer(), nullable=False),
    sa.Column('ops_acknowledged', sa.Integer(), nullable=False),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('key_hash'),
    sa.UniqueConstraint('key_id')
    )
    with op.batch_alter_table('phone_keys', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_phone_keys_worker_id'), ['worker_id'], unique=False)

    op.create_table('qa_audit',
    sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    sa.Column('at', sa.DateTime(), nullable=False),
    sa.Column('actor', sa.String(length=64), nullable=False),
    sa.Column('channel', sa.String(length=16), nullable=False),
    sa.Column('outcome', sa.String(length=16), nullable=False),
    sa.Column('cited_section_ids', sa.JSON(), nullable=False),
    sa.Column('rule_ids', sa.JSON(), nullable=False),
    sa.Column('escalate', sa.Boolean(), nullable=False),
    sa.Column('refused', sa.Boolean(), nullable=False),
    sa.Column('latency_ms', sa.Float(), nullable=True),
    sa.Column('worker_id', sa.String(length=32), nullable=True),
    sa.Column('household_id', sa.String(length=32), nullable=True),
    sa.Column('status', sa.String(length=16), nullable=True),
    sa.Column('handled_by', sa.String(length=64), nullable=True),
    sa.Column('handled_at', sa.DateTime(), nullable=True),
    sa.Column('note_code', sa.String(length=32), nullable=True),
    sa.CheckConstraint("outcome IN ('ESCALATED','REFUSED','ANSWERED')", name='ck_qa_outcome'),
    sa.CheckConstraint("status IS NULL OR status IN ('OPEN','ACKNOWLEDGED','CLOSED')", name='ck_qa_status'),
    sa.PrimaryKeyConstraint('id')
    )
    with op.batch_alter_table('qa_audit', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_qa_audit_at'), ['at'], unique=False)
        batch_op.create_index(batch_op.f('ix_qa_audit_escalate'), ['escalate'], unique=False)
        batch_op.create_index(batch_op.f('ix_qa_audit_outcome'), ['outcome'], unique=False)
        batch_op.create_index(batch_op.f('ix_qa_audit_status'), ['status'], unique=False)

    op.create_table('users',
    sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    sa.Column('username', sa.String(length=64), nullable=False),
    sa.Column('display_name', sa.String(length=128), nullable=False),
    sa.Column('role', sa.String(length=16), nullable=False),
    sa.Column('worker_id', sa.String(length=32), nullable=True),
    sa.Column('password_hash', sa.String(length=256), nullable=False),
    sa.Column('is_active', sa.Boolean(), nullable=False),
    sa.Column('token_version', sa.Integer(), nullable=False),
    sa.Column('failed_logins', sa.Integer(), nullable=False),
    sa.Column('locked_until', sa.DateTime(), nullable=True),
    sa.Column('language', sa.String(length=4), nullable=False),
    sa.Column('created_at', sa.DateTime(), nullable=False),
    sa.Column('last_login_at', sa.DateTime(), nullable=True),
    sa.CheckConstraint("role <> 'asha' OR worker_id IS NOT NULL", name='ck_user_asha_worker'),
    sa.CheckConstraint("role IN ('admin','supervisor','asha')", name='ck_user_role'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('username')
    )
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_users_role'), ['role'], unique=False)

    op.create_table('villages',
    sa.Column('village_id', sa.String(length=32), nullable=False),
    sa.Column('name', sa.String(length=64), nullable=False),
    sa.Column('block', sa.String(length=64), nullable=False),
    sa.Column('source', sa.String(length=16), nullable=False),
    sa.Column('map_json', sa.JSON(), nullable=True),
    sa.PrimaryKeyConstraint('village_id')
    )
    op.create_table('household_profiles',
    sa.Column('household_id', sa.String(length=32), nullable=False),
    sa.Column('house_no', sa.String(length=16), nullable=True),
    sa.Column('head_member_id', sa.String(length=16), nullable=True),
    sa.Column('head_name', sa.String(length=64), nullable=True),
    sa.Column('lat', sa.Float(), nullable=True),
    sa.Column('lng', sa.Float(), nullable=True),
    sa.Column('phone_number', sa.String(length=20), nullable=True),
    sa.ForeignKeyConstraint(['household_id'], ['households.household_id'], ),
    sa.PrimaryKeyConstraint('household_id')
    )
    op.create_table('members',
    sa.Column('member_id', sa.String(length=16), nullable=False),
    sa.Column('household_id', sa.String(length=32), nullable=False),
    sa.Column('name', sa.String(length=64), nullable=False),
    sa.Column('relation', sa.String(length=32), nullable=True),
    sa.Column('sex', sa.String(length=1), nullable=True),
    sa.Column('dob', sa.Date(), nullable=True),
    sa.Column('register', sa.JSON(), nullable=False),
    sa.ForeignKeyConstraint(['household_id'], ['households.household_id'], ),
    sa.PrimaryKeyConstraint('member_id')
    )
    with op.batch_alter_table('members', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_members_household_id'), ['household_id'], unique=False)



def downgrade():
    with op.batch_alter_table('members', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_members_household_id'))

    op.drop_table('members')
    op.drop_table('household_profiles')
    op.drop_table('villages')
    with op.batch_alter_table('users', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_users_role'))

    op.drop_table('users')
    with op.batch_alter_table('qa_audit', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_qa_audit_status'))
        batch_op.drop_index(batch_op.f('ix_qa_audit_outcome'))
        batch_op.drop_index(batch_op.f('ix_qa_audit_escalate'))
        batch_op.drop_index(batch_op.f('ix_qa_audit_at'))

    op.drop_table('qa_audit')
    with op.batch_alter_table('phone_keys', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_phone_keys_worker_id'))

    op.drop_table('phone_keys')
    op.drop_table('ashas')
    op.drop_table('app_settings')
    with op.batch_alter_table('admin_audit', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_admin_audit_at'))
        batch_op.drop_index(batch_op.f('ix_admin_audit_actor'))
        batch_op.drop_index(batch_op.f('ix_admin_audit_action'))

    op.drop_table('admin_audit')
