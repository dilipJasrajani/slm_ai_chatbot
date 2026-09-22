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

## AI request flow

```text
User
 ↓
ChatController
 ↓
AskQuestionUseCase
 ↓
ChatIntentRouter
 ├── CHAT
 │    ↓
 │   ConversationalPromptBuilder
 │    ↓
 │   LocalLlmService
 │    ↓
 │   Qwen3
 │
 └── KNOWLEDGE
      ↓
   RetrievalQueryBuilder
      ↓
   RagRepository
      ↓
   EmbeddingGemma + SQLite vector search
      ↓
   RetrievedKnowledgeRelevance
      ↓
   DocumentContextBuilder
      ↓
   RagPromptBuilder
      ↓
   LocalLlmService
      ↓
   Qwen3
```

`ChatController` turns the UI event and streamed answer into presentation
state. `AskQuestionUseCase` is the route-first orchestration point: both
branches use the generic local LLM service, while only the KNOWLEDGE branch
retrieves and grounds context. A successful completed answer is added to
short-term conversation history before the final UI state is shown.

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

## Presentation and application composition

```text
main.dart
    ↓
MyApp
    ↓
AiChatPage
    ↓
ChatController
    ↓
AskQuestionUseCase
    ↓
LLM / RAG
```

`main.dart` is the startup entry point: it initializes Flutter and the local AI
runtime, creates application dependencies, then calls `runApp`. `app/app.dart`
is the application shell, and `app/app_dependencies.dart` is the composition
root that wires shared runtime instances and interfaces to implementations.

Change chat UI, interaction, scrolling, animations, and message rendering in
`features/chat/presentation/ai_chat_page.dart`. `ChatController` in the same
folder owns presentation state and turns UI events and use-case streams into
`ChatState` updates. `AskQuestionUseCase` remains responsible for chat request
orchestration.

Change white-label chat text, source-display behavior, history limit, and UI
settings in `features/chat/presentation/ai_chat_configuration.dart`.
`AiChatTheme` contains visual customization such as colors, spacing, bubbles,
and avatar styling; `AiChatConfiguration` contains chat text and behavior
configuration. `chat_models.dart` contains only transient `ChatMessage` and
`ChatState` presentation models.

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
