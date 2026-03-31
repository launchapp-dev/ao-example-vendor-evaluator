# Vendor Evaluation Pipeline — Build Plan

## Overview

Multi-agent vendor evaluation pipeline — takes a vendor shortlist, researches each
vendor via web fetch (company pages, reviews, docs), scores them against weighted
criteria (pricing, features, support, security, compliance), builds comparison
matrices, and produces an executive recommendation memo with pros/cons and risk
assessment.

Uses fetch MCP for real web research, sequential-thinking for structured scoring
methodology, memory MCP for tracking evaluation history across runs, and filesystem
for all data I/O.

---

## Agents (4)

| Agent | Model | Role |
|---|---|---|
| **researcher** | claude-haiku-4-5 | Fast web research — fetches vendor websites, reviews, docs, extracts key facts |
| **scorer** | claude-sonnet-4-6 | Weighted scoring analysis — applies criteria rubric, scores each vendor, flags gaps |
| **compliance-checker** | claude-haiku-4-5 | Security and compliance review — checks certifications, data handling, red flags |
| **report-writer** | claude-sonnet-4-6 | Synthesizes all findings into comparison matrix and executive recommendation |

### MCP Servers Used by Agents

- **filesystem** — all agents read/write JSON and markdown data files
- **fetch** (`@modelcontextprotocol/server-fetch`) — researcher uses to fetch vendor websites, review sites, documentation
- **sequential-thinking** (`@modelcontextprotocol/server-sequential-thinking`) — scorer uses for multi-criteria weighted scoring methodology
- **memory** (`@modelcontextprotocol/server-memory`) — report-writer uses to store/recall historical vendor evaluations for trend comparison

---

## Workflows (2)

### 1. `evaluate-vendors` (primary — triggered per evaluation request)

Main pipeline: vendor list in -> research -> score -> compliance check -> report out.

**Phases:**

1. **parse-request** (command)
   - Script: `scripts/parse-request.sh`
   - Reads evaluation request from `config/evaluation-request.yaml`
   - Validates vendor list is non-empty and criteria weights sum to 100
   - Writes normalized request to `data/active-evaluation.json`:
     - `evaluation_id`, `category` (e.g. "CRM", "CI/CD", "Cloud Storage")
     - `vendors[]` with name and primary URL
     - `criteria[]` with name, weight, and description
     - `requirements[]` hard requirements (must-have vs nice-to-have)
   - Exit 1 if validation fails (blocks pipeline)

2. **research-vendors** (agent: researcher)
   - Reads vendor list from `data/active-evaluation.json`
   - For each vendor, uses fetch MCP to retrieve:
     - Company homepage — extract: tagline, founding year, team size signals, pricing page
     - Pricing page — extract: plan tiers, per-seat costs, enterprise pricing availability
     - Features/product page — extract: feature list, integrations, API availability
     - Documentation/changelog — extract: update frequency, API maturity signals
     - Review sites (G2, Capterra URLs if known) — extract: rating, review count, common praise/complaints
   - Output contract per vendor: `data/research/{vendor-slug}.json`
     ```json
     {
       "vendor": "Acme Corp",
       "slug": "acme-corp",
       "website": "https://acme.com",
       "overview": "One paragraph summary",
       "pricing": { "model": "per-seat", "tiers": [...], "free_tier": true/false },
       "features": ["feature1", "feature2", ...],
       "integrations": ["Slack", "Jira", ...],
       "api_available": true/false,
       "reviews_summary": { "avg_rating": 4.2, "review_count": 150, "top_praise": [...], "top_complaints": [...] },
       "last_updated": "2024-...",
       "sources_fetched": ["url1", "url2", ...]
     }
     ```
   - Writes `data/research/research-summary.json` with status per vendor (success/partial/failed)

3. **score-vendors** (agent: scorer)
   - Reads research data from `data/research/` and criteria from `data/active-evaluation.json`
   - Uses sequential-thinking to reason through scoring methodology:
     - For each vendor x criteria pair, assigns a score 1-10 with justification
     - Applies weights to produce weighted scores per criteria dimension
     - Calculates overall weighted score (0-100 scale)
   - Handles missing data: if research couldn't find pricing info, score that dimension lower and flag as "data gap"
   - Output contract per vendor: `data/scores/{vendor-slug}.json`
     ```json
     {
       "vendor": "Acme Corp",
       "criteria_scores": [
         { "criteria": "Pricing", "weight": 25, "raw_score": 7, "weighted_score": 17.5, "justification": "..." },
         ...
       ],
       "overall_score": 72.5,
       "data_gaps": ["No public pricing found", ...],
       "strengths": ["Strong API", "Good reviews"],
       "weaknesses": ["No SOC2 certification mentioned"]
     }
     ```
   - Writes `data/scores/score-matrix.json` with all vendors side-by-side

4. **check-compliance** (agent: compliance-checker)
   - Reads research from `data/research/` and hard requirements from `data/active-evaluation.json`
   - For each vendor, checks:
     - **Security certifications**: SOC2, ISO 27001, GDPR compliance mentioned on site
     - **Data handling**: where data is stored, encryption mentions, data export/deletion capabilities
     - **Vendor stability**: funding signals, team size, years in business, acquisition risk
     - **Hard requirements**: does the vendor meet all must-have requirements?
   - Each finding: `{ "area": "security", "status": "pass|fail|unknown", "detail": "..." }`
   - Decision contract: `{ "verdict": "all-clear | has-blockers | needs-more-info", "reasoning": "...", "blockers": [...] }`
   - Writes `data/compliance/{vendor-slug}.json` per vendor
   - Writes `data/compliance/compliance-summary.json`
   - **Routing:**
     - `all-clear` -> generate-report
     - `has-blockers` -> generate-report (blockers included as red flags in report)
     - `needs-more-info` -> research-vendors (rework, max 2 attempts — researcher fetches additional URLs)

5. **generate-report** (agent: report-writer)
   - Reads all data: research, scores, compliance findings
   - Uses memory MCP to check for previous evaluations in same category (trend data)
   - Generates three output files:

   **a. Comparison Matrix** — `output/comparison-matrix.md`
   - Side-by-side table: vendors as columns, criteria as rows
   - Scores with color-coded indicators (high/medium/low)
   - Data gap warnings inline
   - Hard requirement pass/fail row

   **b. Executive Recommendation** — `output/executive-recommendation.md`
   - **TL;DR**: one-sentence recommendation
   - **Recommendation**: top pick with reasoning (2-3 paragraphs)
   - **Runner-up**: second choice and when to prefer it
   - **Comparison matrix** (embedded from above)
   - **Per-vendor profiles**: 1 paragraph each with pros/cons/risk
   - **Risk assessment**: vendor risk factors (stability, lock-in, compliance gaps)
   - **Next steps**: suggested actions (request demo, negotiate pricing, run POC)

   **c. Detailed Scores** — `output/detailed-scores.md`
   - Full scoring breakdown per vendor per criteria
   - Methodology explanation
   - Data sources cited

   - Stores evaluation summary in memory MCP for future reference
   - Writes `data/history/{evaluation_id}.json` for local history tracking
   - Capabilities: writes_files, mutates_state

6. **review-report** (agent: scorer)
   - Decision contract: `{ "verdict": "approve | rework", "reasoning": "...", "issues": [...] }`
   - Sanity-checks the final report:
     - Does the recommendation align with the scores?
     - Are all vendors represented in the comparison matrix?
     - Are compliance blockers properly flagged?
     - Is the executive summary accurate and not misleading?
   - **Routing:**
     - `approve` -> done (post_success)
     - `rework` -> generate-report (max 2 attempts)

### 2. `quick-compare` (on-demand — fast 2-vendor comparison)

Lightweight comparison for quick decisions, skips deep compliance and review.

**Phases:**

1. **parse-quick** (command)
   - Reads two vendor names from `{{subject_description}}`
   - Creates minimal evaluation request with default criteria weights
   - Writes to `data/active-evaluation.json`

2. **research-and-score** (agent: scorer)
   - Combined phase: uses fetch MCP to research both vendors
   - Applies default criteria rubric (features 30, pricing 25, support 20, security 15, ease-of-use 10)
   - Produces a single comparison document
   - Writes `output/quick-comparison.md`

---

## Decision Contracts

### check-compliance verdict
```json
{
  "verdict": "all-clear | has-blockers | needs-more-info",
  "reasoning": "summary of compliance findings",
  "blockers": ["vendor X fails SOC2 requirement"],
  "unknowns": ["vendor Y pricing not publicly available"]
}
```

### review-report verdict
```json
{
  "verdict": "approve | rework",
  "reasoning": "why the report is/isn't ready",
  "issues": ["recommendation contradicts scores for vendor X"]
}
```

---

## Directory Layout

```
config/
├── evaluation-request.yaml   # Input: vendor list, criteria, weights, requirements
├── criteria-defaults.yaml    # Default criteria and weights for common categories
└── compliance-checklist.yaml # Security/compliance items to check per vendor

scripts/
├── parse-request.sh          # Validates and normalizes evaluation request

data/
├── active-evaluation.json    # Normalized current evaluation request
├── research/{vendor}.json    # Raw research per vendor
├── scores/{vendor}.json      # Scored results per vendor
├── scores/score-matrix.json  # All vendors side-by-side scores
├── compliance/{vendor}.json  # Compliance findings per vendor
└── history/{eval-id}.json    # Historical evaluation records

output/
├── comparison-matrix.md      # Side-by-side vendor comparison table
├── executive-recommendation.md  # Final recommendation memo
├── detailed-scores.md        # Full scoring breakdown
└── quick-comparison.md       # Quick compare output (quick-compare workflow)
```

---

## Config Files

### config/evaluation-request.yaml
```yaml
evaluation_id: eval-2024-crm-001
category: CRM
description: "Evaluate CRM platforms for 50-person sales team"

vendors:
  - name: HubSpot
    url: https://www.hubspot.com
  - name: Salesforce
    url: https://www.salesforce.com
  - name: Pipedrive
    url: https://www.pipedrive.com

criteria:
  - name: Pricing
    weight: 25
    description: "Cost per seat, total cost of ownership, hidden fees"
  - name: Features
    weight: 25
    description: "Contact management, pipeline tracking, reporting, automation"
  - name: Ease of Use
    weight: 15
    description: "Onboarding time, UI quality, learning curve"
  - name: Integrations
    weight: 15
    description: "API quality, native integrations, Zapier/webhook support"
  - name: Support
    weight: 10
    description: "Response time, channels available, documentation quality"
  - name: Security & Compliance
    weight: 10
    description: "SOC2, GDPR, data encryption, access controls"

hard_requirements:
  - "Must have API access"
  - "Must support SSO/SAML"
  - "Must offer data export"
```

### config/criteria-defaults.yaml
```yaml
defaults:
  saas:
    criteria:
      - { name: Pricing, weight: 25 }
      - { name: Features, weight: 25 }
      - { name: Ease of Use, weight: 15 }
      - { name: Integrations, weight: 15 }
      - { name: Support, weight: 10 }
      - { name: Security & Compliance, weight: 10 }
  infrastructure:
    criteria:
      - { name: Performance, weight: 25 }
      - { name: Reliability, weight: 20 }
      - { name: Security, weight: 20 }
      - { name: Pricing, weight: 15 }
      - { name: Support, weight: 10 }
      - { name: Integrations, weight: 10 }
```

### config/compliance-checklist.yaml
```yaml
security:
  - SOC 2 Type II certification
  - ISO 27001 certification
  - Data encryption at rest and in transit
  - Regular penetration testing
  - Incident response plan published

data_handling:
  - GDPR compliance (for EU data)
  - Data residency options
  - Data export capability
  - Data deletion on request
  - Subprocessor transparency

access_control:
  - SSO/SAML support
  - Role-based access control
  - Multi-factor authentication
  - Audit logging
  - API key management
```

---

## Schedule

No default schedule — vendor evaluations are triggered on-demand:
```bash
ao queue enqueue \
  --title "CRM Evaluation Q1 2025" \
  --description "Evaluate HubSpot, Salesforce, Pipedrive for sales team CRM" \
  --workflow-ref evaluate-vendors
```

For quick comparisons:
```bash
ao queue enqueue \
  --title "HubSpot vs Salesforce" \
  --description "HubSpot https://hubspot.com vs Salesforce https://salesforce.com" \
  --workflow-ref quick-compare
```

---

## Key Design Decisions

1. **Fetch MCP over Playwright**: Vendor websites are mostly static marketing pages —
   `server-fetch` converts to markdown cleanly and is much faster than browser automation.
   Playwright would only be needed for heavily JS-rendered pricing calculators.

2. **Separate compliance phase**: Compliance is a distinct concern from feature scoring.
   Keeping it separate lets the pipeline rework just the research phase if compliance
   data is missing, without re-scoring everything.

3. **Memory MCP for history**: Enables trend tracking ("last time we evaluated CRMs,
   HubSpot scored 68 — they've improved to 75"). Persists across evaluation runs.

4. **Review gate before output**: The scorer agent reviewing the reporter's output
   catches recommendation/score misalignment before the exec memo goes out.

5. **Default criteria templates**: Most evaluations fall into SaaS vs Infrastructure
   categories. Defaults save time while remaining fully customizable per request.
