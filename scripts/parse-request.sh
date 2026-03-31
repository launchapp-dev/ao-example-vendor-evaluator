#!/usr/bin/env bash
# parse-request.sh — Validates and normalizes the evaluation request.
# Reads: config/evaluation-request.yaml
# Writes: data/active-evaluation.json
# Exit 1 if validation fails.

set -euo pipefail

CONFIG="config/evaluation-request.yaml"
OUTPUT="data/active-evaluation.json"

echo "=== Vendor Evaluation Request Parser ==="
echo "Reading: $CONFIG"

# Check config file exists
if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: $CONFIG not found. Create it from the template before running." >&2
  exit 1
fi

# Check yq or python3 is available for YAML parsing
if command -v python3 &>/dev/null; then
  PARSER="python3"
else
  echo "ERROR: python3 is required to parse YAML." >&2
  exit 1
fi

# Extract and validate fields using Python
python3 << 'PYEOF'
import sys
import json
import re
from datetime import datetime

try:
    import yaml
except ImportError:
    # Minimal YAML parser for simple key-value structures
    print("WARNING: PyYAML not installed. Using minimal parser.", file=sys.stderr)
    yaml = None

config_path = "config/evaluation-request.yaml"

if yaml:
    with open(config_path) as f:
        config = yaml.safe_load(f)
else:
    # Fallback: read as text and parse key fields manually
    print("ERROR: PyYAML is required. Install with: pip3 install pyyaml", file=sys.stderr)
    sys.exit(1)

errors = []

# Validate required fields
required = ["evaluation_id", "category", "vendors", "criteria"]
for field in required:
    if field not in config or not config[field]:
        errors.append(f"Missing required field: {field}")

if errors:
    for e in errors:
        print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)

# Validate vendors list
vendors = config.get("vendors", [])
if len(vendors) == 0:
    errors.append("vendors list is empty — must have at least one vendor")
if len(vendors) > 10:
    errors.append(f"vendors list has {len(vendors)} entries — maximum is 10 per evaluation")

# Validate each vendor has name and url
for i, v in enumerate(vendors):
    if not v.get("name"):
        errors.append(f"Vendor #{i+1} is missing 'name'")
    if not v.get("url"):
        errors.append(f"Vendor '{v.get('name', f'#{i+1}')}' is missing 'url'")

# Validate criteria weights sum to 100
criteria = config.get("criteria", [])
if len(criteria) == 0:
    errors.append("criteria list is empty")

total_weight = sum(c.get("weight", 0) for c in criteria)
if total_weight != 100:
    errors.append(f"Criteria weights sum to {total_weight}, must equal 100")

# Validate each criterion has required fields
for c in criteria:
    if not c.get("name"):
        errors.append("A criterion is missing 'name'")
    if "weight" not in c:
        errors.append(f"Criterion '{c.get('name', 'unknown')}' is missing 'weight'")

if errors:
    print("=== VALIDATION FAILED ===", file=sys.stderr)
    for e in errors:
        print(f"  ✗ {e}", file=sys.stderr)
    sys.exit(1)

# Normalize vendors: add slug
import re
for v in vendors:
    v["slug"] = re.sub(r"[^a-z0-9]+", "-", v["name"].lower()).strip("-")

# Build normalized output
output = {
    "evaluation_id": config["evaluation_id"],
    "category": config["category"],
    "description": config.get("description", ""),
    "created_at": datetime.utcnow().isoformat() + "Z",
    "vendors": vendors,
    "criteria": criteria,
    "hard_requirements": config.get("hard_requirements", []),
    "total_criteria_weight": total_weight
}

import os
os.makedirs("data", exist_ok=True)

with open("data/active-evaluation.json", "w") as f:
    json.dump(output, f, indent=2)

print(f"✓ Evaluation ID: {output['evaluation_id']}")
print(f"✓ Category: {output['category']}")
print(f"✓ Vendors ({len(vendors)}): {', '.join(v['name'] for v in vendors)}")
print(f"✓ Criteria ({len(criteria)}): weights sum to {total_weight}")
print(f"✓ Hard requirements: {len(output['hard_requirements'])}")
print(f"✓ Output written to data/active-evaluation.json")
PYEOF

echo "=== Validation passed. Pipeline is ready to run. ==="
