#!/usr/bin/env bash
# Mints a short-lived, prefix-scoped S3 session and stores it as a Secret in the run namespace.
# Usage: issue.sh <writer|reader|transfer> <run-id> <namespace> [export-id]
set -euo pipefail

mode=$1 run=$2 ns=$3 export_id=${4:-}
: "${ML_BUCKET:?}" "${ML_ISSUER_AWS_ACCESS_KEY_ID:?}" "${ML_ISSUER_AWS_SECRET_ACCESS_KEY:?}"
ttl=${SESSION_SECONDS:-14400}

[[ $run =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || { echo "invalid run id" >&2; exit 2; }
[[ -z $export_id || $export_id =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || { echo "invalid export id" >&2; exit 2; }

arn="arn:aws:s3:::${ML_BUCKET}"
case $mode in
writer)
  role=$ML_WRITER_ROLE_ARN
  policy=$(jq -cn --arg a "$arn" --arg r "$run" --arg e "$export_id" '
    {Version:"2012-10-17",Statement:(
      [{Effect:"Allow",Action:["s3:GetObject","s3:PutObject","s3:AbortMultipartUpload","s3:ListMultipartUploadParts"],
        Resource:["\($a)/runs/\($r)/checkpoints/*","\($a)/runs/\($r)/outputs/*"]},
       {Effect:"Allow",Action:"s3:ListBucket",Resource:$a,
        Condition:{StringLike:{"s3:prefix":["runs/\($r)/*"]}}}]
      + (if $e == "" then [] else
        [{Effect:"Allow",Action:"s3:GetObject",Resource:"\($a)/datasets/\($e)/*"},
         {Effect:"Allow",Action:"s3:ListBucket",Resource:$a,Condition:{StringLike:{"s3:prefix":["datasets/\($e)/*"]}}}] end))}')
  ;;
reader)
  [[ -n $export_id ]] || { echo "reader needs an export id" >&2; exit 2; }
  role=$ML_READER_ROLE_ARN
  policy=$(jq -cn --arg a "$arn" --arg e "$export_id" '
    {Version:"2012-10-17",Statement:[
      {Effect:"Allow",Action:"s3:GetObject",Resource:"\($a)/datasets/\($e)/*"},
      {Effect:"Allow",Action:"s3:ListBucket",Resource:$a,Condition:{StringLike:{"s3:prefix":["datasets/\($e)/*"]}}}]}')
  ;;
transfer)
  role=$ML_TRANSFER_ROLE_ARN
  policy=$(jq -cn --arg a "$arn" --arg e "$export_id" --arg r "$run" '
    {Version:"2012-10-17",Statement:(
      (if $e == "" then [] else
        [{Effect:"Allow",Action:["s3:PutObject","s3:AbortMultipartUpload","s3:ListMultipartUploadParts"],Resource:"\($a)/datasets/\($e)/*"}] end)
      + [{Effect:"Allow",Action:"s3:GetObject",Resource:"\($a)/runs/\($r)/outputs/*"},
         {Effect:"Allow",Action:"s3:ListBucket",Resource:$a}])}')
  ttl=3600
  ;;
*)
  echo "mode must be writer, reader or transfer" >&2
  exit 2
  ;;
esac

creds=$(AWS_ACCESS_KEY_ID=$ML_ISSUER_AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$ML_ISSUER_AWS_SECRET_ACCESS_KEY \
  aws sts assume-role --role-arn "$role" --role-session-name "${mode}-${run}" \
  --duration-seconds "$ttl" --policy "$policy" --query Credentials --output json)

name="ml-${mode}-${run}"
kubectl -n "$ns" create secret generic "$name" --dry-run=client -o yaml \
  --from-literal=AWS_ACCESS_KEY_ID="$(jq -r .AccessKeyId <<<"$creds")" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$(jq -r .SecretAccessKey <<<"$creds")" \
  --from-literal=AWS_SESSION_TOKEN="$(jq -r .SessionToken <<<"$creds")" \
  --from-literal=AWS_DEFAULT_REGION="${ML_REGION:-us-east-1}" \
  --from-literal=ML_BUCKET="$ML_BUCKET" \
  | kubectl label --local -f - -o yaml "ml.talos.dev/run=${run}" "ml.talos.dev/mode=${mode}" \
  | kubectl apply -f - >/dev/null
echo "secret/${name} expires $(jq -r .Expiration <<<"$creds")"
