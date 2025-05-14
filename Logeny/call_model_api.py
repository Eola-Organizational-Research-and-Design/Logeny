import sqlite3
import hashlib
import os

import openai
import google.generativeai as genai
from importlib import import_module


def call_model_api(model_name, prompt, db_path, user_name, chat_thread_id):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get entity_id for model
    cursor.execute("SELECT entity_id FROM entities WHERE entity_name = ? AND entity_type = 'model'", (model_name,))
    row = cursor.fetchone()
    if not row:
        raise ValueError(f"Model '{model_name}' not found in database.")
    model_id = row[0]

    # Get model tags
    cursor.execute("SELECT tagCategory, tagValue FROM entity_tags WHERE entity_id = ?", (model_id,))
    tags = {row[0]: row[1] for row in cursor.fetchall()}

    # Get user_id
    cursor.execute("SELECT entity_id FROM entities WHERE entity_name = ? AND entity_type = 'user'", (user_name,))
    user_id = cursor.fetchone()[0]

    # Retrieve API key path for this model-user pair
    api_path_key = f"api_path_{model_name}"
    cursor.execute("SELECT tagValue FROM entity_tags WHERE entity_id = ? AND tagCategory = ?", (user_id, api_path_key))
    api_key_path_row = cursor.fetchone()
    api_key_path = api_key_path_row[0] if api_key_path_row else None

    # Read the actual API key
    api_key = None
    if api_key_path and os.path.exists(api_key_path):
        with open(api_key_path, "r") as f:
            api_key = f.read().strip()

    # Load imports dynamically
    if "import_statement" in tags:
        exec(tags["import_statement"], globals())

    # Provider-specific authentication
    if "provider" in tags and tags["provider"] == "openai":
        openai.api_key = api_key
    elif "provider" in tags and tags["provider"] == "google":
        genai.configure(api_key=api_key)

    # Build execution context
    local_vars = {
        "prompt": prompt,
        "chat_thread_id": chat_thread_id,
        "context_window": int(tags.get("context_window", 4096)),
    }

    try:
        if "api_call_template" not in tags:
            raise RuntimeError("Missing 'api_call_template' tag for model.")
        print("===== Executing API call =====")
        print(tags["api_call_template"])
        result = eval(tags["api_call_template"], globals(), local_vars)
        return result
    except Exception as e:
        raise RuntimeError(f"Failed to execute API call: {str(e)}")
