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

## Chat request flow

1. `AiChatPage` reads the user's message and sends it to `ChatController`.
2. `ChatController` adds user and streaming assistant messages to the UI, then
   consumes `AskQuestionUseCase.stream`.
3. `AskQuestionUseCase` reads short-term conversation history and routes the
   request as CHAT or KNOWLEDGE.
4. CHAT requests build a conversational prompt and stream the local LLM.
5. KNOWLEDGE requests build a history-aware retrieval query, search the local
   RAG database, and check that the retrieved documents are relevant.
6. Relevant documents are converted into prompt context before the local LLM
   streams the grounded answer. Retrieval failures and ungrounded requests
   return their existing controlled responses without generation.
7. Successful completed answers are stored with the user message in
   short-term conversation history.
8. Each streamed answer is returned to `ChatController`, which updates the
   assistant message displayed by `AiChatPage`.

## Local AI and model lifecycle

### LLM generation

```text
Chat / RAG
    ↓
LocalLlmService
    ↓
LocalLlmServiceImpl
    ↓
flutter_gemma / Qwen3
```

Chat and RAG depend on the generic `LocalLlmService`. Its local implementation
creates an inference session, submits the prompt, and streams generated output
from the active local model.

### Output processing

```text
Qwen3 output
    ↓
Qwen3OutputChannelParser
    ↓
clean assistant text
```

`LocalLlmServiceImpl` sends every raw streamed chunk through
`Qwen3OutputChannelParser`. The parser contains the Qwen3-specific channel
protocol handling; callers receive only the resulting assistant text.

### Model lifecycle

```text
LocalModelManager
    ↓
LocalModelRepository
    ↓
LocalModelRepositoryImpl
```

`LocalModelManager` coordinates download, loading, readiness, and error
status. `LocalModelRepositoryImpl` performs the current local Qwen3 install
and active-model loading. The composition root shares that loaded model with
the local LLM service without making chat or RAG code depend on the model SDK.

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
