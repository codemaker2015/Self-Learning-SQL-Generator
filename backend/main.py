"""
SQL Query Assistant Backend
Azure OpenAI + asyncpg MCP + PostgreSQL (pgvector)
"""

import os
import json
import asyncio
from uuid import UUID
from typing import Optional

import asyncpg
from fastapi import FastAPI, BackgroundTasks, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from openai import AsyncAzureOpenAI

# ─── Config ──────────────────────────────────────────────────────────────────

AZURE_OPENAI_ENDPOINT   = os.getenv("AZURE_OPENAI_ENDPOINT")
AZURE_OPENAI_API_KEY    = os.getenv("AZURE_OPENAI_API_KEY")
AZURE_OPENAI_API_VERSION = os.getenv("AZURE_OPENAI_API_VERSION", "2024-08-01-preview")
AZURE_CHAT_DEPLOYMENT    = os.getenv("AZURE_CHAT_DEPLOYMENT", "gpt-4o")
AZURE_EMBED_DEPLOYMENT   = os.getenv("AZURE_EMBED_DEPLOYMENT", "text-embedding-3-small")

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:password@localhost:5432/sqlassistant"
)

# Target database (the one users query against — separate from feedback store)
TARGET_DATABASE_URL = os.getenv("TARGET_DATABASE_URL", DATABASE_URL)

# ─── App setup ───────────────────────────────────────────────────────────────

app = FastAPI(title="SQL Query Assistant")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

azure_client: AsyncAzureOpenAI = None
feedback_pool: asyncpg.Pool = None
target_pool: asyncpg.Pool = None


@app.on_event("startup")
async def startup():
    global azure_client, feedback_pool, target_pool

    azure_client = AsyncAzureOpenAI(
        azure_endpoint=AZURE_OPENAI_ENDPOINT,
        api_key=AZURE_OPENAI_API_KEY,
        api_version=AZURE_OPENAI_API_VERSION,
    )

    feedback_pool = await asyncpg.create_pool(DATABASE_URL, min_size=2, max_size=10)
    target_pool   = await asyncpg.create_pool(TARGET_DATABASE_URL, min_size=2, max_size=10)

    async with feedback_pool.acquire() as conn:
        await conn.execute("CREATE EXTENSION IF NOT EXISTS vector")
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS sql_query_feedback (
                id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_input        TEXT NOT NULL,
                generated_sql     TEXT NOT NULL,
                corrected_sql     TEXT,
                correction_reason TEXT DEFAULT '',
                feedback          SMALLINT DEFAULT 0,
                user_comment      TEXT DEFAULT '',
                schema_context    TEXT,
                embedding         vector(1536),
                execution_success BOOLEAN,
                created_at        TIMESTAMPTZ DEFAULT now(),
                updated_at        TIMESTAMPTZ DEFAULT now()
            )
        """)
        await conn.execute("""
            CREATE INDEX IF NOT EXISTS idx_embedding
            ON sql_query_feedback
            USING ivfflat (embedding vector_cosine_ops)
            WITH (lists = 10)
        """)


@app.on_event("shutdown")
async def shutdown():
    if feedback_pool:
        await feedback_pool.close()
    if target_pool:
        await target_pool.close()


# ─── Models ──────────────────────────────────────────────────────────────────

class QueryRequest(BaseModel):
    user_input: str
    schema_context: str

class FeedbackRequest(BaseModel):
    query_id: str
    feedback: int          # 1=👍, -1=👎
    user_comment: str = ""

class ExecuteRequest(BaseModel):
    query_id: str
    sql: str               # The SQL to actually run (may be corrected SQL)


# ─── Embedding ───────────────────────────────────────────────────────────────

async def get_embedding(text: str) -> list[float]:
    resp = await azure_client.embeddings.create(
        model=AZURE_EMBED_DEPLOYMENT,
        input=text,
    )
    return resp.data[0].embedding


# ─── Few-shot retrieval ───────────────────────────────────────────────────────

async def fetch_similar_examples(embedding: list[float], top_k: int = 5) -> list[dict]:
    vec_str = "[" + ",".join(str(x) for x in embedding) + "]"
    async with feedback_pool.acquire() as conn:
        rows = await conn.fetch(f"""
            SELECT
                user_input,
                COALESCE(corrected_sql, generated_sql) AS final_sql,
                correction_reason,
                feedback
            FROM sql_query_feedback
            WHERE feedback = 1
               OR (feedback = -1 AND corrected_sql IS NOT NULL)
            ORDER BY embedding <=> '{vec_str}'::vector
            LIMIT {top_k}
        """)
    return [dict(r) for r in rows]


# ─── Prompt builder ──────────────────────────────────────────────────────────

def build_messages(user_input: str, schema: str, examples: list[dict]) -> list[dict]:
    parts = []
    for ex in examples:
        note = ""
        if ex["feedback"] == -1 and ex.get("correction_reason"):
            note = f"\n  -- Fixed because: {ex['correction_reason']}"
        parts.append(f"User: {ex['user_input']}\nSQL: {ex['final_sql']}{note}")

    examples_block = "\n---\n".join(parts) if parts else "No approved examples yet."

    system = f"""You are a precise SQL expert for PostgreSQL.

Database schema:
{schema}

Approved past query examples (use as style reference):
{examples_block}

Rules:
- Output ONLY the raw SQL query. No markdown, no explanation, no code fences.
- Never use SELECT * — always name columns explicitly.
- Use PostgreSQL syntax exclusively.
- Match column and table names exactly as in the schema."""

    return [
        {"role": "system", "content": system},
        {"role": "user",   "content": user_input},
    ]


# ─── SQL Generation ──────────────────────────────────────────────────────────

@app.post("/generate-sql")
async def generate_sql(req: QueryRequest):
    embedding = await get_embedding(req.user_input)
    examples  = await fetch_similar_examples(embedding)
    messages  = build_messages(req.user_input, req.schema_context, examples)

    resp = await azure_client.chat.completions.create(
        model=AZURE_CHAT_DEPLOYMENT,
        messages=messages,
        temperature=0,
    )
    sql = resp.choices[0].message.content.strip()
    # Strip accidental markdown fences
    if sql.startswith("```"):
        sql = "\n".join(sql.split("\n")[1:])
    if sql.endswith("```"):
        sql = "\n".join(sql.split("\n")[:-1])
    sql = sql.strip()

    vec_str = "[" + ",".join(str(x) for x in embedding) + "]"
    async with feedback_pool.acquire() as conn:
        row = await conn.fetchrow("""
            INSERT INTO sql_query_feedback
                (user_input, generated_sql, schema_context, embedding)
            VALUES ($1, $2, $3, $4::vector)
            RETURNING id
        """, req.user_input, sql, req.schema_context, vec_str)

    return {"query_id": str(row["id"]), "sql": sql}


# ─── Query Execution ─────────────────────────────────────────────────────────

@app.post("/execute-sql")
async def execute_sql(req: ExecuteRequest):
    """
    Executes the SQL against the target database.
    Returns rows as list-of-dicts plus column metadata.
    Read-only guard: only SELECT statements are allowed.
    """
    sql_upper = req.sql.strip().upper()
    if not sql_upper.startswith("SELECT"):
        raise HTTPException(
            status_code=400,
            detail="Only SELECT queries are permitted for execution."
        )

    try:
        async with target_pool.acquire() as conn:
            # Hard row cap to prevent UI meltdown
            capped_sql = f"SELECT * FROM ({req.sql.rstrip().rstrip(';')}) __q LIMIT 500"
            rows = await conn.fetch(capped_sql)

        if not rows:
            result = {"columns": [], "rows": [], "row_count": 0}
        else:
            columns = list(rows[0].keys())
            data    = [
                {col: (str(v) if not isinstance(v, (int, float, bool, type(None))) else v)
                 for col, v in zip(columns, row)}
                for row in rows
            ]
            result = {"columns": columns, "rows": data, "row_count": len(data)}

        # Mark execution success on the feedback record
        async with feedback_pool.acquire() as conn:
            await conn.execute("""
                UPDATE sql_query_feedback
                SET execution_success = TRUE, updated_at = now()
                WHERE id = $1
            """, UUID(req.query_id))

        return {"success": True, **result}

    except Exception as e:
        async with feedback_pool.acquire() as conn:
            await conn.execute("""
                UPDATE sql_query_feedback
                SET execution_success = FALSE, updated_at = now()
                WHERE id = $1
            """, UUID(req.query_id))
        raise HTTPException(status_code=422, detail=str(e))


# ─── Feedback ────────────────────────────────────────────────────────────────

@app.post("/feedback")
async def submit_feedback(req: FeedbackRequest, background_tasks: BackgroundTasks):
    async with feedback_pool.acquire() as conn:
        await conn.execute("""
            UPDATE sql_query_feedback
            SET feedback = $1, user_comment = $2, updated_at = now()
            WHERE id = $3
        """, req.feedback, req.user_comment, UUID(req.query_id))

    if req.feedback == -1:
        background_tasks.add_task(correct_query_bg, req.query_id, req.user_comment)

    return {"status": "ok"}


# ─── Correction (background) ─────────────────────────────────────────────────

async def correct_query_bg(query_id: str, user_comment: str):
    async with feedback_pool.acquire() as conn:
        row = await conn.fetchrow("""
            SELECT user_input, generated_sql, schema_context
            FROM sql_query_feedback WHERE id = $1
        """, UUID(query_id))

    if not row:
        return

    user_input = row["user_input"]
    bad_sql    = row["generated_sql"]
    schema     = row["schema_context"]

    if user_comment.strip():
        feedback_section = f"""User feedback on what's wrong:
"{user_comment}"

Use this feedback as the primary signal for what to fix."""
    else:
        feedback_section = """No user comment was provided.
Infer what is likely wrong by carefully re-reading the question and schema."""

    prompt = f"""A SQL query was rejected by a user.

User's original question:
{user_input}

Database schema:
{schema}

Incorrect SQL:
{bad_sql}

{feedback_section}

Respond in exactly this format (no extra text):
REASON: <one sentence — what was wrong>
CORRECTED_SQL: <fixed SQL only, no markdown>"""

    client = AsyncAzureOpenAI(
        azure_endpoint=AZURE_OPENAI_ENDPOINT,
        api_key=AZURE_OPENAI_API_KEY,
        api_version=AZURE_OPENAI_API_VERSION,
    )

    resp = await client.chat.completions.create(
        model=AZURE_CHAT_DEPLOYMENT,
        messages=[
            {"role": "system", "content": "You are a SQL debugging expert. Fix SQL queries based on user feedback."},
            {"role": "user",   "content": prompt},
        ],
        temperature=0,
    )

    text      = resp.choices[0].message.content
    reason    = text.split("REASON:")[-1].split("CORRECTED_SQL:")[0].strip()
    corrected = text.split("CORRECTED_SQL:")[-1].strip()
    if corrected.startswith("```"):
        corrected = "\n".join(corrected.split("\n")[1:])
    if corrected.endswith("```"):
        corrected = "\n".join(corrected.split("\n")[:-1])
    corrected = corrected.strip()

    async with feedback_pool.acquire() as conn:
        await conn.execute("""
            UPDATE sql_query_feedback
            SET corrected_sql = $1, correction_reason = $2, updated_at = now()
            WHERE id = $3
        """, corrected, reason, UUID(query_id))


# ─── Correction status poll ──────────────────────────────────────────────────

@app.get("/correction/{query_id}")
async def get_correction(query_id: str):
    """Frontend polls this after submitting 👎 to get the corrected SQL."""
    async with feedback_pool.acquire() as conn:
        row = await conn.fetchrow("""
            SELECT corrected_sql, correction_reason
            FROM sql_query_feedback WHERE id = $1
        """, UUID(query_id))

    if not row or not row["corrected_sql"]:
        return {"ready": False}

    return {
        "ready":             True,
        "corrected_sql":     row["corrected_sql"],
        "correction_reason": row["correction_reason"],
    }


# ─── History ─────────────────────────────────────────────────────────────────

@app.get("/history")
async def get_history(limit: int = 20):
    async with feedback_pool.acquire() as conn:
        rows = await conn.fetch("""
            SELECT id, user_input, generated_sql, corrected_sql,
                   feedback, user_comment, correction_reason,
                   execution_success, created_at
            FROM sql_query_feedback
            ORDER BY created_at DESC
            LIMIT $1
        """, limit)
    return [
        {**dict(r), "id": str(r["id"]), "created_at": r["created_at"].isoformat()}
        for r in rows
    ]
