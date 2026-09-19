# Copilot Instructions

## Before Coding

1. Read `AGENTS.md` before making changes.
2. Inspect the existing project structure and `pubspec.yaml`.
3. Check the current package documentation/API before using any AI package.
4. Do not invent, assume, or use outdated APIs.

## Architecture

Follow the Clean Architecture defined in `AGENTS.md`:

```text
Presentation → Domain → Data
```

* Keep business logic out of widgets.
* Use Cubit/BLoC for presentation state.
* Use dependency injection.
* Keep LLM and RAG implementations behind abstractions.
* Do not tightly couple Domain or Presentation to `flutter_gemma`, SQLite, or LiteRT-LM.

## AI Requirements

The application must work **100% offline at runtime**.

Current stack:

* Flutter
* `flutter_gemma`
* `flutter_gemma_mediapipe`
* `flutter_gemma_rag_sqlite`
* Gemma 3 270M IT as the initial SLM

Do not introduce cloud AI APIs, remote inference, or backend dependencies.

Model files must not be committed to Git.

## Development Approach

Implement the project incrementally:

```text
Phase 1 → Local SLM
Phase 2 → Embeddings
Phase 3 → Vector Store
Phase 4 → Document Ingestion
Phase 5 → RAG + SLM
Phase 6 → Testing & Optimization
```

**Only implement the requested phase.**

Do not implement RAG during Phase 1.

## Code Quality

* Prefer simple, readable, maintainable code.
* Follow existing project conventions.
* Use meaningful names.
* Keep classes focused on one responsibility.
* Avoid unnecessary abstractions and dependencies.
* Do not duplicate logic.
* Add tests for important business logic and services.
* Handle errors explicitly.
* Consider memory usage and performance for on-device AI.

## Package/API Changes

Before adding or changing a dependency:

1. Verify the current package version.
2. Verify the current API/documentation.
3. Use the supported API rather than deprecated examples.
4. Keep dependency changes minimal.

If an API is unclear, **stop and verify it rather than guessing**.

## Testing

After implementation:

```text
flutter analyze
flutter test
```

Fix issues introduced by the change before considering the task complete.

## Git

* Do not commit model files.
* Do not commit secrets or API keys.
* Keep changes focused on the requested task.
* Do not modify unrelated files without a reason.

## Important Rule

**Do not make architectural decisions that conflict with `AGENTS.md`.**

If a requested change requires a significant architecture change, explain the impact before implementing it.
