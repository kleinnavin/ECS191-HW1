# SmartStock Insights Worker

A Cloudflare Worker that powers the app's Portfolio Insights. The app sends
its holdings to `POST /analyze`; the Worker builds the prompt, calls Claude
with the Anthropic API key stored as a Worker secret, and returns the
analysis as JSON. The key never ships in the app.

The model, prompt and response format live in `src/index.ts`, so the
endpoint can only produce portfolio analyses. Each IP address is limited to
3 requests a minute.

## Deploy

```sh
cd insights-worker
npm install
npx wrangler login                            # opens the browser to sign in to Cloudflare
npx wrangler secret put ANTHROPIC_API_KEY     # paste a new Anthropic key when prompted
npx wrangler deploy                           # prints the Worker's URL
```

Then put the Worker's host (without `https://`) in
`SmartStock/Config/Secrets.xcconfig` and rebuild the app:

```
INSIGHTS_API_HOST = smartstock-insights.<your-subdomain>.workers.dev
```

## Run locally

```sh
cp .dev.vars.example .dev.vars   # then add your key; .dev.vars is git-ignored
npm run dev                      # serves http://127.0.0.1:8787
```

Set `INSIGHTS_API_HOST = 127.0.0.1:8787` in `Secrets.xcconfig` to point the
simulator at it.

## Changing the prompt

Edit `SYSTEM`, `SCHEMA` or `prompt()` in `src/index.ts`, then `npx wrangler
deploy`. No app update is needed unless the response's shape changes, in
which case `PortfolioAnalysis` in the app must match `SCHEMA`.
