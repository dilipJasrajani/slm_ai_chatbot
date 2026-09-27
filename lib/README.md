# Application architecture

## Application flow

```text
User
 ↓
Chat
 ↓
Retrieval query
 ↓
EmbeddingGemma + SQLite vector search
 ↓
Grounding
 ├── relevant → RAG prompt → Qwen3
 └── not relevant → restricted conversational prompt → Qwen3
```

The application runs these components on the device. `app/` contains the
composition root: it initializes the supported local AI backends, creates the
feature dependencies, and starts the Flutter app.

## Chat request flow

1. `AiChatPage` reads the user's message and sends it to `ChatController`.
2. `ChatController` adds user and streaming assistant messages to the UI, then
   consumes `AskQuestionUseCase.stream`.
3. `AskQuestionUseCase` reads short-term conversation history, builds a
   history-aware retrieval query, searches the local RAG database, and checks
   that retrieved documents are relevant.
4. Relevant documents are converted into prompt context before the local LLM
   streams a grounded answer. With no relevant documents, a restricted
   conversational prompt is sent to the local LLM instead. Retrieval failures
   return a controlled response without generation.
5. Successful completed answers are stored with the user message in
   short-term conversation history.
6. Each streamed answer is returned to `ChatController`, which updates the
   assistant message displayed by `AiChatPage`.

## AI request flow

```text
User
 ↓
ChatController
 ↓
AskQuestionUseCase
 ↓
RetrievalQueryBuilder
 ↓
RagRepository
 ↓
EmbeddingGemma + SQLite vector search
 ↓
RetrievedKnowledgeRelevance
 ├── relevant → DocumentContextBuilder → RagPromptBuilder
 └── not relevant → ConversationalPromptBuilder (restricted)
 ↓
LocalLlmService
 ↓
Qwen3
```

`ChatController` turns the UI event and streamed answer into presentation
state. `AskQuestionUseCase` retrieves and grounds first, then makes one
generation call through the generic local LLM service if retrieval succeeds.
A successful completed answer is added to short-term conversation history
before the final UI state is shown. The legacy LLM router remains available
only to the separate debug routing evaluation, not to chat requests.

## Local AI and model lifecycle

### LLM generation

```text
Restricted conversational / RAG prompt
    ↓
LocalLlmService
    ↓
LocalLlmServiceImpl
    ↓
flutter_gemma / Qwen3
```

Both answer paths depend on the generic `LocalLlmService`. Its local
implementation creates an inference session, submits the prompt, and streams
generated output from the active local model.

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

The composer displays the configured local model label and, when available,
the initialized inference model's selected runtime backend. After local
generation finishes, each successful assistant message can show its generation
time. Grounded answer documents already returned by `AskQuestionUseCase` appear
as compact source codes and titles, without another retrieval or exposing
document content.

`AiChatConfiguration` also provides `assistantName` and an optional
`assistantAvatar` (`ImageProvider`, such as an `AssetImage` declared by the host
app). Without an image, the existing theme icon is used. `welcomeTitle`,
`welcomeMessage` (description), and `suggestions` customize the empty state.
Suggestions use the same composer send action as typed questions; the welcome
view returns whenever the conversation has no messages.

Pass `chatTheme: const AiChatTheme(primaryColor: Colors.teal, ...)` to `MyApp`
or directly to `AiChatPage` to customize the accent, user bubble, and message
text colors. The primary color also styles the send button, focused composer,
and assistant avatar; `accentColor` styles suggested-prompt outlines.
Assistant messages render directly on the chat background without a bubble;
the existing `assistantBubbleColor` setting is retained for compatibility but
does not color messages in this layout. Unspecified user text contrasts with
the user bubble, while unspecified assistant text contrasts with the chat
background. The existing light palette remains the default; in a dark host
`ThemeData`, unspecified colors come from its `ColorScheme`. Typography
inherits the host `TextTheme` (including its font family). Other surfaces,
borders, and spacing remain available through the existing `AiChatTheme`
without adding configuration fields.

Completed, non-error assistant responses show a compact Copy action that copies
only the response text (not timing or sources) and briefly confirms success.
Set `AiChatConfiguration(showCopyAction: false)` to hide it.

Completed assistant answers render Markdown paragraphs, headings, lists, inline
code, and fenced code blocks. Code blocks scroll horizontally and offer a
separate Copy action for only that block's raw code; response Copy still copies
the exact original answer, including Markdown syntax. Partial streamed answers,
user messages, and errors keep their plain-text presentation. Markdown images
show alt text rather than loading remote resources, keeping chat offline.

Only the latest completed, non-error assistant response offers Regenerate
(`showRegenerateAction: false` hides it); earlier responses can still be copied.
This reuses the original question and retrieval-first flow, streams into
the same message area, and replaces the prior answer in recent conversation
history rather than adding a turn. On failure the prior response is kept and
the existing error text is shown.

Failed requests keep their user question and show a compact Retry action
(`showRetryAction: false` hides Retry controls). Retrying reuses the existing
retrieval-first pipeline and streams into the same assistant message area
without adding another user message or a failed turn to conversation history.
A successful retry gets its normal sources, generation time, Copy, Regenerate,
and Markdown presentation. Retrying an older failure records the recovered
turn when the retry completes; existing successful turns are not rewritten.
Local model loading errors show a concise message
and offer a separate retry using the existing model manager. Knowledge
preparation failures show restart guidance; the underlying initialization
may cache a failure until the app restarts.

## Folder responsibilities

`features/chat` contains conversation behavior, conversation history, the
retrieval-first chat orchestrator, historical debug routing evaluation, and
the chat UI.

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
