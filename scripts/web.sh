#!/bin/bash
# HealthLab: deploy the web page to Amplify app "healthlab" (branch main), straight from GitHub.
#   Part 1:  creates the app and deploys index.html with placeholders (reserves the URL)
#   Part 10: run it again -> fills apiUrl / cognitoDomain / clientId from healthlab-api and
#            the Cognito app client "healthlab-web" automatically, then redeploys
# Run in CloudShell:  bash <(curl -sL https://raw.githubusercontent.com/haru-mishi/healthlab/main/scripts/web.sh)
set -euo pipefail
export AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1
cd "$(mktemp -d)"
curl -sfL https://raw.githubusercontent.com/haru-mishi/healthlab/main/web/index.html -o index.html

APP=$(aws amplify list-apps --query "apps[?name=='healthlab'].appId | [0]" --output text)
if [ "$APP" = None ]; then
  APP=$(aws amplify create-app --name healthlab --query app.appId --output text)
  aws amplify create-branch --app-id "$APP" --branch-name main > /dev/null
  echo "created Amplify app healthlab ($APP)"
fi

API=$(aws apigatewayv2 get-apis --query "Items[?Name=='healthlab-api'].ApiEndpoint | [0]" --output text)
APIID=$(aws apigatewayv2 get-apis --query "Items[?Name=='healthlab-api'].ApiId | [0]" --output text)
POOL=None CLIENT=None

# 1) Use the user pool + app client that the API's JWT authorizer trusts (Part 8.3).
#    Taking them from anywhere else gives tokens the API rejects with 401 -> "can't log in".
if [ "$APIID" != None ]; then
  ISS=$(aws apigatewayv2 get-authorizers --api-id "$APIID" \
    --query "Items[?AuthorizerType=='JWT'].JwtConfiguration.Issuer | [0]" --output text)
  AUD=$(aws apigatewayv2 get-authorizers --api-id "$APIID" \
    --query "Items[?AuthorizerType=='JWT'].JwtConfiguration.Audience[0] | [0]" --output text)
  ISS=${ISS%/}
  if [ "$ISS" != None ] && [ "$AUD" != None ] &&
     aws cognito-idp describe-user-pool-client --user-pool-id "${ISS##*/}" --client-id "$AUD" > /dev/null 2>&1; then
    POOL=${ISS##*/} CLIENT=$AUD
  fi
fi

# 2) No authorizer yet: fall back to the app client named healthlab-web, and warn if there is more than one
if [ "$POOL" = None ]; then
  FOUND=()
  for p in $(aws cognito-idp list-user-pools --max-results 60 --query 'UserPools[].Id' --output text); do
    c=$(aws cognito-idp list-user-pool-clients --user-pool-id "$p" \
      --query "UserPoolClients[?ClientName=='healthlab-web'].ClientId | [0]" --output text)
    if [ "$c" != None ]; then FOUND+=("$p"); [ "$POOL" = None ] && POOL=$p CLIENT=$c; fi
  done
  if [ ${#FOUND[@]} -gt 1 ]; then
    echo "WARNING: ${#FOUND[@]} user pools have an app client named healthlab-web: ${FOUND[*]}"
    echo "         using $POOL - users who signed up in another pool cannot log in. Delete the extras (or fix Part 8.3)."
  fi
fi

if [ "$API" != None ] && [ "$CLIENT" != None ]; then
  DOM=$(aws cognito-idp describe-user-pool --user-pool-id "$POOL" --query UserPool.Domain --output text)
  sed -i -e "s#__API_URL__#$API#" -e "s#__COGNITO_DOMAIN__#https://$DOM.auth.us-east-1.amazoncognito.com#" \
         -e "s#__CLIENT_ID__#$CLIENT#" index.html
  echo "apiUrl:        $API"
  echo "cognitoDomain: https://$DOM.auth.us-east-1.amazoncognito.com"
  echo "clientId:      $CLIENT"
  echo "userPool:      $POOL ($(aws cognito-idp describe-user-pool --user-pool-id "$POOL" --query UserPool.EstimatedNumberOfUsers --output text) users)"
else
  echo "healthlab-api / Cognito app client healthlab-web not found yet: deploying with placeholders (fine for Part 1)"
fi

python3 -m zipfile -c web.zip index.html
D=$(aws amplify create-deployment --app-id "$APP" --branch-name main)
curl -sf -T web.zip "$(echo "$D" | jq -r .zipUploadUrl)"
JOB=$(echo "$D" | jq -r .jobId)
aws amplify start-deployment --app-id "$APP" --branch-name main --job-id "$JOB" > /dev/null
for _ in $(seq 30); do
  S=$(aws amplify get-job --app-id "$APP" --branch-name main --job-id "$JOB" --query job.summary.status --output text)
  case $S in SUCCEED|FAILED|CANCELLED) break;; esac
  sleep 2
done
echo "deploy: $S"
echo "URL: https://main.$APP.amplifyapp.com/"
