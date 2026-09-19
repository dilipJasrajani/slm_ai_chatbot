# AGENTS.md

## Project

This is a **100% offline Flutter AI chatbot** for Android and iOS.

The app uses:

* **On-device SLM** for text generation
* **Local RAG** for retrieving relevant knowledge
* No backend/API/network dependency at runtime

Initial use case: technical support chatbot that answers questions using a local knowledge base of error codes, causes, solutions, and related information.

---

## Architecture

Use **Clean Architecture**:

```text
Presentation
    ↓
Domain
    ↓
Data
```

Recommended structure:

```text
lib/
├── core/
├── domain/
│   ├── entities/
│   ├── repositories/
│   └── usecases/
├── data/
│   ├── repositories/
│   ├── llm/
│   ├── embeddings/
│   └── rag/
└── presentation/
    └── chat/
```

Use **BLoC/Cubit** for presentation state management and dependency injection where appropriate.

---

## AI Stack

Use:

* `flutter_gemma`
* `flutter_gemma_mediapipe`
* `flutter_gemma_rag_sqlite`

Initial model:

```text
Gemma 3 270M IT
litert-community/gemma-3-270m-it
```

The model must run **locally on the device**.

Keep the LLM behind an abstraction such as:

```dart
abstract class LlmRepository {
  Stream<String> generateResponse(String prompt);
}
```

Do not couple Domain or Presentation directly to `flutter_gemma`.

---

## RAG

RAG will use:

```text
Documents
   ↓
Chunking
   ↓
Embeddings
   ↓
SQLite / sqlite-vec
   ↓
Similarity Search
   ↓
Relevant Context
   ↓
Local SLM
   ↓
Answer
```

Use `EmbeddingGemma` through the supported `flutter_gemma` ecosystem for embeddings.

Keep RAG behind repository/service abstractions.

---

## Development Rules

1. **Offline first** — no API/server dependency.
2. Follow **Clean Architecture**.
3. Keep AI/LLM implementation replaceable.
4. Keep RAG implementation replaceable.
5. Do not put business logic in widgets.
6. Prefer small, testable classes.
7. Use dependency injection.
8. Write unit tests for domain logic and important services.
9. Handle model loading, errors, cancellation, and memory carefully.
10. Do not commit model files to Git.
11. Avoid unnecessary dependencies.
12. Do not over-engineer the project.

---

## Coding Agent Rules

Before making changes:

1. Read this file.
2. Read `CODE_AGENT.md`.
3. Inspect the existing project and `pubspec.yaml`.
4. Check the **current package documentation/API** before using `flutter_gemma` APIs.
5. Never invent package APIs or assume outdated examples.

Implement only the requested phase/task.

Do **not** implement RAG when working on the initial local-LLM phase.

---

## Current Development Order

```text
Phase 1 → Local SLM
Phase 2 → Embeddings
Phase 3 → Local Vector Store
Phase 4 → Document Ingestion
Phase 5 → RAG + SLM
Phase 6 → Testing & Optimization
```

Each phase should work before moving to the next.

## Definition of Done

A feature is complete when:

* It works fully offline.
* It follows the architecture.
* It is testable.
* No unnecessary dependencies are introduced.
* `flutter analyze` passes.
* Tests pass.
* Existing functionality is not broken.
