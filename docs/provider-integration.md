# Provider integration

## ChatGPT Plus

Current OpenCode documentation identifies ChatGPT Plus as a supported subscription path. Perform the supported
browser login only inside a runtime session with `XDG_DATA_HOME` under guest `/run`, or use the company LLM gateway.

## Claude

Do not install unofficial Claude Pro/Max subscription plugins. Current OpenCode documentation states that
Anthropic prohibits that route and that bundled plugins were removed. Use an approved Anthropic API account or
company gateway.

## Grok

Use the xAI API or a gateway model backed by xAI. A consumer Grok subscription should not be assumed to provide
API access.

## Local Llama

The included `vdm-local` provider uses an OpenAI-compatible endpoint. Set:

```bash
VDM_LOCAL_LLM_BASE_URL=http://trusted-host:11434/v1
VDM_LOCAL_LLM_MODEL=exact-model-id
```

The static config contains a placeholder model ID. Replace it through company configuration once the actual local
server's `/v1/models` output is known.

## Agent role routing

Suggested starting allocation:

- orchestrator: strongest general coding model;
- architect: strongest long-context reasoning model;
- implementer: model best suited to the repository language;
- tester and documenter: lower-cost reliable model or local Llama;
- reviewer and security: a model different from the implementer;
- browser-qa: model with reliable tool use.

Do not hard-code these choices into the universal image. Model availability changes and each department may have
different budgets.
