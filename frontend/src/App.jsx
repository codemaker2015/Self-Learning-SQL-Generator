import { useState, useEffect, useRef, useCallback } from "react";
import "./index.css";

const API = "/api";

// ─── Utilities ───────────────────────────────────────────────────────────────

function classNames(...classes) {
  return classes.filter(Boolean).join(" ");
}

function ago(iso) {
  const d = new Date(iso);
  const s = Math.floor((Date.now() - d) / 1000);
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  return `${Math.floor(s / 3600)}h ago`;
}

// ─── Icons ───────────────────────────────────────────────────────────────────

const Icon = {
  Send: () => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/>
    </svg>
  ),
  ThumbUp: ({ filled }) => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill={filled ? "currentColor" : "none"} stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M14 9V5a3 3 0 0 0-3-3l-4 9v11h11.28a2 2 0 0 0 2-1.7l1.38-9a2 2 0 0 0-2-2.3H14z"/>
      <path d="M7 22H4a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2h3"/>
    </svg>
  ),
  ThumbDown: ({ filled }) => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill={filled ? "currentColor" : "none"} stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M10 15v4a3 3 0 0 0 3 3l4-9V2H5.72a2 2 0 0 0-2 1.7l-1.38 9a2 2 0 0 0 2 2.3H10z"/>
      <path d="M17 2h2.67A2.31 2.31 0 0 1 22 4v7a2.31 2.31 0 0 1-2.33 2H17"/>
    </svg>
  ),
  Play: () => (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
      <polygon points="5 3 19 12 5 21 5 3"/>
    </svg>
  ),
  Loader: () => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="spin">
      <path d="M21 12a9 9 0 1 1-6.219-8.56"/>
    </svg>
  ),
  Check: () => (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="20 6 9 17 4 12"/>
    </svg>
  ),
  X: () => (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
    </svg>
  ),
  History: () => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 .49-4.95"/>
    </svg>
  ),
  Database: () => (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/>
      <path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/>
    </svg>
  ),
  Zap: () => (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor">
      <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>
    </svg>
  ),
  ChevronDown: () => (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="6 9 12 15 18 9"/>
    </svg>
  ),
  Copy: () => (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="9" y="9" width="13" height="13" rx="2" ry="2"/>
      <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
    </svg>
  ),
  Wand: () => (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M15 4V2m0 14v-2M8 9H2m14 0h-2M13.8 6.2 12 4.4M5.2 13.8 3.4 12m10.4 1.8 1.8-1.8M3.4 6.2l1.8 1.8"/>
      <path d="m22 22-7-7"/>
    </svg>
  ),
};

// ─── SQL Block ────────────────────────────────────────────────────────────────

function SqlBlock({ sql, label, variant = "default" }) {
  const [copied, setCopied] = useState(false);
  const copy = () => {
    navigator.clipboard.writeText(sql);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };
  return (
    <div className={`sql-block sql-block--${variant}`}>
      <div className="sql-block__header">
        <span className="sql-block__label">{label}</span>
        <button className="copy-btn" onClick={copy} title="Copy SQL">
          {copied ? <Icon.Check /> : <Icon.Copy />}
          {copied ? "Copied" : "Copy"}
        </button>
      </div>
      <pre className="sql-block__code">{sql}</pre>
    </div>
  );
}

// ─── Results Table ────────────────────────────────────────────────────────────

function ResultsTable({ columns, rows, rowCount }) {
  if (!columns.length) {
    return <p className="results-empty">Query returned no rows.</p>;
  }
  return (
    <div className="results-wrap">
      <div className="results-meta">
        <Icon.Database />
        <span>{rowCount} row{rowCount !== 1 ? "s" : ""} returned</span>
        {rowCount === 500 && <span className="results-cap">· capped at 500</span>}
      </div>
      <div className="results-scroll">
        <table className="results-table">
          <thead>
            <tr>{columns.map(c => <th key={c}>{c}</th>)}</tr>
          </thead>
          <tbody>
            {rows.map((row, i) => (
              <tr key={i}>
                {columns.map(c => (
                  <td key={c} title={String(row[c] ?? "")}>
                    {row[c] === null ? <span className="null-val">null</span> : String(row[c])}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ─── Feedback Panel ───────────────────────────────────────────────────────────

function FeedbackPanel({ queryId, onFeedbackDone }) {
  const [state, setState] = useState("idle"); // idle | thumbsdown | submitting | done
  const [comment, setComment] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const handleThumbsUp = async () => {
    setSubmitting(true);
    await fetch(`${API}/feedback`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query_id: queryId, feedback: 1, user_comment: "" }),
    });
    setState("done");
    setSubmitting(false);
    onFeedbackDone(1, "");
  };

  const handleThumbsDown = () => setState("thumbsdown");

  const handleSubmitBad = async () => {
    setSubmitting(true);
    await fetch(`${API}/feedback`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query_id: queryId, feedback: -1, user_comment: comment }),
    });
    setState("done");
    setSubmitting(false);
    onFeedbackDone(-1, comment);
  };

  if (state === "done") return null;

  return (
    <div className="feedback-panel">
      {state === "idle" && (
        <div className="feedback-row">
          <span className="feedback-label">Was this query correct?</span>
          <button
            className="fb-btn fb-btn--up"
            onClick={handleThumbsUp}
            disabled={submitting}
            title="Looks good"
          >
            <Icon.ThumbUp /> Looks good
          </button>
          <button
            className="fb-btn fb-btn--down"
            onClick={handleThumbsDown}
            disabled={submitting}
            title="Something's wrong"
          >
            <Icon.ThumbDown /> Something's wrong
          </button>
        </div>
      )}

      {state === "thumbsdown" && (
        <div className="feedback-expanded">
          <div className="feedback-row">
            <span className="feedback-label">What's wrong? <span className="optional">(optional)</span></span>
          </div>
          <textarea
            className="feedback-textarea"
            placeholder='e.g. "wrong table used — should be orders not order_items" or "missing JOIN with customers"'
            value={comment}
            onChange={e => setComment(e.target.value)}
            rows={3}
            autoFocus
          />
          <div className="feedback-actions">
            <button
              className="fb-action fb-action--skip"
              onClick={handleSubmitBad}
              disabled={submitting}
            >
              {submitting ? <Icon.Loader /> : <Icon.X />}
              Skip &amp; correct
            </button>
            <button
              className="fb-action fb-action--send"
              onClick={handleSubmitBad}
              disabled={submitting || !comment.trim()}
            >
              {submitting ? <Icon.Loader /> : <Icon.Send />}
              Send feedback &amp; correct
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Correction Poller ────────────────────────────────────────────────────────

function CorrectionWatcher({ queryId, onReady }) {
  const [dots, setDots] = useState(".");
  const intervalRef = useRef(null);
  const pollRef    = useRef(null);

  useEffect(() => {
    // Animate dots
    intervalRef.current = setInterval(() =>
      setDots(d => d.length >= 3 ? "." : d + "."), 500);

    // Poll for correction
    pollRef.current = setInterval(async () => {
      try {
        const r = await fetch(`${API}/correction/${queryId}`);
        const data = await r.json();
        if (data.ready) {
          clearInterval(pollRef.current);
          clearInterval(intervalRef.current);
          onReady(data);
        }
      } catch (_) {}
    }, 1500);

    return () => {
      clearInterval(intervalRef.current);
      clearInterval(pollRef.current);
    };
  }, [queryId, onReady]);

  return (
    <div className="correction-waiting">
      <Icon.Wand />
      <span>Generating corrected query{dots}</span>
    </div>
  );
}

// ─── Query Card ───────────────────────────────────────────────────────────────

function QueryCard({ entry }) {
  const [feedbackGiven, setFeedbackGiven]         = useState(entry.feedback !== 0 ? entry.feedback : null);
  const [userComment, setUserComment]             = useState(entry.user_comment || "");
  const [correction, setCorrection]               = useState(
    entry.corrected_sql
      ? { corrected_sql: entry.corrected_sql, correction_reason: entry.correction_reason }
      : null
  );
  const [waitingCorrection, setWaitingCorrection] = useState(false);
  const [execResult, setExecResult]               = useState(null);
  const [execError, setExecError]                 = useState(null);
  const [executing, setExecuting]                 = useState(false);

  // The SQL to run — prefer corrected if approved
  const activeSql = correction?.corrected_sql || entry.generated_sql;

  const handleFeedbackDone = useCallback((fb, comment) => {
    setFeedbackGiven(fb);
    setUserComment(comment);
    if (fb === -1) setWaitingCorrection(true);
  }, []);

  const handleCorrectionReady = useCallback((data) => {
    setCorrection(data);
    setWaitingCorrection(false);
  }, []);

  const runSql = async (sql) => {
    setExecuting(true);
    setExecResult(null);
    setExecError(null);
    try {
      const r = await fetch(`${API}/execute-sql`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query_id: entry.id, sql }),
      });
      const data = await r.json();
      if (!r.ok) throw new Error(data.detail || "Execution failed");
      setExecResult(data);
    } catch (e) {
      setExecError(e.message);
    } finally {
      setExecuting(false);
    }
  };

  return (
    <div className={classNames(
      "qcard",
      feedbackGiven === 1 && "qcard--approved",
      feedbackGiven === -1 && "qcard--rejected"
    )}>
      {/* Question */}
      <div className="qcard__question">
        <span className="qcard__q-icon">Q</span>
        <p>{entry.user_input}</p>
        {entry.created_at && <time className="qcard__time">{ago(entry.created_at)}</time>}
      </div>

      {/* Generated SQL */}
      <SqlBlock sql={entry.generated_sql} label="Generated SQL" variant="default" />

      {/* Run button for generated SQL */}
      {!correction && (
        <div className="run-row">
          <button
            className="run-btn"
            onClick={() => runSql(entry.generated_sql)}
            disabled={executing}
          >
            {executing ? <Icon.Loader /> : <Icon.Play />}
            Run query
          </button>
        </div>
      )}

      {/* Feedback panel */}
      {feedbackGiven === null && (
        <FeedbackPanel
          queryId={entry.id}
          onFeedbackDone={handleFeedbackDone}
        />
      )}

      {/* Feedback badge */}
      {feedbackGiven === 1 && (
        <div className="fb-badge fb-badge--up">
          <Icon.ThumbUp filled /> Marked as correct
        </div>
      )}
      {feedbackGiven === -1 && !waitingCorrection && !correction && (
        <div className="fb-badge fb-badge--down">
          <Icon.ThumbDown filled />
          Marked incorrect{userComment ? ` · "${userComment}"` : ""}
        </div>
      )}

      {/* Correction loading */}
      {waitingCorrection && (
        <CorrectionWatcher
          queryId={entry.id}
          onReady={handleCorrectionReady}
        />
      )}

      {/* Corrected SQL */}
      {correction && (
        <div className="correction-block">
          <div className="correction-reason">
            <Icon.Wand />
            <span>{correction.correction_reason}</span>
          </div>
          <SqlBlock
            sql={correction.corrected_sql}
            label="Corrected SQL"
            variant="corrected"
          />
          <div className="run-row">
            <button
              className="run-btn run-btn--corrected"
              onClick={() => runSql(correction.corrected_sql)}
              disabled={executing}
            >
              {executing ? <Icon.Loader /> : <Icon.Play />}
              Run corrected query
            </button>
          </div>
        </div>
      )}

      {/* Execution result */}
      {executing && (
        <div className="exec-loading">
          <Icon.Loader /> Running query…
        </div>
      )}

      {execError && (
        <div className="exec-error">
          <Icon.X /> {execError}
        </div>
      )}

      {execResult && (
        <ResultsTable
          columns={execResult.columns}
          rows={execResult.rows}
          rowCount={execResult.row_count}
        />
      )}
    </div>
  );
}

// ─── History Sidebar ──────────────────────────────────────────────────────────

function HistorySidebar({ open, onClose, onSelect }) {
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!open) return;
    setLoading(true);
    fetch(`${API}/history?limit=30`)
      .then(r => r.json())
      .then(data => { setItems(data); setLoading(false); })
      .catch(() => setLoading(false));
  }, [open]);

  return (
    <>
      <div className={classNames("sidebar-overlay", open && "sidebar-overlay--open")} onClick={onClose} />
      <aside className={classNames("sidebar", open && "sidebar--open")}>
        <div className="sidebar__header">
          <span>Query history</span>
          <button className="sidebar__close" onClick={onClose}><Icon.X /></button>
        </div>
        {loading && <div className="sidebar__loading"><Icon.Loader /></div>}
        {!loading && items.map(item => (
          <button
            key={item.id}
            className="sidebar__item"
            onClick={() => { onSelect(item); onClose(); }}
          >
            <span className="sidebar__item-q">{item.user_input}</span>
            <div className="sidebar__item-meta">
              <span className={classNames(
                "sidebar__badge",
                item.feedback === 1 && "sidebar__badge--up",
                item.feedback === -1 && "sidebar__badge--down",
              )}>
                {item.feedback === 1 ? "✓" : item.feedback === -1 ? "✗" : "—"}
              </span>
              <time>{ago(item.created_at)}</time>
            </div>
          </button>
        ))}
        {!loading && !items.length && (
          <p className="sidebar__empty">No queries yet.</p>
        )}
      </aside>
    </>
  );
}

// ─── Main App ─────────────────────────────────────────────────────────────────

const DEFAULT_SCHEMA = `-- ⚠️  AMBIGUOUS COLUMN GUIDE — read before querying
--
--  sales.name          = product SKU snapshot at sale time
--  sales.product_name  = full product name snapshot at sale time
--  products.name       = current master SKU  (may differ from sales snapshot)
--  products.product_name = current master full name
--
--  sales.price_usd / price_inr   = ACTUAL charged price (with discount, FX at sale time)
--  products.price_usd / price_inr = CURRENT list price  (may have changed since sale)
--
--  sales.customer_name = billing entity snapshot
--  sales.end_customer  = end-user/beneficiary snapshot
--  customers.customer_name = current master billing name
--  customers.end_customer  = current master end-user name
--
--  sales_reps.name     = rep full name  (also just "name", like sales.name and products.name)

CREATE TABLE sales_reps (
    id             SERIAL PRIMARY KEY,
    name           TEXT NOT NULL,        -- rep full name
    email          TEXT UNIQUE NOT NULL,
    region         TEXT NOT NULL,        -- APAC / EMEA / AMER / LATAM
    hire_date      DATE NOT NULL,
    commission_pct NUMERIC(4,2) NOT NULL
);

CREATE TABLE products (
    id           SERIAL PRIMARY KEY,
    product_name TEXT NOT NULL,          -- full product name  ← same column exists in sales
    name         TEXT NOT NULL,          -- short SKU name     ← same column exists in sales
    category     TEXT NOT NULL,
    price_usd    NUMERIC(10,2) NOT NULL, -- current list price USD  ← same column in sales (but different value!)
    price_inr    NUMERIC(12,2) NOT NULL, -- current list price INR  ← same column in sales (but different value!)
    stock_qty    INT NOT NULL DEFAULT 0,
    is_active    BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE customers (
    id            SERIAL PRIMARY KEY,
    customer_name TEXT NOT NULL,         -- billing entity   ← also a snapshot column in sales
    end_customer  TEXT NOT NULL,         -- final recipient  ← also a snapshot column in sales
    country       TEXT NOT NULL,
    city          TEXT NOT NULL,
    account_tier  TEXT NOT NULL,         -- Gold / Silver / Bronze
    contact_email TEXT UNIQUE NOT NULL,
    phone         TEXT
);

CREATE TABLE sales (
    id             SERIAL PRIMARY KEY,
    -- Snapshot columns (point-in-time values, may differ from master tables)
    name           TEXT NOT NULL,          -- products.name at time of sale
    product_name   TEXT NOT NULL,          -- products.product_name at time of sale
    price_usd      NUMERIC(10,2) NOT NULL, -- actual charged USD (post-discount, FX at sale date)
    price_inr      NUMERIC(12,2) NOT NULL, -- actual charged INR (FX at sale date)
    discount_pct   NUMERIC(4,2)  NOT NULL DEFAULT 0,
    quantity       INT NOT NULL DEFAULT 1,
    total_usd      NUMERIC(12,2),          -- generated: price_usd * qty * (1 - discount_pct/100)
    total_inr      NUMERIC(14,2),          -- generated: price_inr * qty * (1 - discount_pct/100)
    customer_name  TEXT NOT NULL,          -- customers.customer_name snapshot (billing entity)
    end_customer   TEXT NOT NULL,          -- customers.end_customer snapshot (actual user)
    -- Foreign keys
    product_id     INT REFERENCES products(id),
    customer_id    INT REFERENCES customers(id),
    rep_id         INT REFERENCES sales_reps(id),
    -- Deal metadata
    deal_stage     TEXT NOT NULL,          -- Closed-Won / Closed-Lost / Refunded
    payment_method TEXT NOT NULL,          -- Wire / Card / UPI / Invoice / N/A
    invoice_number TEXT UNIQUE NOT NULL,
    sale_date      DATE NOT NULL,
    delivery_date  DATE,
    notes          TEXT
);

-- Convenience view joining all tables with unambiguous aliases
-- Use this for complex multi-table queries
CREATE VIEW sales_summary AS
SELECT
    s.id, s.invoice_number, s.sale_date,
    s.name              AS product_sku,
    s.product_name      AS product_full_name,
    s.price_usd         AS charged_price_usd,
    s.price_inr         AS charged_price_inr,
    s.discount_pct, s.quantity, s.total_usd, s.total_inr,
    s.customer_name     AS billing_customer,
    s.end_customer,
    c.country, c.city, c.account_tier,
    r.name              AS rep_name,
    r.region            AS rep_region,
    s.deal_stage, s.payment_method
FROM sales s
JOIN products p   ON p.id  = s.product_id
JOIN customers c  ON c.id  = s.customer_id
JOIN sales_reps r ON r.id  = s.rep_id;`;

export default function App() {
  const [userInput, setUserInput]       = useState("");
  const [schema, setSchema]             = useState(DEFAULT_SCHEMA);
  const [schemaOpen, setSchemaOpen]     = useState(false);
  const [cards, setCards]               = useState([]);
  const [loading, setLoading]           = useState(false);
  const [error, setError]               = useState(null);
  const [historyOpen, setHistoryOpen]   = useState(false);
  const inputRef                        = useRef(null);
  const bottomRef                       = useRef(null);

  const submit = async () => {
    if (!userInput.trim() || loading) return;
    setError(null);
    setLoading(true);
    const question = userInput.trim();
    setUserInput("");

    try {
      const r = await fetch(`${API}/generate-sql`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ user_input: question, schema_context: schema }),
      });
      if (!r.ok) throw new Error("Failed to generate SQL");
      const data = await r.json();
      setCards(prev => [
        ...prev,
        { id: data.query_id, user_input: question, generated_sql: data.sql, feedback: 0, created_at: new Date().toISOString() },
      ]);
      setTimeout(() => bottomRef.current?.scrollIntoView({ behavior: "smooth" }), 50);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
      setTimeout(() => inputRef.current?.focus(), 100);
    }
  };

  const loadFromHistory = (item) => {
    setCards(prev => {
      if (prev.find(c => c.id === item.id)) return prev;
      return [...prev, item];
    });
  };

  const onKeyDown = (e) => {
    if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) submit();
  };

  return (
    <div className="app">
      {/* Header */}
      <header className="header">
        <div className="header__brand">
          <span className="header__logo"><Icon.Database /></span>
          <span className="header__title">SQL Assistant</span>
          {/* <span className="header__pill">
            <Icon.Zap /> Azure OpenAI
          </span> */}
        </div>
        <button className="header__history-btn" onClick={() => setHistoryOpen(true)}>
          <Icon.History /> History
        </button>
      </header>

      <div className="layout">
        {/* Schema panel */}
        <div className={classNames("schema-panel", schemaOpen && "schema-panel--open")}>
          <button
            className="schema-toggle"
            onClick={() => setSchemaOpen(o => !o)}
          >
            <Icon.Database />
            <span>DB Schema</span>
            <span className={classNames("schema-toggle__chevron", schemaOpen && "schema-toggle__chevron--open")}>
              <Icon.ChevronDown />
            </span>
          </button>
          {schemaOpen && (
            <textarea
              className="schema-editor"
              value={schema}
              onChange={e => setSchema(e.target.value)}
              spellCheck={false}
              rows={20}
            />
          )}
        </div>

        {/* Main feed */}
        <main className="feed">
          {/* Scrollable results area */}
          <div className="feed__results">
            {error && <div className="global-error"><Icon.X /> {error}</div>}

            {/* Cards */}
            <div className="cards">
              {cards.length === 0 && !loading && (
                <div className="empty-state">
                  <span className="empty-state__icon"><Icon.Database /></span>
                  <p>Ask a question in plain English and get SQL back instantly.</p>
                  <p className="empty-state__sub">Each response can be executed, rated, and corrected — the system learns from your feedback.</p>
                </div>
              )}
              {cards.map(card => (
                <QueryCard key={card.id} entry={card} />
              ))}
              <div ref={bottomRef} />
            </div>
          </div>

          {/* Input pinned at bottom */}
          <div className="feed__input">
            <div className="input-card">
              <textarea
                ref={inputRef}
                className="main-input"
                placeholder="Ask a question in plain English…&#10;e.g. Show me top 10 customers by total order value this month"
                value={userInput}
                onChange={e => setUserInput(e.target.value)}
                onKeyDown={onKeyDown}
                rows={3}
              />
              <div className="input-footer">
                <span className="input-hint">⌘↵ to send</span>
                <button
                  className="send-btn"
                  onClick={submit}
                  disabled={!userInput.trim() || loading}
                >
                  {loading ? <><Icon.Loader /> Generating…</> : <><Icon.Send /> Generate SQL</>}
                </button>
              </div>
            </div>
          </div>
        </main>
      </div>

      <HistorySidebar
        open={historyOpen}
        onClose={() => setHistoryOpen(false)}
        onSelect={loadFromHistory}
      />
    </div>
  );
}
