#!/bin/bash
set -e

echo "Reassembling model weights..."
cat weights/model_part_* > model.gguf

echo "Installing llama-cpp-python..."
pip install llama-cpp-python --quiet

echo "Running inference..."
python3 - << 'EOF'
import os, json
from llama_cpp import Llama

history_file = "memory/history.json"
prompt = os.environ["USER_PROMPT"]
clear_history = os.environ["CLEAR_HISTORY"].lower() == "true"

if clear_history or not os.path.exists(history_file):
    history = [{"role": "system", "content": "You are a helpful, concise AI assistant."}]
else:
    with open(history_file, "r") as f:
        history = json.load(f)
    if not history:
        history = [{"role": "system", "content": "You are a helpful, concise AI assistant."}]

history.append({"role": "user", "content": prompt})

trimmed_history = [history[0]] + history[-6:] if len(history) > 7 else history

llm = Llama(model_path="model.gguf", n_ctx=2048, n_threads=4, verbose=False)
response = llm.create_chat_completion(messages=trimmed_history, max_tokens=512)
reply = response["choices"][0]["message"]["content"]

history.append({"role": "assistant", "content": reply})

with open(history_file, "w") as f:
    json.dump(history, f, indent=2)

summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
if summary_path:
    with open(summary_path, "w") as f:
        f.write(f"### You:\n> {prompt}\n\n### Assistant:\n> {reply}\n")

print("\n--- RESPONSE ---\n" + reply)
EOF

echo "Saving updated chat history to branch..."
cd memory
git config user.name "GitHub Actions LLM"
git config user.email "actions@github.com"
git add history.json
git commit -m "Chat turn: $(date -u +'%Y-%m-%d %H:%M:%S UTC')" || echo "No changes to commit"
git push origin chat-history