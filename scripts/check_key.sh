#!/usr/bin/env bash
KEY=$1
EXISTS=$(aws ec2 describe-key-pairs --key-names "$KEY" 2>&1)
if echo "$EXISTS" | grep -q "InvalidKeyPair.NotFound"; then
  echo '{"exists":"false"}'
else
  echo '{"exists":"true"}'
fi
