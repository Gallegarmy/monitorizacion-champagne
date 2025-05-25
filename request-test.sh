#!/usr/bin/env bash

BASE_URL="http://localhost:8000"
ENDPOINTS=( "/process" "/compute" "/error" "/external-call" )


NUM_REQUESTS="${NUM_REQUESTS:-}"
MAX_SLEEP="${MAX_SLEEP:-2.0}"

count=0
while [[ -z "$NUM_REQUESTS" || "$count" -lt "$NUM_REQUESTS" ]]; do
  idx=$(( RANDOM % ${#ENDPOINTS[@]} ))
  route="${ENDPOINTS[$idx]}"
  url="$BASE_URL$route"

  if [[ "$route" == "/compute" ]]; then
    n=$(( RANDOM % 16 + 5 ))
    url="${url}?count=${n}"
  fi

  start_ts=$(date +%s.%N)
  result=$(curl -s -o /dev/null -w "%{http_code} %{time_total}" "$url")
  http_code=${result%% *}
  latency=${result##* }
  end_ts=$(date +%s.%N)

  printf "[%s] %-30s → %3s in %ss\n" \
    "$(date '+%H:%M:%S')" "$url" "$http_code" "$latency"

  sleep_time=$(awk -v m="$MAX_SLEEP" -v r="$RANDOM" \
    'BEGIN { printf "%.3f", (r/32767) * m }')
  sleep "$sleep_time"

  count=$((count+1))
done
