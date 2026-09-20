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

## Local RAG

### Knowledge ingestion

```text
documents.json
    ↓
JsonDocumentSource
    ↓
KnowledgeDocument
    ↓
IngestDocumentsUseCase
    ↓
EmbeddingGemma
    ↓
SQLite vector storage
```

`JsonDocumentSource` loads the asset into generic `KnowledgeDocument` values.
`IngestDocumentsUseCase` creates stable searchable text for each document and
passes it to `RagRepository`. The Flutter Gemma repository uses
EmbeddingGemma to create vectors and persists them in its local SQLite vector
store, alongside metadata needed to reconstruct the original document.

### Question retrieval

```text
User question + conversation context
    ↓
RetrievalQueryBuilder
    ↓
EmbeddingGemma
    ↓
vector search
    ↓
RagSearchResult
    ↓
RetrievedKnowledgeRelevance
    ↓
DocumentContextBuilder
```

`RetrievalQueryBuilder` includes the current question and existing
conversation context in the search query. The repository delegates query
embedding and vector search to the active EmbeddingGemma/vector-store runtime,
then returns `RagSearchResult` values. `RetrievedKnowledgeRelevance` applies
the existing grounding rules before `DocumentContextBuilder` formats documents
that are safe to use.

### Answer generation

```text
Context + question + supported history
    ↓
RagPromptBuilder
    ↓
LocalLlmService
    ↓
Qwen3
    ↓
answer
```

`RagPromptBuilder` owns the unchanged grounded-answer prompt. The Chat
orchestrator sends that prompt through the generic `LocalLlmService`; Qwen3
generates the answer. EmbeddingGemma is used only for ingestion and retrieval,
not answer generation.

## Folder responsibilities

`features/chat` contains conversation behavior, CHAT/KNOWLEDGE routing,
conversation history, chat evaluation, and the chat UI.

`features/llm` contains the generic local-generation abstraction and the
Qwen3 generation implementation, including Qwen3 output-channel parsing.

`features/rag` contains knowledge documents, document ingestion, local
embeddings, SQLite vector retrieval, grounding, RAG prompts, and retrieval
evaluation. Its `evaluation/` folder is non-runtime retrieval tooling, and its
`support/` folder contains the inactive proof-of-concept
screen and helper kept for reference.

`features/model` contains Qwen3 model downloading, installation, lifecycle
management, and model status.

Within each feature, `domain` holds feature rules and abstractions, `data`
holds local infrastructure implementations, and `presentation` holds Flutter
UI and UI state where that feature has a UI.
