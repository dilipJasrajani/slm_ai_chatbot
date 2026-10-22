# SLM AI Chatbot

This Android and iOS Flutter app is a generic offline document RAG system that
runs Gemma and retrieval entirely on the device.

## Local chat

The app starts with a reusable, white-label offline chat interface. It shows
local model download/loading state, streams accumulated answers, supports retry,
and can show retrieved local source titles. The chat only depends on domain
interfaces; Gemma, embeddings, and SQLite remain behind data-layer adapters.
The model must be ready before sending a message.

## Local knowledge-base JSON

Place JSON assets directly in `assets/knowledge_base/` and rebuild the app.
On knowledge-base preparation, the app loads all JSON files in that directory
and indexes their records in the local SQLite vector store. The bundled
`kb_mobile_v1_1.json` contributes 425 source passages and 408 linked cards
alongside 9 conversation documents.
Each record is stored as a complete JSON object for answer context, including
its nested fields. Only its non-empty `search_text` field is embedded for
similarity search when present; otherwise the entire serialized JSON record is
embedded. Other fields (including `phrasings`) are not added to an embedding
when `search_text` exists. Linked IDs are stored as data but are not
automatically followed during retrieval. The `searchable` flag is not used
to exclude records from indexing.

The existing `{"version": 1, "documents": [...]}` format remains supported.
Other files can be a JSON array of objects, an object with `entries` or
`documents` arrays, an object containing top-level arrays of records, or a
single JSON object. Each record is indexed separately; a record's `id` is
used when present, otherwise its file path and position provide an ID. Its
`title`, `name`, or `code` provides a display title when present. The complete
record, rather than only `text` or `content`, supplies answer content.
Non-object records and duplicate IDs fail ingestion explicitly.
Nested JSON is retained as text within a record rather than automatically
split into separate documents. For reliable retrieval and readable answers,
prefer small, self-contained records with stable IDs, explicit titles, and
verified factual content. Adding a new file requires rebuilding the app and
re-indexing; the embedding model must be installed before offline indexing.
For answers, the app uses the record's factual `text` (or `content`) and
source pages rather than repeating the stored JSON, retrieval phrasings, and
metadata in the model prompt. Unknown records without either field keep their
other fields as answer context. It sends at most two semantic matches to the
answer model, while retaining all fault codes explicitly requested by the user.
Search and grounded generation use the same deterministically resolved question,
not the full conversation. Explicit fault codes override older subjects and
restrict evidence to matching records; missing codes return an insufficient-
knowledge response without calling the answer model. Comparisons retain separate
records for each requested code. Follow-ups use the nearest relevant user-authored
subject, never generated assistant facts; multiple plausible faults require
clarification. Questions without codes retain semantic ranking and grounding.

Grounded prompts omit conversation history and instruct the model not to transfer
facts between faults. Fault records are also displayed as plain, selectable source
text in a collapsed-by-default, expandable section above the separately labelled
AI explanation, even when optional source titles are hidden or generation fails.
Expand this section to read original warnings and corrective measures.
Source warnings, conditions, and measures must not
be replaced by a generated summary. Model explanations remain probabilistic.
Debug-only chat diagnostics report bounded current/resolved questions, target
codes, retrieved IDs and scores, selected IDs, and history inclusion; production
builds do not emit these diagnostics.
The app saves a fingerprint of the bundled JSON and embedding model alongside
the SQLite database. On later launches it opens the existing index and
restores exact-code lookup without re-embedding documents. Editing the KB,
changing the embedding model, or deleting the database triggers a full rebuild.

## Select a local inference model

The default inference model is **Gemma 3 1B IT** from
`assets/models/gemma3-1b-it.litertlm`. Supply this file locally (it is ignored
by Git) before building. Flutter bundles it into the app, then copies it into
local model storage on first launch. Allow room for both copies on the device.
No inference-model download is needed for Gemma.

To use the existing Qwen3 0.6B network-installed model instead, set
`LocalModelConfiguration.active = qwen3` in
`lib/features/model/data/local_model_configuration.dart`, then restart the app.
Set it back to `gemma3` to use the bundled model. That one selector controls
installation, model type, chat label, and model-specific output processing.
Switching to Qwen3 requires a one-time download if it has not been installed.
The RAG embedding model is still downloaded separately on first use unless
already installed; bundling Gemma alone does not make a fresh RAG installation
entirely offline.

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

## Intent routing evaluation

In debug builds, **Run Routing Evaluation (Debug)** evaluates the bundled
historical router dataset in `assets/evaluation/chat_intent_cases.json` using
an experimental local model-backed router. It reports accuracy plus average
and maximum routing latency for the current device/session. The production
chat path does not use this router: it always retrieves and checks grounding
before building either a RAG prompt or a restricted conversational prompt.
Running the debug evaluation does not change chat or RAG retrieval behavior.
