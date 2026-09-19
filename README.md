# SLM AI Chatbot

This Android and iOS Flutter app is a generic offline document RAG system that
runs Gemma and retrieval entirely on the device.

## Local RAG question answering

The **Run Local RAG Question Answering** button loads
`assets/knowledge_base/documents.json`, validates and indexes generic knowledge
documents, retrieves relevant documents for a Wi-Fi question, builds a
deterministic local context and prompt, then generates an answer with Gemma 3
270M. The current sample documents contain technical error information, but the
schema supports guides, FAQs, manuals, procedures, and articles. Vectors are
stored in the app-support directory as
`technical_support_rag.db`. Re-indexing uses deterministic document IDs, so the
vector store replaces existing records instead of creating duplicates.

On its first use, the app downloads the 256-token EmbeddingGemma 300M LiteRT
model and SentencePiece tokenizer from `litert-community`. This is a one-time
model installation; embedding generation, SQLite storage, and similarity
retrieval are all local thereafter. Supply `HUGGING_FACE_TOKEN` with
`--dart-define` only if the model host requires authentication. Model files are
not committed to this repository.
