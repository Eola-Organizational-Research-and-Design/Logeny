import sqlite3
import hashlib
from datetime import datetime

def hash_password(password):
    return hashlib.sha256(password.encode()).hexdigest()

def create_users_table(conn):
    conn.execute("""
        CREATE TABLE IF NOT EXISTS users (
            username TEXT PRIMARY KEY,
            password_hash TEXT,
            role TEXT DEFAULT 'member',
            status TEXT DEFAULT 'pending'
        )
    """)
    conn.commit()

def create_admin_user(db_path, username, password):
    conn = sqlite3.connect(db_path)
    try:
        create_users_table(conn)
        cur = conn.cursor()
        hashed = hash_password(password)
        cur.execute("INSERT INTO users (username, password_hash, role, status) VALUES (?, ?, 'admin', 'active')",
                    (username, hashed))
        conn.commit()
        return True
    except Exception as e:
        print("Admin creation error:", e)
        return False
    finally:
        conn.close()

def authenticate_user(db_path, username, password):
    conn = sqlite3.connect(db_path)
    try:
        create_users_table(conn)
        hashed = hash_password(password)
        cur = conn.cursor()
        cur.execute("SELECT role, status FROM users WHERE username=? AND password_hash=?", (username, hashed))
        row = cur.fetchone()
        if row:
            role, status = row
            if status == "active":
                return role
        return None
    finally:
        conn.close()

def register_user(db_path, username, password, role="member"):
    conn = sqlite3.connect(db_path)
    try:
        create_users_table(conn)
        cur = conn.cursor()
        cur.execute("SELECT * FROM users WHERE username=?", (username,))
        if cur.fetchone():
            return "exists"
        hashed = hash_password(password)
        cur.execute("INSERT INTO users (username, password_hash, role, status) VALUES (?, ?, ?, 'pending')",
                    (username, hashed, role))
        conn.commit()

        # Send alert message via items to Global project
        cur.execute("SELECT entity_id FROM entities WHERE entity_name='Global' AND entity_type='project'")
        row = cur.fetchone()
        if row:
            global_id = row[0]
            note = f"New user '{username}' has requested access. Please approve."
            cur.execute("""
                INSERT INTO items (key, content, created_by, created_at)
                VALUES (?, ?, ?, datetime('now'))
            """, (f"note_global_{username}", note, "system"))
            conn.commit()
        return "pending"
    except Exception as e:
        print("Registration error:", e)
        return "error"
    finally:
        conn.close()

        
def get_pending_users(db_path):
    import sqlite3
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT username FROM users WHERE status='pending'")
    results = [r[0] for r in c.fetchall()]
    conn.close()
    return results

def update_user_status(db_path, username, new_status):
    import sqlite3
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("UPDATE users SET status=? WHERE username=?", (new_status, username))
    conn.commit()
    conn.close()
    return True
  
def get_all_project_names(db_path):
    import sqlite3
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT entity_name FROM entities WHERE entity_type='project' ORDER BY entity_name ASC")
        names = [row[0] for row in cursor.fetchall()]
    finally:
        conn.close()
    return names

