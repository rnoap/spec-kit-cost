# Contract: cost-config.yml Schema

**File**: `.specify/extensions/cost/cost-config.yml`
**Required**: No (all keys have defaults)

---

## Keys

| Key | Type | Default | Description |
|---|---|---|---|
| `provider` | `self-report` \| `manual` \| `log-file` | `self-report` | Token count data source. Override at runtime: `SPECKIT_COST_PROVIDER=manual`. |
| `price_per_1k` | float ≥ 0 | *(absent)* | Legacy blended rate in USD per 1,000 tokens. **Only honored when explicitly set** (v1.3.0). When absent, unmatched models use split defaults: $3/M input, $15/M output. Shipped commented out in `config-template.yml`. |
| `input_rate_per_1k` | float ≥ 0 | *(absent)* | Override input token rate in USD per 1,000 tokens. Takes priority over the catalog for input tokens. |
| `output_rate_per_1k` | float ≥ 0 | *(absent)* | Override output token rate in USD per 1,000 tokens. Takes priority over the catalog for output tokens. |
| `model` | string | `unknown` | Legacy model label. Used as display only when the AI command cannot detect the model from harness context. Do not set this to control pricing — configure the catalog instead. |

---

## Rate Resolution (per token type)

For input tokens:
1. `input_rate_per_1k` (if set) → convert to per-M (× 1000)
2. Catalog `input_per_M` for the harness-detected model (tolerant matching — see [catalog-format.md](catalog-format.md))
3. `price_per_1k` (only if explicitly set) → convert to per-M (× 1000)
4. Hardcoded default: 3 per-M

For output tokens:
1. `output_rate_per_1k` (if set) → convert to per-M (× 1000)
2. Catalog `output_per_M` for the harness-detected model (tolerant matching — see [catalog-format.md](catalog-format.md))
3. `price_per_1k` (only if explicitly set) → convert to per-M (× 1000)
4. Hardcoded default: 15 per-M

---

## Backward Compatibility

A project with an existing `cost-config.yml` containing only `price_per_1k: 0.003` (and no new keys) will continue to produce correct output: the blended formula applies (cost = `(in + out) × 0.003 / 1000`). If a catalog match is found for the detected model, the catalog rates take priority — this is an improvement, not a breaking change.

Since v1.3.0 the template ships `price_per_1k` **commented out**, so fresh installs use the catalog plus split defaults ($3/M in, $15/M out) instead of pinning unknowns to a blended rate.

---

## Example

```yaml
# Minimal — use catalog for known models, split defaults ($3/M in, $15/M out) for unknowns
provider: self-report
# price_per_1k: 0.003   # opt-in legacy blended fallback — uncomment only to pin a single rate

# Optional: override catalog for custom enterprise pricing
# input_rate_per_1k: 0.004
# output_rate_per_1k: 0.020

# Optional: model label for manual-provider recording (not used for pricing)
# model: claude-sonnet-4-6
```
