import os
import json
import re
import PyPDF2
import docx
import pandas as pd

def read_text_file(file_path):
    """
    Reads text from multiple file types, returning a single string.
    If unsupported or fails, returns None.
    Supported: .txt, .r, .py, .rmd, .md, .xml, .pdf, .docx, .json
    """
    if not os.path.isfile(file_path):
        print(f"Warning: File does not exist: {file_path}")
        return None

    ext = os.path.splitext(file_path)[1].lower()

    try:
        if ext in [".txt", ".r", ".py", ".rmd", ".md", ".xml"]:
            with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                text_content = f.read()
            return text_content.replace("\x00", "")

        elif ext == ".pdf":
            text_chunks = []
            with open(file_path, "rb") as f:
                reader = PyPDF2.PdfReader(f)
                for page in reader.pages:
                    page_text = page.extract_text()
                    if page_text:
                        text_chunks.append(page_text)
            return "\n".join(text_chunks).replace("\x00", "")

        elif ext == ".docx":
            doc_file = docx.Document(file_path)
            paragraphs = [p.text for p in doc_file.paragraphs]
            return "\n".join(paragraphs).replace("\x00", "")

        elif ext == ".json":
            with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                data = json.load(f)
            return json.dumps(data, ensure_ascii=False)

        else:
            print(f"Skipping unsupported file extension: {ext}")
            return None

    except Exception as e:
        print(f"Warning: Could not parse file at {file_path} => {e}")
        return None


def extract_snippets(file_path, search_terms, context_size=50):
    """
    1) Reads file text via read_text_file.
    2) Does a SIMPLE exact-match snippet extraction for each search term.
       - No expansions, synonyms, or partial matching.
       - Each match returns 'context_size' words around it.

    Returns a pd.DataFrame with columns ["document", "matched_word", "context"].
    """
    text_content = read_text_file(file_path)
    if not text_content:
        return pd.DataFrame(columns=["document","matched_word","context"])

    # Lowercase for a naive case-insensitive match
    text_content = text_content.lower()

    # Tokenize by whitespace
    tokens = re.split(r"\s+", text_content.strip())

    # We'll define a helper to remove leading/trailing punctuation
    import string
    def strip_punct(token):
        return token.strip(string.punctuation)

    results = []
    doc_title = os.path.basename(file_path)
    context_size = int(context_size)

    # For each user-provided search term
    for term in search_terms:
        term_lower = term.lower()
        # find tokens that EXACTLY match `term_lower` after punctuation strip
        match_positions = []
        for i, raw_tok in enumerate(tokens):
            w_stripped = strip_punct(raw_tok)
            if w_stripped == term_lower:
                match_positions.append(i)

        # For each match, build a snippet +/- context_size words
        for idx in match_positions:
            start = max(0, idx - context_size)
            end   = min(len(tokens), idx + context_size + 1)
            snippet_text = " ".join(tokens[start:end])
            results.append({
                "document": doc_title,
                "matched_word": term,
                "context": snippet_text
            })

    df = pd.DataFrame(results, columns=["document","matched_word","context"])
    return df


