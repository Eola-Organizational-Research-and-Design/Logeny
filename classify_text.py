from transformers import AutoTokenizer, AutoModelForCausalLM,pipeline  # Add this import
import os


os.environ['HF_HUB_DISABLE_SYMLINKS_WARNING'] = '1'

# Load GPT-2 model and tokenizer
tokenizer_gpt2 = AutoTokenizer.from_pretrained("gpt2")
model_gpt2 = AutoModelForCausalLM.from_pretrained("gpt2")


def generate_with_gpt2(prompt, max_new_tokens=200, temperature=0.7):
    """
    Generate text using GPT-2.

    Args:
        prompt (str): Input prompt for the model.
        max_new_tokens (int): Maximum number of tokens to generate.
        temperature (float): Sampling temperature for diversity.

    Returns:
        str: Generated text.
    """
    inputs = tokenizer_gpt2(prompt, return_tensors="pt", truncation=True, max_length=1024)
    outputs = model_gpt2.generate(
        inputs["input_ids"], 
        max_new_tokens=max_new_tokens, 
        temperature=temperature, 
        pad_token_id=tokenizer_gpt2.eos_token_id
    )
    return tokenizer_gpt2.decode(outputs[0], skip_special_tokens=True)


  
def qa_with_gpt2(conversation, max_tokens=300, temperature=0.7):
    try:
        # Prepare prompt
        prompt = ""
        for message in conversation:
            prompt += f"{message['role']}: {message['content']}\n"
        prompt += "assistant:"

        # Handle token limits and chunking
        prompt_tokens = tokenizer_gpt2.tokenize(prompt)
        if len(prompt_tokens) < 600:
            generated_text = generate_with_gpt2(prompt, max_new_tokens=max_tokens, temperature=temperature)
        else:
            # Chunking for large contexts
            reduced_prompt = handle_large_contexts(prompt_tokens, max_tokens)
            generated_text = generate_with_gpt2(reduced_prompt, max_new_tokens=max_tokens, temperature=temperature)

        # Parse GPT-2's response
        assistant_response = generated_text.split("assistant:")[-1].strip()

        # Update conversation history
        conversation.append({"role": "assistant", "content": assistant_response})
        return conversation
    except Exception as e:
        conversation.append({"role": "assistant", "content": f"Error: {str(e)}"})
        return conversation

# ----------------------------- Classification Function -----------------------------


# Load zero-shot classification model
pipe = pipeline("zero-shot-classification", model="valhalla/distilbart-mnli-12-1")

def classify_text(text_list, prompt, terms):
    """
    Classify texts using zero-shot classification.

    Args:
        text_list (list): List of texts to classify.
        prompt (str): Instruction prompt for context (not used directly but can guide preprocessing).
        terms (list): List of classification labels.

    Returns:
        list: List of classification results.
    """
    classifications = []

    for text in text_list:
        try:
            # Perform zero-shot classification
            result = pipe(text, candidate_labels=terms)
            
            # Get the label with the highest score
            classification = result['labels'][0]
            classifications.append(classification)
        except Exception as e:
            classifications.append(f"Error: {str(e)}")

    return classifications


      
      



