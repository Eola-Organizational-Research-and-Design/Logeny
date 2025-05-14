import os
import re
import sqlite3
import numpy as np
from sentence_transformers import SentenceTransformer

from extract_text import read_text_file

###############################################################################
# HNSWIndex with Cosine Distance
###############################################################################

class HNSWIndex:
    def __init__(self, dim, M=16, ef=50):
        self.dim = dim
        self.M = M
        self.ef = ef
        self.vectors = []
        self.ids = []
        self.graph = []

    def add_items(self, vectors, ids):
        def cosine_distance(v1, v2):
            return 1.0 - np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2))

        for i in range(len(vectors)):
            v = vectors[i]
            the_id = ids[i]
            idx = len(self.vectors)
            self.vectors.append(v)
            self.ids.append(the_id)
            self.graph.append([])
            if idx == 0:
                continue
            dists = []
            for j in range(idx):
                dist = cosine_distance(v, self.vectors[j])
                dists.append((dist, j))
            dists.sort(key=lambda x: x[0])
            neighbors = [p[1] for p in dists[:self.M]]
            self.graph[idx] = neighbors
            for nbr in neighbors:
                if len(self.graph[nbr]) < self.M:
                    self.graph[nbr].append(idx)

    def search(self, qvec, top_k=5):
        def cosine_distance(v1, v2):
            return 1.0 - np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2))

        import random, heapq
        if len(self.vectors) == 0:
            return []

        start = random.randint(0, len(self.vectors)-1)
        visited = set([start])
        candidates = [(cosine_distance(qvec, self.vectors[start]), start)]
        heapq.heapify(candidates)

        while len(candidates) < self.ef and len(candidates) < len(self.vectors):
            dist, node = heapq.heappop(candidates)
            for nbr in self.graph[node]:
                if nbr not in visited:
                    visited.add(nbr)
                    dist_nbr = cosine_distance(qvec, self.vectors[nbr])
                    heapq.heappush(candidates, (dist_nbr, nbr))

        candidates.sort(key=lambda x: x[0])
        return [self.ids[x[1]] for x in candidates[:top_k]]

###############################################################################
# Reconstruct Snippet
###############################################################################

def re_chunk_file(file_path, chunk_size, snippet_index):
    text = read_text_file(file_path)
    if not text:
        return None
    words = re.split(r"\s+", text.strip())
    start_i = snippet_index * chunk_size
    end_i = min(len(words), start_i + chunk_size)
    if start_i >= len(words):
        return None
    return " ".join(words[start_i:end_i])

###############################################################################
# Vector Search Logic
###############################################################################
def vector_db_search(db_path, collection_name, query_str, top_k=5, chunk_size=50, model_name="sentence-transformers/all-MiniLM-L6-v2"):

    os.environ["TRANSFORMERS_OFFLINE"] = "1"

    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    # 1. Get relevant itemIDs
    if collection_name == "All Documents":
        c.execute("SELECT itemID FROM items WHERE itemTypeID != 14")
        item_ids = [r[0] for r in c.fetchall()]
    else:
        c.execute("SELECT collectionID FROM collections WHERE collectionName=?", (collection_name,))
        row = c.fetchone()
        if not row:
            conn.close()
            return []
        coll_id = row[0]
        c.execute("SELECT itemID FROM collectionItems WHERE collectionID=?", (coll_id,))
        item_ids = [r[0] for r in c.fetchall()]
        if not item_ids:
            conn.close()
            return []

    # 2. Load embeddings
    placeholders = ",".join(["?"] * len(item_ids))
    c.execute(f"""
        SELECT snippetID, itemID, chunkIndex
        FROM documentEmbeddings
        WHERE itemID IN ({placeholders})
        ORDER BY snippetID
    """, item_ids)
    snippet_rows = c.fetchall()

    db_folder = os.path.dirname(db_path)
    emb_folder = os.path.join(db_folder, "embedding_data")
    vectors = []
    snippet_ids = []

    for s_id, i_id, chunk_idx in snippet_rows:
        emb_path = os.path.join(emb_folder, f"snippet_{s_id}.npy")
        if os.path.exists(emb_path):
            vectors.append(np.load(emb_path))
            snippet_ids.append((s_id, i_id, chunk_idx))

    if not vectors:
        conn.close()
        return []

    # 3. Build HNSW index and embed query
    dim = vectors[0].shape[0]
    hnsw = HNSWIndex(dim)
    hnsw.add_items(np.array(vectors, dtype=np.float32), list(range(len(vectors))))

    embedder = SentenceTransformer(model_name, cache_folder=os.path.expanduser("~/.cache/huggingface/"))
    q_vec = embedder.encode([query_str])[0].astype("float32")

    # 4. Search
    local_indices = hnsw.search(q_vec, top_k=top_k)

    # 5. Insert results + return
    results = []
    for L in local_indices:
        snippet_id, item_id, chunk_idx = snippet_ids[L]

        # Fetch file path for chunk reconstruction
        c.execute("SELECT key FROM items WHERE itemID=?", (item_id,))
        row_k = c.fetchone()
        if not row_k:
            continue
        file_key = row_k[0]

        snippet_text = re_chunk_file(file_key, chunk_size, chunk_idx)
        snippet_text = snippet_text if snippet_text else "(No snippet text found)"

        # Check if result already exists
        c.execute("""
            SELECT 1 FROM search_results
            WHERE snippetID = ? AND query = ? AND collection_name = ?
        """, (snippet_id, query_str, collection_name))
        if not c.fetchone():
            c.execute("""
                INSERT INTO search_results (queryID, snippetID, query, matched_word, context, collection_name)
                VALUES (?,?, ?, ?, ?, ?)
            """, (0,snippet_id, query_str, query_str, snippet_text, collection_name))

        results.append({
            "snippetID": snippet_id,
            "matched_word": query_str,
            "context": snippet_text
        })

    conn.commit()
    conn.close()
    return results

