#!/bin/bash
# HealthLab Part 5: put the code and settings into the 4 Lambda functions created in the Console.
# Uploads dist/lambda.zip from GitHub, then sets Handler, Timeout, Memory and the 5 environment
# variables. Finds the bucket, SNS topic and Amplify URL by their names; asks for the Gemini key
# (hidden input, never printed).
# Run in CloudShell:  bash <(curl -sL https://raw.githubusercontent.com/haru-mishi/healthlab/main/scripts/lambda.sh)
set -euo pipefail
export AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1
cd "$(mktemp -d)"

for n in analyzer api subscribe reminder; do
  aws lambda get-function --function-name "healthlab-$n" > /dev/null 2>&1 ||
    { echo "healthlab-$n not found: create it in the Console first (5.1-5.2)"; exit 1; }
done
B=$(aws s3api list-buckets --query "Buckets[?starts_with(Name,'healthlab-uploads-')].Name | [0]" --output text)
T=$(aws sns list-topics --query "Topics[?ends_with(TopicArn,':healthlab-alerts')].TopicArn | [0]" --output text)
APP=$(aws amplify list-apps --query "apps[?name=='healthlab'].appId | [0]" --output text)
[ "$B" != None ] || { echo "no bucket healthlab-uploads-*: do Part 2 first"; exit 1; }
[ "$T" != None ] || { echo "no SNS topic healthlab-alerts: do Part 4 first"; exit 1; }
[ "$APP" != None ] || { echo "no Amplify app healthlab: do Part 1 first"; exit 1; }
URL=https://main.$APP.amplifyapp.com/
echo "BUCKET=$B"; echo "TOPIC_ARN=$T"; echo "APP_URL=$URL"

read -rsp 'Gemini API key (hidden): ' KEY; echo
KEY=${KEY//[[:space:]]/}
# Test the key with the same call the Lambda makes (generateContent on gemini-2.5-flash, x-goog-api-key),
# never by its prefix or another endpoint: AI Studio keys can start with AIza or AQ., and only this call matters.
# 1 output token, no thinking: costs one tiny request. 429 = key is valid but rate limited right now.
out=$(curl -s -w '\n%{http_code}' --max-time 30 -H "x-goog-api-key: $KEY" -H 'Content-Type: application/json' \
  -d '{"contents":[{"parts":[{"text":"ping"}]}],"generationConfig":{"maxOutputTokens":1,"thinkingConfig":{"thinkingBudget":0}}}' \
  https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent) || true
code=${out##*$'\n'}
[ "$code" = 200 ] || [ "$code" = 429 ] || { echo "Gemini key check failed (HTTP $code: $(printf '%s' "${out%$'\n'*}" | jq -r '.error.message // empty' 2>/dev/null || true)). 400/401/403 = wrong key: copy it again from aistudio.google.com/apikey"; exit 1; }
echo "Gemini key OK (HTTP $code)"

curl -sfLO https://raw.githubusercontent.com/haru-mishi/healthlab/main/dist/lambda.zip
ENV="Variables={TABLE=HealthReports,BUCKET=$B,TOPIC_ARN=$T,APP_URL=$URL,GEMINI_API_KEY=$KEY}"
for f in analyzer:180 api:30 subscribe:10 reminder:60; do
  n=${f%:*} fn=healthlab-${f%:*}
  aws lambda update-function-code --function-name "$fn" --zip-file fileb://lambda.zip > /dev/null
  aws lambda wait function-updated-v2 --function-name "$fn"
  aws lambda update-function-configuration --function-name "$fn" --handler "app.$n" \
    --timeout "${f#*:}" --memory-size 256 --environment "$ENV" > /dev/null
  aws lambda wait function-updated-v2 --function-name "$fn"
  echo "OK $fn  handler=app.$n  timeout=${f#*:}s"
done
