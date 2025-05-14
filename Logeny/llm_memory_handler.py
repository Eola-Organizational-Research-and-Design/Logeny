import sqlite3
import numpy as np
from sentence_transformers import SentenceTransformer, util
from sklearn.metrics.pairwise import cosine_similarity
import torch

# Caching loaded models to avoid redundant downloads
model_cache = {}

def get_embedding_model(model_name):
    if model_name not in model_cache:
        model_cache[model_name] = SentenceTransformer(model_name)
    return model_cache[model_name]

def embed_text(texts, model_name):
    model = get_embedding_model(model_name)
    return model.encode(texts, convert_to_tensor=False).tolist()

def save_message_embedding(db_path, item_id, message, model_name, chunk_size=100):
    embedding = embed_text([message], model_name)[0]
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO documentEmbeddings (snippetID, itemID, chunkIndex, chunkStart, chunkEnd, embeddingModel, chunkSize, embedding)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        None, 
        item_id, 
        0, 
        0, 
        len(message), 
        model_name, 
        chunk_size, 
        sqlite3.Binary(np.array(embedding, dtype=np.float32).tobytes())
    ))
    conn.commit()
    conn.close()
    return embedding

def retrieve_nearest_context(db_path, user_message, model_name, chat_thread_id, k=3):
    message_vec = embed_text([user_message], model_name)[0]

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("""
        SELECT de.itemID, de.chunkIndex, de.embedding, it.tagResponse
        FROM documentEmbeddings de
        JOIN itemTags it ON de.itemID = it.itemID
        WHERE de.embeddingModel = ? AND it.tagCategory = 'chat_thread' AND it.tagResponse = ?
    """, (model_name, chat_thread_id))
    rows = cur.fetchall()

    embeddings = []
    item_ids = []
    for item_id, chunk_idx, embedding_blob, _ in rows:
        cur.execute("""
            SELECT tagResponse FROM itemTags
            WHERE itemID = ? AND tagCategory = 'note_content'
        """, (item_id,))
        note = cur.fetchone()
        if not note:
            continue

        embedding_vector = np.frombuffer(embedding_blob, dtype=np.float32)
        embeddings.append(embedding_vector)
        item_ids.append((item_id, note[0]))

    conn.close()

    if not embeddings:
        return []

    similarities = cosine_similarity([message_vec], embeddings)[0]
    top_indices = np.argsort(similarities)[-k:][::-1]

    top_notes = [item_ids[i][1] for i in top_indices]
    return top_notes

def build_short_term_memory(db_path, user_message, model_name, chat_thread_id, max_k=3):
    neighbors = retrieve_nearest_context(
        db_path, user_message, model_name, chat_thread_id, k=max_k
    )
    return "\n---\n".join(neighbors)

def assemble_memory_context(db_path,
                             thread_name,
                             user_message,
                             k_last_messages=5,
                             use_summary=True,
                             n_snippet_neighbors=3,
                             snippet_embedding_model="sentence-transformers/all-MiniLM-L6-v2"):
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    # (1) Get last K messages from the thread
    cur.execute("""
        SELECT t1.tagResponse AS note_content
        FROM items i
        JOIN itemTags t1 ON i.itemID = t1.itemID AND t1.tagCategory = 'note_content'
        JOIN itemTags t2 ON i.itemID = t2.itemID AND t2.tagCategory = 'chat_thread'
        WHERE t2.tagResponse = ?
        ORDER BY i.itemID DESC
        LIMIT ?
    """, (thread_name, k_last_messages))
    last_messages = [row[0] for row in cur.fetchall()]
    last_k_text = "\n".join(reversed(last_messages)) if last_messages else ""


    return {
        "here are is our conversation history": last_k_text,

    }
