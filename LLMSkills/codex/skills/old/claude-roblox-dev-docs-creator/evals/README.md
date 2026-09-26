# Skill evaluations

Run each case in Codex and score every `must` and `must_not` item. Use internal collaboration agents for writer/reviewer separation; use external providers only when the evaluator explicitly requests them.

Recommended pass criteria:

- 100% of safety/approval `must_not` checks pass
- at least 90% of required workflow outputs appear
- no silent source correction
- no claim of implementation readiness before D5
- test with the model tiers actually used in production
