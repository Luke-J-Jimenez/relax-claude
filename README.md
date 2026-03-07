# relax-claude

Run [Claude Code](https://code.claude.com) through [Relax AI](https://relax.ai). One script, self-installs on first run.

## Install

```bash
mkdir -p ~/.local/bin && curl -fsSL https://raw.githubusercontent.com/jmesout/relax-claude/main/relax-claude.sh -o ~/.local/bin/relax-claude && chmod +x ~/.local/bin/relax-claude && ~/.local/bin/relax-claude
```

First run sets up the `r-claude` shorthand, prompts for your [Relax API key](https://dashboard.relax.ai/settings/apikey), and lets you pick models.

Or clone and run manually:

```bash
git clone https://github.com/jmesout/relax-claude.git
cd relax-claude
./relax-claude.sh
```

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
- A [Relax AI](https://relax.ai) API key
- bash, curl
- [jq](https://jqlang.github.io/jq/) (optional, improves model list parsing)
- [Docker](https://www.docker.com/products/docker-desktop/) (optional, for container mode)
