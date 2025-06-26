#!/usr/bin/env bash

KEY_BASE=$1

# Get all matching key names
KEYS=$(aws ec2 describe-key-pairs --query "KeyPairs[].KeyName" --output text)

# Filter keys starting with base key name
MATCHED_KEYS=$(echo "$KEYS" | tr '\t' '\n' | grep "^${KEY_BASE}")

# If no keys found, use original key name
if [ -z "$MATCHED_KEYS" ]; then
  echo "{\"exists\":\"false\", \"next_suffix\":\"\"}"
  exit 0
fi

# Extract all suffix numbers and find max
MAX=0
for KEY in $MATCHED_KEYS; do
  SUFFIX=$(echo "$KEY" | grep -oE '[0-9]+$')
  if [ ! -z "$SUFFIX" ] && [ "$SUFFIX" -gt "$MAX" ]; then
    MAX=$SUFFIX
  fi
done

# Calculate next suffix (increment by 2)
NEXT=$((MAX + 2))

echo "{\"exists\":\"true\", \"next_suffix\":\"-${NEXT}\"}"
