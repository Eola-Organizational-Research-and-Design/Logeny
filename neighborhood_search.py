import requests
import pandas as pd
import time

# Optional: Include your email to help with Crossref rate limits
HEADERS = {"User-Agent": "n-neighborhood-app (mailto:shails@vt.edu)"}

def get_crossref_metadata(doi):
    """
    Query Crossref API to get metadata and references for a given DOI.
    Returns dict with Title, Authors, Year, and list of Reference DOIs.
    """
    url = f"https://api.crossref.org/works/{doi}"
    try:
        response = requests.get(url, headers=HEADERS, timeout=10)
        response.raise_for_status()
        item = response.json()["message"]

        title = item.get("title", [""])[0]
        authors = ", ".join([
            f"{a.get('given', '')} {a.get('family', '')}".strip()
            for a in item.get("author", [])
        ])
        year = item.get("issued", {}).get("date-parts", [[""]])[0][0]

        reference_dois = []
        for ref in item.get("reference", []):
            ref_doi = ref.get("DOI")
            if ref_doi:
                reference_dois.append(ref_doi.lower())

        return {
            "DOI": doi,
            "Title": title,
            "Authors": authors,
            "Year": year,
            "References": reference_dois,
        }
    except Exception as e:
        print(f"Error fetching DOI {doi}: {e}")
        return {
            "DOI": doi,
            "Title": None,
            "Authors": None,
            "Year": None,
            "References": []
        }

def n_neighborhood_search(doi, depth=1):
    """
    Recursively search reference DOIs up to depth `n`, starting from `doi`.
    Returns: List of dicts with metadata for each visited paper.
    """
    visited = set()
    queue = [(doi, 0, "Source")]
    all_results = []

    while queue:
        current_doi, current_depth, relation = queue.pop(0)

        if current_doi in visited:
            continue
        visited.add(current_doi)

        print(f" Depth {current_depth}: {current_doi}")

        data = get_crossref_metadata(current_doi)
        data["Depth"] = current_depth
        data["Relation"] = relation
        all_results.append(data)

        # Throttle to avoid rate limits
        time.sleep(1)

        if current_depth < depth:
            for ref_doi in data["References"]:
                if ref_doi and ref_doi not in visited:
                    queue.append((ref_doi, current_depth + 1, "Reference"))

    return pd.DataFrame(all_results)

