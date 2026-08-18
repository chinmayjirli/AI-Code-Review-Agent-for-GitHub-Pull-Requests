# AI Code Review Agent for GitHub Pull Requests

An automated, production-shaped code review service built with **Spring Boot 3.3.2**, **Java 17**, and the **Anthropic Claude API**. The service listens for real-time GitHub `pull_request` webhook events, authenticates as a registered GitHub App, fetches unified diffs alongside surrounding source code context, analyzes the changes using Claude (`claude-3-5-sonnet-latest`), and automatically posts structured inline code comments and executive review summaries back to the Pull Request.

Functioning as a fast, automated first-pass reviewer, this agent catches security vulnerabilities, edge-case bugs, resource leaks, and architectural flaws before human engineers review the code — reducing review turnaround time while keeping API costs predictable.

---

## 📐 System Architecture

```mermaid
flowchart TD
    subgraph External Systems
        GH_WH[GitHub Webhook Event]
        GH_API[GitHub REST API]
        CLAUDE[Anthropic Claude API]
    end

    subgraph Spring Boot Backend
        subgraph Web Layer
            Filter[GitHubWebhookSignatureFilter<br/><i>HMAC-SHA256 Timing-Safe Check</i>]
            Wrapper[CachedBodyRequestWrapper<br/><i>Multi-Read Servlet Stream</i>]
            Ctrl[WebhookController<br/><i>POST /webhook/github</i>]
        end

        subgraph Async Processing & Queueing
            Exec[ThreadPoolTaskExecutor<br/><i>reviewExecutor Pool</i>]
        end

        subgraph Core Services Layer
            AuthCache[InstallationTokenCache<br/><i>5-min Expiry Buffer</i>]
            AuthService[GitHubAppAuthService<br/><i>RS256 JWT & Token Exchange</i>]
            Reconcile[JobReconciliationService<br/><i>SHA Dedup & Re-run Supersession</i>]
            Client[GitHubApiClient<br/><i>WebClient: Diff & File Fetch</i>]
            RepoConfig[RepoConfigService<br/><i>.reviewagent.yml Parser & Filter</i>]
            Enricher[ContextEnricher<br/><i>Full File Content Enrichment</i>]
            Prompt[PromptBuilder<br/><i>Context Windowing & JSON Schema</i>]
            ClaudeClient[ClaudeApiClient<br/><i>Messages API Call & JSON Parser</i>]
            CostCalc[CostCalculator<br/><i>Token Counting & USD Pricing</i>]
            Publisher[ReviewPublisher<br/><i>Line Validation & 422 Fallback</i>]
        end

        subgraph Persistence Layer
            DB[(PostgreSQL / H2<br/><i>ReviewJob Table</i>)]
        end
    end

    %% Flow connections
    GH_WH -->|POST /webhook/github| Filter
    Filter -->|Validated| Wrapper
    Wrapper --> Ctrl
    Ctrl -->|Immediate 200 OK & Async Dispatch| Exec
    Exec -->|1. Acquire or Supersede| Reconcile
    Reconcile <-->|Query & Update Status| DB
    Exec -->|2. Get Valid Token| AuthCache
    AuthCache -->|Mint JWT if Expired| AuthService
    AuthService -->|POST /app/installations/.../access_tokens| GH_API
    Exec -->|3. Fetch PR Diff & Metadata| Client
    Client -->|GET /repos/.../pulls/{id}| GH_API
    Exec -->|4. Load Repo Config| RepoConfig
    RepoConfig -->|Fetch .reviewagent.yml| Client
    Exec -->|5. Enrich Surrounding File Context| Enricher
    Enricher -->|GET /repos/.../contents/{path}| Client
    Exec -->|6. Construct Structured Prompt| Prompt
    Exec -->|7. Invoke Review Analysis| ClaudeClient
    ClaudeClient -->|POST /v1/messages| CLAUDE
    ClaudeClient -->|Extract Usage Tokens| CostCalc
    Exec -->|8. Validate & Publish Review| Publisher
    Publisher -->|POST /repos/.../pulls/{id}/reviews| GH_API
    Publisher -->|9. Record Final Status & Cost| DB
```

---

## 🛠️ Setup & Running

### 1. Register a GitHub App
1. Go to **GitHub Settings > Developer Settings > GitHub Apps > New GitHub App**.
2. Set **Webhook URL** to your server endpoint (or ngrok URL, e.g. `https://<subdomain>.ngrok-free.app/webhook/github`).
3. Set a **Webhook Secret** string.
4. Set permissions:
   - **Pull requests**: Read & Write (to read diffs and post review comments)
   - **Contents**: Read-only (to read repository source files and `.reviewagent.yml`)
5. Subscribe to **Pull request** events.
6. Generate a **Private Key** (`.pem`) and download it locally.
7. Install the App on your target repository.

### 2. Environment Variables

| Variable | Description | Example |
|---|---|---|
| `GITHUB_APP_WEBHOOK_SECRET` | Webhook secret string configured in GitHub App | `my-secret-123` |
| `GITHUB_APP_ID` | Numeric App ID shown in GitHub App settings | `123456` |
| `GITHUB_APP_PRIVATE_KEY_PATH` | Path to downloaded `.pem` private key file | `C:\keys\app.private-key.pem` |
| `ANTHROPIC_API_KEY` | Anthropic Claude API Key | `sk-ant-api03-...` |
| `ANTHROPIC_MODEL` | *(Optional)* Claude model ID (default: `claude-3-5-sonnet-latest`) | `claude-3-5-sonnet-latest` |

---

### 3. Run Locally (Development Mode — H2 In-Memory)

```powershell
# Set environment variables
$env:GITHUB_APP_WEBHOOK_SECRET   = "your-webhook-secret"
$env:GITHUB_APP_ID               = "123456"
$env:GITHUB_APP_PRIVATE_KEY_PATH = "C:\keys\your-app.private-key.pem"
$env:ANTHROPIC_API_KEY           = "sk-ant-..."

# Run Spring Boot app
.\mvnw.cmd spring-boot:run
```

---

### 4. Run in Production Mode (PostgreSQL via Docker Compose)

```powershell
# 1. Start PostgreSQL container
docker-compose up -d

# 2. Launch with prod Spring profile
$env:SPRING_PROFILES_ACTIVE         = "prod"
$env:SPRING_DATASOURCE_URL          = "jdbc:postgresql://localhost:5432/reviewdb"
$env:SPRING_DATASOURCE_USERNAME     = "postgres"
$env:SPRING_DATASOURCE_PASSWORD     = "postgres"
$env:GITHUB_APP_WEBHOOK_SECRET   = "your-webhook-secret"
$env:GITHUB_APP_ID               = "123456"
$env:GITHUB_APP_PRIVATE_KEY_PATH = "C:\keys\your-app.private-key.pem"
$env:ANTHROPIC_API_KEY           = "sk-ant-..."

.\mvnw.cmd spring-boot:run
```

---

## 🧠 Key Design Decisions

### 1. Timing-Safe HMAC Webhook Verification
GitHub signs every webhook request using HMAC-SHA256. To prevent timing side-channel attacks, the application uses `MessageDigest.isEqual()` to compare computed signatures in constant time. Request bodies are wrapped in a `CachedBodyRequestWrapper` to allow dual-reading of the input stream (first for security verification, second for JSON parsing).

### 2. GitHub App JWT + Installation Token Auth Flow
Authentication uses GitHub App short-lived JWTs signed with RS256 via BouncyCastle PEM parsing. JWTs are exchanged for 1-hour Installation Access Tokens. An `InstallationTokenCache` caches tokens with a 5-minute safety buffer before expiration, avoiding unnecessary JWT minting on rapid PR pushes while guaranteeing tokens never expire in mid-review.

### 3. Mid-Flight Job Supersession & Deduplication
When developers push new commits in rapid succession (`synchronize` events), continuing to review obsolete commits wastes API budget. `JobReconciliationService` tracks job lifecycle state in PostgreSQL (`PENDING`, `IN_PROGRESS`, `COMPLETED`, `SUPERSEDED`). Incoming commits trigger a bulk query marking active older jobs as `SUPERSEDED`. Workers re-check job status before diff fetch, before LLM invocation, and before posting to GitHub — ensuring outdated review comments are never posted.

### 4. 422 Position Error Fallback Strategy
GitHub's Review API rejects inline comments targeting lines outside the diff with a `422 Unprocessable Entity` status code. `ReviewPublisher` validates inline comment lines against parsed diff hunks before submission. If GitHub still returns a 422 error, `ReviewPublisher` automatically retries as a top-level review summary comment containing all findings in the markdown body — guaranteeing review feedback is delivered even when line numbers shift.

### 5. Token Usage & USD Cost Tracking
Every LLM call captures exact `input_tokens` and `output_tokens` from Anthropic API responses. `CostCalculator` computes estimated USD cost based on model pricing tiers (Sonnet, Haiku, Opus). Metrics are stored on the `ReviewJob` record and logged upon review completion for cost auditing.

---

## ⚙️ Repository Configuration (`.reviewagent.yml`)

Repositories can customize review behavior by placing a `.reviewagent.yml` file in the repository root:

```yaml
ignored_files:
  - "*.md"
  - "package-lock.json"
  - "dist/*"

custom_instructions: |
  Enforce immutability and strict NullPointer checks across service methods.

max_inline_comments: 10
```

- **`ignored_files`**: Skips lockfiles, documentation, and generated assets from review.
- **`custom_instructions`**: Appends custom coding standards directly to Claude's system prompt.
- **`max_inline_comments`**: Limits inline comment volume per PR.

---

## 🔮 What I'd Build Next

1. **Multi-Agent Specialist Review Pipeline**:
   Split reviews into parallel specialized sub-agents (e.g. a Security Agent focused on OWASP/injection flaws, a Performance Agent focused on DB queries/memory leaks, and a Style Agent) whose findings are synthesized by an aggregator agent before posting.

2. **Embedding-Based Repository Indexing (RAG)**:
   Index codebase symbols and type definitions in a vector store (e.g. pgvector) so the agent can look up definitions of referenced interfaces, structs, and utilities across un-changed repository files during context enrichment.

3. **Re-Run & Comment Resolution Reconciliation**:
   Listen for PR comment resolution events and track when suggested code fixes are committed, automatically marking previous review findings as resolved in the database.
