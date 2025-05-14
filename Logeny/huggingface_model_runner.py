import os
import torch
from transformers import (
    AutoTokenizer,
    AutoModelForCausalLM,
    AutoModelForSequenceClassification,
    TextStreamer,
    pipeline
)

# Caches
_loaded_models = {}
_loaded_pipelines = {}

# ---------------------------------------------------
# Unified model caching utilities
# ---------------------------------------------------
def get_model_cache_dir(model_name):
    base_dir = os.path.join(os.path.dirname(__file__), "models")
    model_cache_dir = os.path.join(base_dir, model_name.replace("/", "_"))
    os.makedirs(model_cache_dir, exist_ok=True)
    return model_cache_dir

def get_tokenizer_and_model(model_name, model_type="causal-lm"):
    if model_name in _loaded_models:
        return _loaded_models[model_name]

    cache_dir = get_model_cache_dir(model_name)
    print(f"[INFO] Loading tokenizer and model into {cache_dir}")
    tokenizer = AutoTokenizer.from_pretrained(model_name, cache_dir=cache_dir)

    if model_type == "causal-lm":
        model = AutoModelForCausalLM.from_pretrained(model_name, cache_dir=cache_dir)
    elif model_type == "sequence-classification":
        model = AutoModelForSequenceClassification.from_pretrained(model_name, cache_dir=cache_dir)
    else:
        raise ValueError(f"Unsupported model type: {model_type}")

    model.eval()
    _loaded_models[model_name] = (tokenizer, model)
    return tokenizer, model

def get_pipeline(model_name, task="zero-shot-classification"):
    if model_name in _loaded_pipelines:
        return _loaded_pipelines[model_name]

    cache_dir = get_model_cache_dir(model_name)
    print(f"[INFO] Loading pipeline for {model_name} with task {task} from {cache_dir}")
    pipe = pipeline(task=task, model=model_name, tokenizer=model_name, cache_dir=cache_dir)
    _loaded_pipelines[model_name] = pipe
    return pipe

# ---------------------------------------------------
# Streaming Generation (True Streaming)
# ---------------------------------------------------
def stream_response(prompt, model_name, max_new_tokens=256):
    tokenizer, model = get_tokenizer_and_model(model_name, model_type="causal-lm")
    input_ids = tokenizer.encode(prompt, return_tensors="pt").to(model.device)

    streamer = TextStreamer(tokenizer, skip_prompt=True, skip_special_tokens=True)

    with torch.no_grad():
        model.generate(
            input_ids=input_ids,
            max_new_tokens=max_new_tokens,
            streamer=streamer,
            do_sample=True
        )

# ---------------------------------------------------
# Map-Reduce Generation
# ---------------------------------------------------
def split_into_chunks(text, max_tokens, tokenizer):
    tokens = tokenizer.encode(text)
    return [tokens[i:i + max_tokens] for i in range(0, len(tokens), max_tokens)]

def generate_responses_from_chunks(chunks, tokenizer, model, max_tokens=256):
    responses = []
    for chunk in chunks:
        input_ids = torch.tensor([chunk]).to(model.device)
        with torch.no_grad():
            output = model.generate(input_ids, max_new_tokens=max_tokens, do_sample=True)
        decoded = tokenizer.decode(output[0], skip_special_tokens=True)
        responses.append(decoded)
    return responses

def clean_response(response, prompt):
    prompt = prompt.strip().lower()
    response = response.strip()
    if response.lower().startswith(prompt):
        return response[len(prompt):].lstrip(":\n ")
    prompt_lines = set(line.strip().lower() for line in prompt.splitlines() if line.strip())
    cleaned_lines = [
        line for line in response.splitlines()
        if line.strip().lower() not in prompt_lines and line.strip() != ''
    ]
    return '\n'.join(cleaned_lines)

def generate_map_reduce_response(prompt, model_name, context_window=2048):
    tokenizer, model = get_tokenizer_and_model(model_name, model_type="causal-lm")
    max_input_tokens = context_window - 256
    chunks = split_into_chunks(prompt, max_input_tokens, tokenizer)
    partial_responses = generate_responses_from_chunks(chunks, tokenizer, model)

    if len(partial_responses) == 1:
        return clean_response(partial_responses[0], prompt)

    summary_prompt = "Summarize the following:\n" + "\n\n".join(partial_responses)
    summary_chunks = split_into_chunks(summary_prompt, max_input_tokens, tokenizer)
    summary_responses = generate_responses_from_chunks(summary_chunks, tokenizer, model)
    return clean_response("\n\n".join(summary_responses), prompt)

# ---------------------------------------------------
# Classification (Zero-Shot)
# ---------------------------------------------------
def classify_text(text, model_name, candidate_labels):
    pipe = get_pipeline(model_name, task="zero-shot-classification")
    return pipe(text, candidate_labels=candidate_labels)
