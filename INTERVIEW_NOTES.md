# Technical Interview Talking Points & Architecture Highlights

This document contains key interview talking points covering the most technically interesting architectural decisions in the **AI Code Review Agent**. Each point explains **what problem it solves**, **what would go wrong without it**, and **why the chosen approach is optimal**, formatted as natural verbal answers for technical interviews.

---

### 1. Webhook Security & Timing-Safe Signature Verification
> **The Problem:** Webhook endpoints exposed to the public internet are prime targets for payload spoofing and timing attacks. Furthermore, Spring MVC filters consume the request body input stream, which normally prevents downstream controllers from reading the JSON payload.
> 
> **Why it Matters:** Without signature validation, attackers could trigger fake reviews, spam the LLM API, and inflate costs. Without a body caching wrapper, reading the stream in a security filter causes downstream JSON deserialization to fail with a `Stream Closed` exception.
> 
> **How We Solved It:** We implemented an `OncePerRequestFilter` that uses `MessageDigest.isEqual()` for constant-time HMAC-SHA256 comparison, neutralizing timing side-channel attacks. We paired this with a `CachedBodyRequestWrapper` that buffers the raw byte stream in memory, allowing the security filter and the REST controller to safely read the request body independently.

---

### 2. Preventing Race Conditions & Waste via Mid-Flight Job Supersession
> **The Problem:** Developers frequently push multiple commits in rapid succession (e.g. fixing typos right after opening a PR). If every commit fires an asynchronous review job, workers will spend expensive LLM tokens reviewing outdated code, and late-arriving workers might post outdated inline comments over newer code.
> 
> **Why it Matters:** Without supersession handling, rapid pushes cause race conditions, duplicate GitHub comments, and wasted LLM token spend on obsolete commits.
> 
> **How We Solved It:** We designed `JobReconciliationService` backed by PostgreSQL. When a new commit arrives for a PR, a bulk `@Modifying` query updates all active (`PENDING` or `IN_PROGRESS`) jobs for that PR to `SUPERSEDED`. Worker threads check `isJobSuperseded()` at three critical checkpoints — before fetching diffs, before invoking the LLM, and before posting to GitHub API — guaranteeing out-of-date jobs abort immediately without posting stale reviews.

---

### 3. GitHub API Line Validation & 422 Unprocessable Entity Fallback
> **The Problem:** GitHub's Review API strictly requires inline review comments to target lines that actually exist in the pull request diff. If an inline comment targets an unchanged line outside the diff hunks, GitHub rejects the entire review payload with an HTTP 422 Unprocessable Entity error.
> 
> **Why it Matters:** If an LLM generates a valid finding on line 120, but line 120 is outside the changed diff hunk, submitting that comment directly causes the entire review to fail, leaving the developer with no feedback at all.
> 
> **How We Solved It:** We implemented `ReviewPublisher` which parses diff hunk line boundaries and pre-validates finding positions. Valid lines are submitted as inline comments; unattached or out-of-diff findings are automatically routed into the top-level PR summary comment body. If GitHub still returns a 422 error, `ReviewPublisher` catches the exception and gracefully falls back to posting a top-level summary review containing all findings, ensuring zero loss of review feedback.

---

### 4. Dual-Layer GitHub App Authentication & Token Caching
> **The Problem:** GitHub App authentication uses a two-tier model: short-lived RS256 JWTs signed with a private key to authenticate the App, and Installation Access Tokens to make API calls on behalf of a specific repository installation. Furthermore, GitHub issues private keys in PKCS1 format (`BEGIN RSA PRIVATE KEY`), which standard Java `KeyFactory` cannot read natively.
> 
> **Why it Matters:** Re-generating JWTs and calling GitHub's token exchange endpoint on every single webhook request adds ~300ms of latency per call and risks rate-limiting. Using standard Java crypto classes causes `InvalidKeySpecException` on GitHub's PKCS1 keys.
> 
> **How We Solved It:** We integrated BouncyCastle's `PEMParser` to read PKCS1 RSA keys natively without requiring manual OpenSSL conversions. We built `InstallationTokenCache` to cache 1-hour installation tokens in memory with a 5-minute safety buffer before expiration, eliminating redundant auth network round-trips while guaranteeing tokens never expire mid-review.

---

### 5. Token Usage Accounting & USD Cost Tracking
> **The Problem:** LLM API costs can balloon unexpectedly if large pull requests or high-frequency repositories trigger unmonitored review runs.
> 
> **Why it Matters:** Without granular cost tracking, engineering managers have no visibility into per-PR or per-repository LLM spending, making budget enforcement impossible.
> 
> **How We Solved It:** We built `CostCalculator` and integrated token usage tracking into `ClaudeApiClient`. Every LLM response extracts exact `input_tokens` and `output_tokens`, computes estimated USD cost based on model pricing tiers (Sonnet, Haiku, Opus), and persists token counts and dollar amounts directly onto the `ReviewJob` database record for auditing and operational metrics.
