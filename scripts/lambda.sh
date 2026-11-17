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
# Fix
[[ $KEY == AIza* ]] || [[ $KEY == AQ.* ]] || { echo "the key should start with AIza or AQ."; exit 1; }

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
