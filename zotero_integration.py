import sqlite3
import os
import re
import time

def get_all_collections(db_path):
    if not os.path.exists(db_path):
        raise FileNotFoundError(f"Zotero DB not found at: {db_path}")
    
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT collectionName FROM collections")
    rows = c.fetchall()
    conn.close()
    
    return [row[0] for row in rows if row[0]]

def get_collection_items_metadata(db_path, collection_name, require_attachment=False):
    if not os.path.exists(db_path):
        raise FileNotFoundError(f"Zotero database not found at: {db_path}")

    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    c.execute("SELECT collectionID FROM collections WHERE collectionName=?", (collection_name,))
    row = c.fetchone()
    if not row:
        conn.close()
        return []
    collection_id = row[0]

    c.execute("SELECT itemID FROM collectionItems WHERE collectionID=?", (collection_id,))
    item_ids = [r[0] for r in c.fetchall()]
    if not item_ids:
        conn.close()
        return []

    all_metadata = []

    for item_id in item_ids:
        if require_attachment:
            c.execute("SELECT key FROM items WHERE itemID=?", (item_id,))
            row_key = c.fetchone()
            if not row_key:
                continue

        c.execute("SELECT key FROM items WHERE itemID=?", (item_id,))
        row_key = c.fetchone()
        key = row_key[0] if row_key else ""

        # Title
        c.execute("""
            SELECT itemDataValues.value
            FROM itemData
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
            WHERE itemData.itemID=? AND itemData.fieldID=110
        """, (item_id,))
        title = c.fetchone()
        title = ' '.join(str(title[0]).split()) if title else ""

        # Authors
        c.execute("""
            SELECT group_concat(creators.lastName, '; ')
            FROM itemCreators
            JOIN creators ON itemCreators.creatorID = creators.creatorID
            WHERE itemCreators.itemID = ?
        """, (item_id,))
        authors = c.fetchone()
        authors = ' '.join(str(authors[0]).split()) if authors and authors[0] else ""

        # Year
        c.execute("""
            SELECT itemDataValues.value
            FROM itemData
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
            WHERE itemData.itemID=? AND itemData.fieldID=115
        """, (item_id,))
        date = c.fetchone()
        year = ""
        if date:
            try:
                match = re.match(r"(\d{4})", str(date[0]))
                if match:
                    year = match.group(1)
            except:
                year = ""

        all_metadata.append({
            "itemID": item_id,
            "title": title,
            "authors": authors,
            "year": year,
            "key": key
        })

    conn.close()
    return all_metadata

def add_crossref_results_to_zotero(db_path, collection_name, results):
    if not os.path.exists(db_path):
        raise FileNotFoundError(f"Zotero database not found at: {db_path}")

    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    c.execute("SELECT collectionID FROM collections WHERE collectionName=?", (collection_name,))
    row = c.fetchone()
    if not row:
        raise ValueError(f"Collection '{collection_name}' not found in Zotero DB")
    collection_id = row[0]

    c.execute("SELECT MAX(itemID) FROM items")
    item_id_counter = (c.fetchone()[0] or 0) + 1

    c.execute("SELECT MAX(creatorID) FROM creators")
    creator_id_counter = (c.fetchone()[0] or 0) + 1

    for paper in results:
        if not isinstance(paper, dict):
            continue

        title = ' '.join(str(paper.get("title", "")).split())
        authors = paper.get("authors", [])
        if isinstance(authors, str):
            authors = [a.strip() for a in authors.split(",")]
        year = str(paper.get("year", "")).strip()
        doi = ' '.join(str(paper.get("doi", "")).split())

        itemID = item_id_counter
        item_key = f"AUTO{int(time.time()*1000)}{itemID}"[-8:]

        c.execute("INSERT INTO items (itemID, itemTypeID, libraryID, dateAdded, key) VALUES (?, 2, 1, datetime('now'), ?)", (itemID, item_key))

        def insert_field(fieldID, value):
            value = str(value).strip()
            if not value:
                return
            c.execute("INSERT OR IGNORE INTO itemDataValues (value) VALUES (?)", (value,))
            c.execute("SELECT valueID FROM itemDataValues WHERE value = ?", (value,))
            valueID = c.fetchone()[0]
            c.execute("INSERT INTO itemData (itemID, fieldID, valueID) VALUES (?, ?, ?)", (itemID, fieldID, valueID))

        insert_field(110, title)
        insert_field(115, year)
        insert_field(27, doi)

        for orderIndex, author in enumerate(authors):
            author = ' '.join(str(author).split())
            if not author:
                continue
            c.execute("INSERT INTO creators (creatorID, lastName) VALUES (?, ?)", (creator_id_counter, author))
            c.execute("INSERT INTO itemCreators (itemID, creatorID, creatorTypeID, orderIndex) VALUES (?, ?, 1, ?)", (itemID, creator_id_counter, orderIndex))
            creator_id_counter += 1

        c.execute("INSERT INTO collectionItems (collectionID, itemID) VALUES (?, ?)", (collection_id, itemID))
        item_id_counter += 1

    conn.commit()
    conn.close()
    return True