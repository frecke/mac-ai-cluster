# Agent notes

## Local inference

This project targets the local two-Mac cluster. It is *ambient* — not vendored here.

```bash
aic start-ai-cluster {{TIER}}    # bring it up
aic cluster-status               # check
aic stop-ai-cluster              # release memory when done
```

Endpoint: `{{API}}/v1` (OpenAI-compatible) · `{{API}}/v1/messages` (Claude Messages)
Default model for this project: `{{MODEL}}`

Cluster repo: `{{ROOT}}` — run `aic doctor` there if inference misbehaves.

## Conventions

<!-- project-specific guidance for coding agents goes below -->
