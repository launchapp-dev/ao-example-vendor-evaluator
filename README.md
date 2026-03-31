# Vendor Evaluation Pipeline

Multi-agent pipeline that researches vendors via live web fetch, scores them against weighted criteria, checks compliance, and produces an executive recommendation memo — end to end, no manual work.

## Workflow Diagram

```
config/evaluation-request.yaml
          │
          ▼
  ┌─────────────────┐
  │  parse-request  │  (command) Validate input, normalize to data/active-evaluation.json
  └────────┬────────┘
           │
           ▼
  ┌─────────────────┐
  │ research-vendors│  (researcher / haiku) Fetch vendor sites, pricing, reviews via fetch MCP
  └────────┬────────┘
           │
           ▼
  ┌─────────────────┐
  │  score-vendors  │  (scorer / sonnet) Weighted scoring with sequential-thinking
  └────────┬────────┘
           │
           ▼
  ┌──────────────────┐
  │ check-compliance │  (compliance-checker / haiku) Security certs, hard requirements
  └────────┬─────────┘
           │
     ┌─────┴──────┐
     │            │
 needs-more-info  │ all-clear / has-blockers
     │            │
     └──► research-vendors (rework, max 2x)
                  │
                  ▼
  ┌───────────────────┐
  │  generate-report  │  (report-writer / sonnet) Matrix + exec memo + detailed scores
  └────────┬──────────┘
           │
           ▼
  ┌─────────────────┐
  │  review-report  │  (scorer / sonnet) Sanity-check: scores ↔ recommendation alignment
  └────────┬────────┘
           │
     ┌─────┴──────┐
     │            │
  rework    approve
     │            │
     └──► generate-report (rework, max 2x)
                  │
                  ▼
         output/ (reports ready)


Quick Compare Workflow (2 vendors only):
  parse-quick → research-and-score → output/quick-comparison.md
```

## Quick Start

```bash
# 1. Edit your vendor list and criteria
vim config/evaluation-request.yaml

# 2. Start the AO daemon and run the full evaluation
cd examples/vendor-evaluator
ao daemon start
ao queue enqueue \
  --title "CRM Evaluation Q1 2025" \
  --description "Evaluate HubSpot, Salesforce, Pipedrive for our sales team" \
  --workflow-ref evaluate-vendors

# 3. Watch progress
ao daemon stream --pretty

# 4. Read results
cat output/executive-recommendation.md
```

### Quick 2-Vendor Comparison

```bash
ao queue enqueue \
  --title "HubSpot vs Salesforce" \
  --description "HubSpot https://hubspot.com vs Salesforce https://salesforce.com" \
  --workflow-ref quick-compare
```

## Agents

| Agent | Model | Role |
|---|---|---|
| **researcher** | claude-haiku-4-5 | Fetches vendor websites, pricing pages, docs, and review sites via fetch MCP. Extracts structured facts and writes per-vendor research JSON. |
| **scorer** | claude-sonnet-4-6 | Applies weighted scoring rubric across all criteria using sequential-thinking. Produces per-vendor scores and consolidated comparison matrix. Also runs final review gate. |
| **compliance-checker** | claude-haiku-4-5 | Checks each vendor against security checklist (SOC2, GDPR, encryption, SSO) and hard requirements. Issues compliance verdict with routing logic. |
| **report-writer** | claude-sonnet-4-6 | Synthesizes all findings into three output documents. Uses memory MCP to compare against prior evaluations. Writes executive recommendation memo. |

## AO Features Demonstrated

| Feature | Where |
|---|---|
| **Multi-agent pipeline** | Four specialized agents, each with a distinct role and model |
| **Decision contracts** | `check-compliance` and `review-report` emit structured verdicts |
| **Rework loops** | Compliance can loop back to research; report can loop back to writer |
| **Command phases** | `parse-request` validates YAML input and writes JSON via bash |
| **Multiple models** | haiku for fast research/compliance; sonnet for analysis and writing |
| **fetch MCP** | Real-time vendor website research without browser overhead |
| **sequential-thinking MCP** | Structured multi-criteria scoring methodology |
| **memory MCP** | Cross-evaluation history and trend tracking |
| **Output contracts** | Typed JSON outputs define exactly what each agent produces |
| **Retry policy** | research-vendors retries on tool errors |

## Output Files

```
output/
├── executive-recommendation.md   # TL;DR, recommendation, vendor profiles, next steps
├── comparison-matrix.md          # Side-by-side scores table with compliance status
├── detailed-scores.md            # Full scoring breakdown with justifications
└── quick-comparison.md           # Quick-compare output (quick-compare workflow only)

data/
├── active-evaluation.json        # Normalized evaluation request
├── research/{vendor}.json        # Research data per vendor
├── scores/{vendor}.json          # Scores per vendor
├── scores/score-matrix.json      # All vendors ranked by score
├── compliance/{vendor}.json      # Compliance findings per vendor
└── history/{eval-id}.json        # Archived evaluation record
```

## Requirements

- **AO daemon** running (`ao daemon start`)
- **Python 3** with PyYAML (`pip3 install pyyaml`) — for the parse-request script
- **No API keys required** — fetch MCP uses public web pages only
- **Internet access** — researcher fetches live vendor websites

### Optional

- Set up `MEMORY_PATH` if you want memory MCP to persist across sessions
- Customize `config/criteria-defaults.yaml` for your evaluation category
- Add review sites (G2, Capterra) URLs directly in `evaluation-request.yaml` for better research

## Configuration

Edit `config/evaluation-request.yaml` to customize:
- **Vendor list** with names and URLs
- **Criteria** with weights (must sum to 100)
- **Hard requirements** (pass/fail gates)

See `config/criteria-defaults.yaml` for pre-built criteria sets for SaaS, Infrastructure, Data, and Security tooling categories.
