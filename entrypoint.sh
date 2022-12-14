#!/usr/bin/env bash

if [[ "$DEBUG" == "true" ]]; then
    set -eo xtrace
else
    set -e
fi

pwd

git version
git config --global --add safe.directory /github/workspace

echo "Creating artifact.."

COMMIT_MESSAGE=$(git log -1 --pretty=%B)
COMMIT_AUTHOR=$(git log -1 --pretty=format:'%an')
COMMIT_AUTHOR_EMAIL=$(git log -1 --pretty=format:'%ae')
COMMIT_COMITTER=$(git log -1 --pretty=format:'%cn')
COMMIT_COMITTER_EMAIL=$(git log -1 --pretty=format:'%ce')
COMMIT_CREATED=$(git log -1 --format=%cI)

BRANCH=${CI_COMMIT_BRANCH}

EVENT="push"
SHA=$CI_COMMIT_SHA
URL="TODO"

if [[ "$CI_PIPELINE_SOURCE" == "merge_request_event" ]]; then
    EVENT="pr"
    SHA=$CI_COMMIT_SHA
    SOURCE_BRANCH=$CI_MERGE_REQUEST_SOURCE_BRANCH_NAME
    TARGET_BRANCH=$CI_MERGE_REQUEST_TARGET_BRANCH_NAME
    PR_NUMBER=$CI_MERGE_REQUEST_ID
    URL="TODO PR URL"
fi

if [[ -n "$CI_COMMIT_TAG" ]]; then
    TAG=$CI_COMMIT_TAG
    EVENT="tag"
fi

gimlet artifact create \
--repository "$CI_PROJECT_PATH" \
--sha "$SHA" \
--created "$COMMIT_CREATED" \
--branch "$BRANCH" \
--event "$EVENT" \
--sourceBranch "$SOURCE_BRANCH" \
--targetBranch "$TARGET_BRANCH" \
--tag "$TAG" \
--authorName "$COMMIT_AUTHOR" \
--authorEmail "$COMMIT_AUTHOR_EMAIL" \
--committerName "$COMMIT_COMITTER" \
--committerEmail "$COMMIT_COMITTER_EMAIL" \
--message "$COMMIT_MESSAGE" \
--url "$URL" \
> artifact.json

echo "Attaching Gimlet manifests.."
for file in .gimlet/*
do
    if [[ -f $file ]]; then
    gimlet artifact add -f artifact.json --envFile $file
    fi
done

echo "Attaching environment variable context.."

VARS=$(printenv | grep "CI_PROJECT_NAMESPACE\|CI_PROJECT_NAME\|CI_PIPELINE_SOURCE\|CI_BUILD_REF_NAME\|CI_JOB_STATUS\|CI_PIPELINE_ID\|CI_BUILD_REF_SLUG\|CI_COMMIT_REF_SLUG\|CI_SERVER\|CI_COMMIT_SHORT_SHA\|CI_JOB_NAME_SLUG\|CI_PROJECT_PATH\|CI_COMMIT_SHA\|CI_CONCURRENT_PROJECT_ID\|CI_COMMIT_MESSAGE\|CI_BUILD_NAME\|CI_PIPELINE_IID\|CI_SERVER_URL\|CI_JOB_STAGE\|CI_PIPELINE_URL\|CI_DEFAULT_BRANCH\|CI_BUILD_REF\|CI_COMMIT_TITLE\|CI_PROJECT_ROOT_NAMESPACE\|CI_PROJECT_DIR\|CI_RUNNER_ID\|CI_PIPELINE_CREATED_AT\|CI_COMMIT_TIMESTAMP\|CI_REGISTRY_IMAGE\|CI_BUILD_ID\|CI_COMMIT_AUTHOR\|CI_COMMIT_REF_NAME\|CI_SERVER_HOST\|CI_JOB_URL\|CI_JOB_STARTED_AT\|CI_COMMIT_BRANCH\|CI_RUNNER_REVISION\|CI_BUILD_BEFORE_SHA\|CI_JOB_ID\|CI_BUILDS_DIR\|CI_PROJECT_ID\|CI_JOB_IMAGE\|CI_PROJECT_TITLE\|CI_COMMIT_BEFORE_SHA\|CI_BUILD_STAGE\|CI_PROJECT_URL" | awk '$0="--var "$0')
echo $VARS
gimlet artifact add -f artifact.json $VARS

echo "Attaching common Gimlet variables.."
gimlet artifact add \
-f artifact.json \
--var "REPO=$CI_PROJECT_PATH" \
--var "OWNER=$CI_PROJECT_NAMESPACE" \
--var "BRANCH=$BRANCH" \
--var "TAG=$TAG" \
--var "SHA=$CI_COMMIT_SHA" \
--var "ACTOR=" \
--var "EVENT=$CI_PIPELINE_SOURCE" \
--var "JOB=$CI_PIPELINE_ID"

if [[ "$DEBUG" == "true" ]]; then
    cat artifact.json
    exit 0
fi

echo "Shipping artifact.."
ARTIFACT_ID=$(gimlet artifact push -f artifact.json --output json | jq -r '.id' )
if [ $? -ne 0 ]; then
    echo $ARTIFACT_ID
    exit 1
fi

echo "Shipped artifact ID is: $ARTIFACT_ID"

if [[ -z "$TIMEOUT" ]];
then
    TIMEOUT=10m
fi

if [[ "$WAIT" == "true" || "$DEPLOY" == "true" ]]; then
    gimlet artifact track --wait --timeout $TIMEOUT $ARTIFACT_ID
else
    gimlet artifact track $ARTIFACT_ID
fi

if [[ "$DEPLOY" == "true" ]]; then
    echo "Deploying.."
    RELEASE_ID=$(gimlet release make --artifact $ARTIFACT_ID --env $ENV --app $APP --output json | jq -r '.id')
    echo "Deployment ID is: $RELEASE_ID"
    gimlet release track --wait --timeout $TIMEOUT $RELEASE_ID
fi
