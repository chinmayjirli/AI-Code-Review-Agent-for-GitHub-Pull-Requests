# Changelog & Release Notes

All notable changes and milestones for the **AI Code Review Agent** project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-08-17 — Initial Production Release

### Added

#### Phase 1: Webhook Ingestion & Security
- **HMAC-SHA256 Signature Verification Filter**: [`GitHubWebhookSignatureFilter`](file:///c:/Users/Lenovo/OneDrive/Documents/project/project 3/src/main/java/dev/codereviewer/webhook/GitHubWebhookSignatureFilter.java) performs timing-safe signature comparison (`MessageDigest.isEqual`) to reject spoofed/tampered webhooks.
- **Request Body Caching Wrapper**: [`CachedBodyRequestWrapper`](file:///c:/Users/Lenovo/OneDrive/Documents/project/project 3/src/main/java/dev/codereviewer/webhook/CachedBodyRequestWrapper.java) allows dual-reading of the HTTP input stream.
- **Fail-Fast Secret Validator**: [`StartupSecretValidator`](file:///c:/Users/Lenovo/OneDrive/Documents/project/project 3/src/main/java/dev/codereviewer/config/StartupSecretValidator.java) performs eager secret checking on boot.

#### Phase 2: GitHub App JWT Auth, Token Exchange & Diff Fetching
- **RS256 Private Key Reader**: [`GitHubAppAuthService`](file:///c:/Users/Lenovo/OneDrive/Documents/project/project 3/src/main/java/dev/codereviewer/github/auth/GitHubAppAuthService.java) parses GitHub PKCS1 PEM private keys via BouncyCastle.
- **Installation Token Exchange**: Exchanges short-lived App JWTs for 1-hour Installation Access Tokens.
- **Unified Diff Parser**: [`DiffParser`](file:///c:/Users/Lenovo/OneDrive/Documents/project/project 3/src/main/java/dev/codereviewer/github/diff/DiffParser.java) state machine parses unified diff hunks and resolves 1-based target line numbers for inline comment placement.

#### Phase 3: Context Enrichment & Structured LLM Prompts
- **Context Enrichment**: [`ContextEnricher`](file:///c:/Users/Lenovo/OneDrive/Documents/project/project 3/src/main/java/dev/codereviewer/github/context/ContextEnricher.java) retrieves full file contents at head SHA for changed files, skipping binary and deleted files.
- **Windowed Context & Character Budgets**: [`PromptBuilder`](file:///c:/Users/Lenovo/OneDrive/Documents/project/project 3/src/main/java/dev/codereviewer/llm/PromptBuilder.java) applies ±15 line context windowing around hunks and enforces prompt character budgets (`maxPromptChars`, `maxFileChars`).
- **Anthropic Messages Client**: [`ClaudeApiClient`](file:///c:/Users/Lenovo/OneDrive/Documents/project/project 3/src/main/java/dev/codereviewer/llm/ClaudeApiClient.java) invokes the Anthropic API (`claude-3-5-sonnet-latest`) and parses structured JSON findings into `ReviewFindings`.

#### Phase 4: Inline Comments & PR Review Submission
- **Markdown Comment Formatter**: [`ReviewCommentFormatter`](file:///c:/Users/Lenovo/OneDrive/Documents/project/project 3/src/main/java/dev/codereviewer/github/review/ReviewCommentFormatter.java) formats inline comments with severity badges (`🚨 HIGH`, `⚠️ MEDIUM`, `🔍 LOW`, `💡 INFO`) and ````suggestion``` code blocks.
- **Line Validation & 422 Fallback**: [`ReviewPublisher`](file:///c:/Users/Lenovo/OneDrive/Documents/project/project 3/src/main/java/dev/codereviewer/github/review/ReviewPublisher.java) validates inline comment line positions against diff hunks and automatically retries as a top-level review summary if GitHub returns a 422 position error.

#### Phase 5: Persistence, Job Deduplication, Token Caching & Cost Tracking
- **Spring Data JPA & PostgreSQL/H2**: [`ReviewJob`](file:///c:/Users/Lenovo/OneDrive/Documents/project/project 3/src/main/java/dev/codereviewer/jobs/model/ReviewJob.java) entity tracks job execution state (`PENDING`, `IN_PROGRESS`, `COMPLETED`, `FAILED`, `SUPERSEDED`), token usage, and cost estimates.
- **Job Deduplication & Re-Run Reconciliation**: [`JobReconciliationService`](file:///c:/Users/Lenovo/OneDrive/Documents/project/project 3/src/main/java/dev/codereviewer/jobs/JobReconciliationService.java) deduplicates identical SHA events and marks active older jobs as `SUPERSEDED` when new commits arrive.
- **Mid-Flight Supersession Protection**: Prevents outdated reviews from posting to GitHub if a PR moves forward during worker execution.
- **Token Cache & Cost Calculator**: [`InstallationTokenCache`](file:///c:/Users/Lenovo/OneDrive/Documents/project/project 3/src/main/java/dev/codereviewer/github/auth/InstallationTokenCache.java) caches tokens with a 5-minute safety buffer. [`CostCalculator`](file:///c:/Users/Lenovo/OneDrive/Documents/project/project 3/src/main/java/dev/codereviewer/llm/CostCalculator.java) calculates estimated USD costs.

#### Stretch Goal: Repository-Level `.reviewagent.yml` Configuration
- **Custom Repo Settings**: [`RepoConfigService`](file:///c:/Users/Lenovo/OneDrive/Documents/project/project 3/src/main/java/dev/codereviewer/config/repo/RepoConfigService.java) loads `.reviewagent.yml` from target repositories, supporting `ignored_files` glob filtering and custom system prompt guidelines.

---

### Test Metrics
- **Unit & Integration Test Suite**: 73 passing automated tests covering all security filters, JWT auth, diff parsing, WireMock API interactions, JPA persistence, prompt windowing, and YAML configuration.
