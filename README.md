# SLM AI Chatbot

This Android and iOS Flutter app runs Gemma and RAG retrieval entirely on the
device.

## Local RAG proof of concept

The **Run Local RAG Proof of Concept** button indexes three technical-support
documents and retrieves the best match for `The device cannot connect to the
network.`. Vectors are stored in the app-support directory as
`technical_support_rag.db`.

On its first use, the app downloads the 256-token EmbeddingGemma 300M LiteRT
model and SentencePiece tokenizer from `litert-community`. This is a one-time
model installation; embedding generation, SQLite storage, and similarity
retrieval are all local thereafter. Supply `HUGGING_FACE_TOKEN` with
`--dart-define` only if the model host requires authentication. Model files are
not committed to this repository.
