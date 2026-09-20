# SLM AI Chatbot

This Android and iOS Flutter app is a generic offline document RAG system that
runs Gemma and retrieval entirely on the device.

## Local chat

The app starts with a reusable, white-label offline chat interface. It shows
local model download/loading state, streams accumulated answers, supports retry,
and can show retrieved local source titles. The chat only depends on domain
interfaces; Gemma, embeddings, and SQLite remain behind data-layer adapters.
The model must be ready before sending a message.

## Retrieval evaluation

In debug builds, **Run Retrieval Evaluation (Debug)** indexes the bundled
knowledge base and evaluates retrieval only against
`assets/evaluation/retrieval_cases.json`. It reports per-case pass/fail status,
the no-known-match classification for unrelated questions, and Hit Rate@1 and
Hit Rate@3. It does not call the generation model or change retrieval behavior.

On its first use, the app downloads the 256-token EmbeddingGemma 300M LiteRT
model and SentencePiece tokenizer from `litert-community`. This is a one-time
model installation; embedding generation, SQLite storage, and similarity
retrieval are all local thereafter. Supply `HUGGING_FACE_TOKEN` with
`--dart-define` only if the model host requires authentication. Model files are
not committed to this repository.
