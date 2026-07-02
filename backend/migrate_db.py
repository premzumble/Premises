import asyncio
import os
import sqlite3
import psycopg2
from urllib.parse import urlparse

# Load .env file manually
def load_env():
    env_path = os.path.join(os.path.dirname(__file__), ".env")
    if os.path.exists(env_path):
        with open(env_path, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    v = v.strip().strip('"').strip("'")
                    os.environ[k] = v

load_env()

pg_url_str = os.environ.get("DATABASE_URL", "")
sqlite_path = os.environ.get("DATABASE_URL_SYNC_FALLBACK", "sqlite:///./premises_fallback.db").replace("sqlite:///", "")

ddl_attendance_records = [
    "ALTER TABLE attendance_records ADD COLUMN is_overridden BOOLEAN NOT NULL DEFAULT FALSE;",
    "ALTER TABLE attendance_records ADD COLUMN override_status VARCHAR(30);",
    "ALTER TABLE attendance_records ADD COLUMN override_reason TEXT;",
    "ALTER TABLE attendance_records ADD COLUMN override_remarks TEXT;",
    "ALTER TABLE attendance_records ADD COLUMN override_by UUID;",
    "ALTER TABLE attendance_records ADD COLUMN override_at TIMESTAMPTZ;",
    "ALTER TABLE attendance_records ADD COLUMN manual_check_in_time TIMESTAMPTZ;",
    "ALTER TABLE attendance_records ADD COLUMN manual_check_out_time TIMESTAMPTZ;",
    "ALTER TABLE attendance_records ADD COLUMN effective_working_hours DOUBLE PRECISION;"
]

ddl_notifications = [
    "ALTER TABLE notifications ADD COLUMN acknowledged_at TIMESTAMPTZ;"
]

ddl_notifications_constraint_pg = [
    "ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;"
]

def migrate_sqlite():
    print(f"Migrating SQLite fallback database at: {sqlite_path}")
    if not os.path.exists(sqlite_path):
        print("SQLite database file does not exist, skipping.")
        return
    
    conn = sqlite3.connect(sqlite_path)
    cursor = conn.cursor()
    
    # Check if is_overridden already exists to prevent duplicate migration errors
    cursor.execute("PRAGMA table_info(attendance_records);")
    columns = [col[1] for col in cursor.fetchall()]
    
    if "is_overridden" not in columns:
        print("Migrating SQLite attendance_records table...")
        for sql in ddl_attendance_records:
            try:
                # SQLite ALTER TABLE might not like TIMESTAMPTZ/UUID/DOUBLE PRECISION directly in some syntax,
                # but standard type names work. We replace psycopg specific types.
                clean_sql = sql.replace("TIMESTAMPTZ", "TEXT").replace("UUID", "TEXT").replace("DOUBLE PRECISION", "REAL")
                cursor.execute(clean_sql)
            except Exception as e:
                print(f"SQLite Alter error: {e}")
        conn.commit()
    else:
        print("SQLite attendance_records already has is_overridden column.")

    # Check notification acknowledged_at
    cursor.execute("PRAGMA table_info(notifications);")
    notif_columns = [col[1] for col in cursor.fetchall()]
    if "acknowledged_at" not in notif_columns:
        print("Migrating SQLite notifications table...")
        for sql in ddl_notifications:
            try:
                clean_sql = sql.replace("TIMESTAMPTZ", "TEXT")
                cursor.execute(clean_sql)
            except Exception as e:
                print(f"SQLite Alter notifications error: {e}")
        conn.commit()
    else:
        print("SQLite notifications already has acknowledged_at column.")
        
    conn.close()
    print("SQLite migration finished.")

def migrate_postgresql():
    if not pg_url_str:
        print("No DATABASE_URL configured, skipping PostgreSQL migration.")
        return
    
    # Parse sync pg url from asyncpg url
    sync_url = pg_url_str.replace("postgresql+asyncpg://", "postgresql://")
    print(f"Migrating PostgreSQL database...")
    
    try:
        conn = psycopg2.connect(sync_url)
        conn.autocommit = True
        cursor = conn.cursor()
        
        # Check if is_overridden column exists
        cursor.execute("SELECT column_name FROM information_schema.columns WHERE table_name='attendance_records' AND column_name='is_overridden';")
        res = cursor.fetchone()
        
        if not res:
            print("Migrating PostgreSQL attendance_records table...")
            for sql in ddl_attendance_records:
                try:
                    cursor.execute(sql)
                except Exception as e:
                    print(f"PostgreSQL Alter error: {e}")
        else:
            print("PostgreSQL attendance_records already migrated.")
            
        # Check acknowledged_at
        cursor.execute("SELECT column_name FROM information_schema.columns WHERE table_name='notifications' AND column_name='acknowledged_at';")
        res_notif = cursor.fetchone()
        if not res_notif:
            print("Migrating PostgreSQL notifications table...")
            for sql in ddl_notifications:
                try:
                    cursor.execute(sql)
                except Exception as e:
                    print(f"PostgreSQL Alter notifications error: {e}")
        else:
            print("PostgreSQL notifications already has acknowledged_at column.")

        # Update constraint
        print("Updating PostgreSQL notification type constraints...")
        for sql in ddl_notifications_constraint_pg:
            try:
                cursor.execute(sql)
            except Exception as e:
                print(f"PostgreSQL Constraint error: {e}")
                
        cursor.close()
        conn.close()
        print("PostgreSQL migration finished successfully.")
    except Exception as e:
        print(f"PostgreSQL connection/migration failed: {e}")

if __name__ == "__main__":
    migrate_sqlite()
    migrate_postgresql()
