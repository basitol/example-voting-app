#!/usr/bin/env bash
set -euo pipefail

VOTE_URL="${VOTE_URL:-http://localhost:8080}"
RESULT_URL="${RESULT_URL:-http://localhost:8081}"

echo "Waiting for Vote service..."
for i in {1..30}; do
  if curl -fsS "$VOTE_URL" >/dev/null; then
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "Vote service failed to become ready."
    exit 1
  fi
  sleep 2
done

echo "Waiting for Result service..."
for i in {1..30}; do
  if curl -fsS "$RESULT_URL" >/dev/null; then
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "Result service failed to become ready."
    exit 1
  fi
  sleep 2
done

get_vote_count() {
  docker compose exec -T db \
    psql -U postgres -d postgres -tAc \
    "SELECT COALESCE(SUM(count), 0) FROM (
       SELECT COUNT(*) AS count FROM votes WHERE vote = 'b'
     ) AS vote_counts;"
}

before=$(get_vote_count)

echo "Submitting a test vote..."
curl -fsS -X POST --data "vote=b" "$VOTE_URL" >/dev/null

echo "Waiting for the vote to reach PostgreSQL..."
for i in {1..30}; do
  after=$(get_vote_count)
  if [ "$after" -gt "$before" ]; then
    echo "Integration test passed: vote count increased from $before to $after."
    exit 0
  fi
  sleep 2
done

echo "Integration test failed: vote was not recorded in PostgreSQL."
exit 1
