# Vendor Evaluation Pipeline — Agent Context

This is an AO workflow that evaluates software vendors using live web research, weighted scoring, compliance checking, and executive report generation.

## What This Repo Does

Takes a vendor shortlist from `config/evaluation-request.yaml`, researches each vendor via the fetch MCP, scores them against weighted criteria using sequential-thinking, checks compliance and hard requirements, and produces three output documents in `output/`.

## Directory Layout

```
config/
├── evaluation-request.yaml   # INPUT: edit this to define your evaluation
├── criteria-defaults.yaml    # Pre-built criteria sets by category
└── compliance-checklist.yaml # Security/compliance items checked per vendor

scripts/
└── parse-request.sh          # Validates evaluation-request.yaml, writes data/active-evaluation.json

data/
├── active-evaluation.json    # Normalized evaluation request (written by parse-request)
├── research/{slug}.json      # Research data per vendor (written by researcher)
├── research/research-summary.json
├── scores/{slug}.json        # Scores per vendor (written by scorer)
├── scores/score-matrix.json  # All vendors ranked (written by scorer)
├── compliance/{slug}.json    # Compliance per vendor (written by compliance-checker)
├── compliance/compliance-summary.json
└── history/{eval-id}.json    # Archived evaluations (written by report-writer)

output/
├── comparison-matrix.md      # Side-by-side table
├── executive-recommendation.md
├── detailed-scores.md
└── quick-comparison.md       # quick-compare workflow only
```

## Agent Responsibilities

- **researcher**: Fetch MCP only — no scoring. Write research JSON files. Mark gaps honestly.
- **scorer**: Scoring and review only. Uses sequential-thinking to structure analysis. Writes score JSON and runs the final review gate.
- **compliance-checker**: Compliance and security review only. Emits decision contract with verdict.
- **report-writer**: Report generation only. Uses memory MCP for history. Writes three output files.

## Data Flow

```
evaluation-request.yaml
  → parse-request.sh
    → data/active-evaluation.json
      → researcher → data/research/*.json
        → scorer → data/scores/*.json
          → compliance-checker → data/compliance/*.json + decision
            → (if all-clear or has-blockers) report-writer → output/*.md
              → scorer (review) → approve or rework loop
```

## Key Conventions

- Vendor slugs are lowercase, hyphenated (e.g., "HubSpot" → "hubspot", "Salesforce" → "salesforce")
- All monetary values in USD
- Scores: 1-10 raw, multiply by weight/10 for weighted score, sum to 100-point overall
- If a data point is unknown, mark it explicitly — never assume or fabricate
- The `needs-more-info` compliance verdict triggers a research rework (max 2 attempts)
- The `rework` review verdict triggers a report regeneration (max 2 attempts)

## Running a New Evaluation

1. Edit `config/evaluation-request.yaml` with your vendor list and criteria
2. Ensure weights sum to 100
3. Run: `ao queue enqueue --title "<eval name>" --workflow-ref evaluate-vendors`

## Adding a Vendor Category

Add a new entry to `config/criteria-defaults.yaml` following the existing format.
Use the criteria names from defaults when setting up `evaluation-request.yaml`.
