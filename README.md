# SQL Assistant — Runtime Self-Learning SQL Generator

Ask questions in plain English, get SQL back instantly. Rate queries with 👍/👎, provide optional feedback on rejections, watch the system correct itself and get smarter with every interaction.

![demo](demos/demo.gif)

## Architecture

```
User question
    │
    ▼
FastAPI backend
    │
    ├─► pgvector similarity search → fetch top-k approved past queries
    │
    ├─► Prompt builder (injects few-shot examples)
    │
    ├─► Azure OpenAI GPT-4o → generates SQL
    │
    ├─► asyncpg → saves query + embedding to PostgreSQL
    │
    └─► Returns SQL to frontend
             │
             ├─► User runs it → results table shown
             │
             └─► User rates it
                    │
                    ├─► 👍 → stored as future few-shot example
                    │
                    └─► 👎 → optional comment → background correction
                                 │
                                 └─► GPT-4o corrects using feedback signal
                                          │
                                          └─► corrected SQL stored & shown
                                                   │
                                                   └─► user can run corrected SQL too
```

## Tech Stack

| Layer | Tech |
|---|---|
| Backend | FastAPI + Python 3.12 |
| LLM | Azure OpenAI GPT-4o |
| Embeddings | Azure OpenAI text-embedding-3-small |
| Database | PostgreSQL 16 + pgvector |
| DB driver | asyncpg (MCP-compatible) |
| Frontend | React 18 + Vite |

## Quick Start

### 1. Prerequisites

- Docker + Docker Compose
- Azure OpenAI resource with GPT-4o and text-embedding-3-small deployed

### 2. Configure environment

```bash
cp backend/.env.example backend/.env
# Edit backend/.env with your Azure OpenAI credentials
```

### 3. Run with Docker Compose

```bash
docker-compose up
```

- Frontend: http://localhost:5173
- Backend API: http://localhost:8000
- API docs: http://localhost:8000/docs

### 4. Manual setup (without Docker)

**Backend:**
```bash
cd backend
python -m venv venv
source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env       # Fill in your credentials
uvicorn main:app --reload
```

**PostgreSQL with pgvector:**
```bash
# Using Docker just for the DB
docker run -d \
  -e POSTGRES_PASSWORD=password \
  -e POSTGRES_DB=sqlassistant \
  -p 5432:5432 \
  pgvector/pgvector:pg16
```

**Frontend:**
```bash
cd frontend
npm install
npm run dev
```

## API Endpoints

| Method | Path | Description |
|---|---|---|
| POST | `/generate-sql` | Generate SQL from natural language |
| POST | `/execute-sql` | Run a SELECT query, get rows back |
| POST | `/feedback` | Submit 👍 or 👎 with optional comment |
| GET  | `/correction/{id}` | Poll for background correction result |
| GET  | `/history` | Recent query history |

## How It Learns

1. **First run**: No examples → raw GPT-4o generation
2. **Thumbs up**: Query stored with embedding → becomes few-shot example for similar future questions
3. **Thumbs down + comment**: LLM corrects using your feedback → corrected SQL stored alongside the rejection reason
4. **Future similar questions**: Both approved originals and corrected queries are retrieved by vector similarity and injected as few-shot examples into the prompt
5. **Over time**: The example bank grows richer → generation quality improves without any weight updates or retraining

## Two Target Databases

The system uses **two separate databases**:
- **`DATABASE_URL`** — stores query feedback, embeddings, corrections (the learning store)
- **`TARGET_DATABASE_URL`** — the database users are actually querying against

They can be the same DB, or separate ones. Set `TARGET_DATABASE_URL` to your actual application database.

## Security Notes

- Only `SELECT` statements are permitted for execution (enforced server-side)
- Results are capped at 500 rows
- Schema context is provided by the user — never auto-discovered from the target DB
- Use a read-only database user for `TARGET_DATABASE_URL` in production
