# Market Risk VaR on BigQuery

Run 1-day Value at Risk end to end in BigQuery, from daily prices to answers in plain English. Back to [`AGENTS.md`](../AGENTS.md) or the [repository README](../README.md).

## What You'll Build

A market risk workflow for Pulsar Capital, a fictional firm with three equity desks and about $100M of US large-cap stocks:

1. **Market data:** 25 years of daily S&P 500 prices from Kaggle, turned into log returns up to a pinned as-of date.
2. **Forward volatility:** TimesFM forecasts every stock in one `AI.FORECAST` query, and its 99% prediction interval sets each stock's volatility.
3. **Monte Carlo:** 100,000 paths per stress scenario, replaying real trading days at today's volatility, giving VaR and Expected Shortfall per portfolio, desk and stock.
4. **Answers:** a Conversational Analytics data agent that answers risk questions in plain English and shows the SQL it ran.

## Technologies

| Service | Purpose |
| --- | --- |
| BigQuery | Storage, SQL transformations, the Monte Carlo procedure and the risk views |
| TimesFM (`AI.FORECAST`) | Zero-shot price forecasts with prediction intervals, no model to train |
| Dataform | Runs the pipeline from this repo's SQL, with assertions that fail bad runs |
| Conversational Analytics | The data agent, with glossary terms and verified queries |
| OpenTofu | Every resource, including the data agent |

## Results

From the sample run, as of 2026-10-23:

- **2.31% of notional** 1-day 99% VaR from the Monte Carlo, against 2.73% historical. The historical window holds the April 2025 selloff.
- **3,000,000 rows simulated** for a new stress scenario in 10 to 20 seconds, with one `INSERT` and one `CALL`
- **5 of 5 risk questions** answered by the data agent with SQL that matches the verified queries

## Guides

| Guide | Covers |
| --- | --- |
| [Value at Risk](01-value-at-risk.md) | Read the forecast, trace a path, compare VaR methods, add a stress scenario, ask the agent |
| [Quick Reference](quick.md) | Copy-paste queries, with sample output |
| [Architecture](architecture.md) | Pipeline diagram, data flow, components, the simulation method, observed product behaviour |

The market data is downloaded from Kaggle by `tofu apply`. See the [repository README](../README.md) for setup.
