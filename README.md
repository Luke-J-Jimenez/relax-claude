# Claude Code on Relax AI — via SmithPorts

Run [Claude Code](https://code.claude.com) through [Relax AI](https://relax.ai) — UK sovereign AI infrastructure. One script, self-installs on first run. Up to 80% cheaper than Anthropic API pricing.

Brought to you by [SmithPorts](https://smithports.co.uk) — The UK AI Infrastructure Lab. Certified Relax AI partner. Deployed on Civo LON1.

## Install

```bash
mkdir -p ~/.local/bin && curl -fsSL https://raw.githubusercontent.com/Luke-J-Jimenez/relax-claude/main/relax-claude.sh -o ~/.local/bin/relax-claude && chmod +x ~/.local/bin/relax-claude && ~/.local/bin/relax-claude
```

First run sets up the `r-claude` shorthand, prompts for your [Relax API key](https://dashboard.relax.ai/settings/apikey), and pre-selects recommended models:

| Claude Code tier | Recommended model | Why |
|-----------------|-------------------|-----|
| Opus | DeepSeek-V4-Pro | Frontier MoE. Reasoning, coding, long-context agentic. 1M token context. |
| Sonnet | DeepSeek-V4-Pro | Same model, tuned for balanced quality/speed. |
| Haiku | Llama-4-Maverick-17B-128E | Fast, multimodal, 500K context. |

Or clone and run manually:

```bash
git clone https://github.com/Luke-J-Jimenez/relax-claude.git
cd relax-claude
./relax-claude.sh
```

## Getting a Relax API Key

You'll need a free Relax AI account and API key. Takes about 60 seconds.

### Step 1: Create your Relax AI account

Go to [relax.ai](https://relax.ai) and click **Get Started** (top right). Sign up with your email. The free plan gives you 20 interactions per day — enough to try Claude Code on sovereign infra without committing to anything.

### Step 2: Generate an API key

Once logged in, go to **Settings → API Keys** (or visit [dashboard.relax.ai/settings/apikey](https://dashboard.relax.ai/settings/apikey) directly).

Click **Create API Key**, give it a name (e.g. "claude-code"), and copy the key. It'll look like `rak_...`.

### Step 3: Run relax-claude

Back in your terminal:

```bash
relax-claude
```

When prompted, paste your API key. That's it — you'll never need to enter it again.

The key is stored securely in your macOS Keychain (`security add-generic-password`) or in `~/.relax-claude-key` on Linux. It never leaves your machine.

### Step 4: Start coding

```bash
r-claude "explain this codebase to me"
```

Claude Code is now running through UK sovereign AI infrastructure, at a fraction of Anthropic's pricing. Your code and prompts never leave the UK.

**Need help?** Email luke@smithports.co.uk

## Why This Exists

Claude Code is the best AI coding agent. But using it through Anthropic directly means:
- Your code and prompts leave the UK (US-hosted inference)
- You pay Anthropic API pricing ($15-75/1M tokens)

Running it through Relax AI means:
- UK sovereign inference (Civo LON1 data centre)
- Up to 80% cheaper than Anthropic API pricing
- Same Claude Code experience — same features, same quality

| | Anthropic (direct) | Relax AI (via SmithPorts) |
|---|---|---|
| **Opus** | $15/1M input, $75/1M output | £1.17/1M input, £2.33/1M output |
| **Sonnet** | $3/1M input, $15/1M output | £0.15/1M input, £0.80/1M output |
| **Infrastructure** | US-hosted | UK sovereign (Civo LON1) |
| **Data residency** | US | UK only |

*Prices are approximate. Check [Relax AI](https://relax.ai) for current pricing.*

## Usage

```bash
relax-claude                       # interactive session
relax-claude "explain this code"   # start with a prompt
r-claude                           # shorthand
```

All flags pass through to `claude`. Additionally:

| Flag | Short | Effect |
|------|-------|--------|
| `--models` | `-m` | Choose which models to use for opus, sonnet, and haiku |
| `--config` | `-c` | Show current configuration |
| `--reset` | | Clear API key and model config |
| `--container [image]` | `-C` | Run Claude Code inside a Docker container |
| `--version` | `-v` | Show version |
| `--help` | `-h` | Show this help message |

## Container Mode

Run Claude Code in a sandboxed Docker container with your current directory mounted:

```bash
relax-claude --container                # pick from pre-defined images
relax-claude --container node:22        # use a specific image directly
relax-claude -C python:3.12            # shorthand
```

On first run for each image, Node.js and Claude Code are installed and the result is cached locally. Subsequent launches use the cached image and start instantly. All Relax API configuration (key, model mappings) is passed into the container automatically.

Custom container images must be Linux-based (Debian/Ubuntu, Alpine, Fedora, etc.) since the setup script uses standard Linux package managers.

Requires [Docker](https://www.docker.com/products/docker-desktop/).

## Uninstall

```bash
rm ~/.local/bin/relax-claude ~/.local/bin/r-claude
rm ~/.relax-claude-config
# macOS: security delete-generic-password -s relax-claude
# Linux: rm ~/.relax-claude-key
```

If installed on first run, also remove the PATH line added to your shell config:
```bash
# Remove the line: export PATH="$HOME/.local/bin:$PATH"
# from ~/.zshrc (macOS) or ~/.bashrc (Linux)
```

## Troubleshooting

If the script is force-killed (e.g. `kill -9`) while a spinner is running, your terminal cursor may be hidden. To restore it:

```bash
tput cnorm    # or just run: reset
```

## Requirements

- [Claude Code](https://code.claude.com) (`npm install -g @anthropic-ai/claude-code`)
- A [Relax AI](https://relax.ai) API key — follow the [Getting a Relax API Key](#getting-a-relax-api-key) guide above
- bash, curl
- [jq](https://jqlang.github.io/jq/) (optional, improves model list parsing)
- [Docker](https://www.docker.com/products/docker-desktop/) (optional, for container mode)

---

[SmithPorts](https://smithports.co.uk) — AI agents and interfaces shipped in 14 days on UK sovereign infrastructure. Fixed price from £2,500. Source code yours.