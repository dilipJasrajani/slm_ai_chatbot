# Application architecture

## Application flow

```text
User
 ↓
Chat
 ↓
Router
 ├── CHAT → Qwen3
 │
 └── KNOWLEDGE
       ↓
   EmbeddingGemma
       ↓
    Vector DB
       ↓
    Grounding
       ↓
      Qwen3
```

The application runs these components on the device. `app/` contains the
composition root: it initializes the supported local AI backends, creates the
feature dependencies, and starts the Flutter app.

## Folder responsibilities

`features/chat` contains conversation behavior, CHAT/KNOWLEDGE routing,
conversation history, chat evaluation, and the chat UI.

`features/llm` contains the generic local-generation abstraction and the
Qwen3 generation implementation, including Qwen3 output-channel parsing.

`features/rag` contains knowledge documents, document ingestion, local
embeddings, SQLite vector retrieval, grounding, RAG prompts, and retrieval
evaluation. Its `support/` folder contains the inactive proof-of-concept
screen and helper kept for reference.

`features/model` contains Qwen3 model downloading, installation, lifecycle
management, and model status.

Within each feature, `domain` holds feature rules and abstractions, `data`
holds local infrastructure implementations, and `presentation` holds Flutter
UI and UI state where that feature has a UI.
