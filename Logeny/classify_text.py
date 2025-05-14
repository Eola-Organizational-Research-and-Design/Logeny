from transformers import AutoTokenizer, AutoModelForSequenceClassification, pipeline
import os
import torch

# Suppress symlink warnings
os.environ['HF_HUB_DISABLE_SYMLINKS_WARNING'] = '1'

# ----------------------------- Utility Functions -----------------------------


def split_text(text, max_chunk_size=512):
    """Splits a long text into smaller chunks."""
    words = text.split()
    chunks = [' '.join(words[i:i + max_chunk_size]) for i in range(0, len(words), max_chunk_size)]
    return chunks


# ----------------------------- Model Loading -----------------------------

# Define a local directory to cache the model
MODEL_NAME = "facebook/bart-large-mnli" # "distilbert-base-uncased"  #  A second widely used default for zero-shot classification
CACHE_DIR = os.path.join(os.path.dirname(__file__), "models", MODEL_NAME.replace("/", "_"))
os.makedirs(CACHE_DIR, exist_ok=True)

# Load tokenizer and model ONCE (outside the function)
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME, cache_dir=CACHE_DIR)

# Initialize the model globally
model = None  # Initialize as None


def load_model():
    global model
    if model is None:
        model = AutoModelForSequenceClassification.from_pretrained(
            MODEL_NAME,
            cache_dir=CACHE_DIR
        )
        model.eval()  # Set to evaluation mode
        # Move the model to the GPU if available
        if torch.cuda.is_available():
            model = model.to("cuda")


load_model()  # Load the model when the script is loaded

# Initialize pipeline globally
global_pipeline = pipeline(
    "zero-shot-classification",
    model=model,
    tokenizer=tokenizer,
    device=0 if torch.cuda.is_available() else -1,  # Use GPU if available, else CPU
    batch_size=16  # Add a batch size
)


# ----------------------------- Classification Function -----------------------------

def classify_text_with_map_reduce(text_list, prompt, terms):
    """Classify long texts using Map-Reduce."""

    classifications = []

    for text in text_list:
        try:
            chunks = split_text(text, max_chunk_size=512)
            # Use the global pipeline
            chunk_results = global_pipeline(chunks, candidate_labels=terms,  truncation=True,  max_length=512)

            # Process the results.  chunk_results is already a list of dicts.
            final_classification = max(chunk_results, key=lambda x: x['scores'][0])['labels'][0]
            classifications.append(final_classification)

        except Exception as e:
            classifications.append(f"Error: {str(e)}")

    return classifications
