# Hermes Agent: a two-hour hands-on workshop

Install, configure and run your own AI agent with
[Hermes Agent](https://github.com/NousResearch/hermes-agent) from Nous Research,
and look at how it works inside: the loop of model calls, tool calls and
observations, and how to check what it hands back to you.

By the end, your agent will have:
- read a sales CSV, computed revenue with code and written a Markdown report;
- been checked by an independent script that uses no LLM;
- reused the same procedure as a skill on a second dataset;
- run as a scheduled job.

Hermes runs only in a Docker container in this workshop. Apart from this
repository and the Docker image, nothing gets installed on your laptop, and the
agent can't see your own files.

Tested with Hermes Agent v0.23.1. Hermes releases often; if a command behaves
differently, check `<command> --help`.

## Who it is for

Anyone comfortable with a terminal. You don't need to know Hermes or Python:
every step uses a provided script or prompt.

You do need Docker, because there is no install-on-your-laptop option:

- Linux (x86_64 or arm64): Docker Engine, with your user allowed to run `docker`.
- macOS (Apple Silicon or Intel): Docker Desktop or Colima.
- Windows: WSL 2 with Docker Desktop's WSL integration, or Docker Engine
  inside WSL. Run every command in the WSL terminal.

If your organisation restricts Docker Desktop (licensing, admin rights), sort
out an allowed runtime or another machine before the day. The prerequisite
check below fails without a working Docker.

## Before the workshop

Please do this at home rather than on conference Wi-Fi: the build downloads
several hundred megabytes, and the finished image is about 2.7 GB.

```bash
git clone <this repository> hermes-workshop && cd hermes-workshop   # or unzip the archive
bash scripts/01-check-prerequisites.sh      # checks Docker, disk space and network (read-only)
bash scripts/02-download-installer.sh       # downloads the official Hermes installer for review
less .downloads/hermes-install.sh           # read it
bash docker/workshop.sh build               # installs Hermes INSIDE the image, pinned to the file you read
bash docker/workshop.sh start               # opens a shell inside the container
# inside the container:
bash scripts/03-verify-installation.sh
exit
```

Then create an account at <https://openrouter.ai> and an API key with a small
credit limit (a few US dollars). You'll set it up inside the container during
the workshop. Keep it to yourself: don't commit it, paste it into chat or show
it on screen.

Already have an Anthropic or OpenAI API account? You can use that key instead.
Set a spending limit in that provider's console, and choose a small, low-cost
model when you set up Hermes (see the quick reference below).

On your machine you need Bash, curl, `sha256sum` or `shasum`, Docker with at
least 4 GB of memory, about 5 GB of free disk, and HTTPS access to
`hermes-agent.nousresearch.com`, `github.com`, Docker Hub, the Ubuntu package
mirrors and `openrouter.ai`. You don't need Python or Hermes on your machine.

## Quick reference

On your machine:

```bash
bash docker/workshop.sh start     # terminal 1: a shell inside the container (participant@hermes-lab)
bash docker/workshop.sh shell     # terminal 2: another shell in the same container
bash docker/workshop.sh stop      # stop it; everything is kept
bash docker/workshop.sh reset     # delete the container and its data (after the workshop)
```

Inside the container (it opens in `~/hermes-workshop`, a copy of this repository):

```bash
bash scripts/04-create-workspace.sh                 # lab directory: ~/hermes-workshop-lab
bash scripts/04.1-show-context-files.sh             # optional: SOUL.md, AGENTS.md, MEMORY.md, USER.md
hermes config set OPENROUTER_API_KEY 'sk-or-v1-...'
hermes config set model.provider openrouter
hermes config set model.default anthropic/claude-haiku-5.5
# or, with your own Anthropic or OpenAI key, instead of the three lines above:
hermes model    # choose "Anthropic" or "OpenAI API", paste the key, pick a small model
cd ~/hermes-workshop-lab && hermes --checkpoints    # always start Hermes inside the lab

# terminal 2, inside the container:
python3 scripts/05-verify-results.py --dataset ~/hermes-workshop-lab/data/sales-sample.csv \
  --report ~/hermes-workshop-lab/reports/first-report.md

bash scripts/06-install-skill.sh                    # installs the csv-reporting skill
```

If you run `03`, `04`, `06` or `07` on your own machine by mistake, they stop
and tell you to open the container.

## Safety rules

1. Run Hermes only inside the workshop container, and start it in
   `~/hermes-workshop-lab`. The `AGENTS.md` in that folder keeps the agent in
   scope, but it's only an instruction. The container is the real boundary.
2. Use the fictional workshop data only.
3. Use your own API key with a credit limit, and revoke it afterwards.
4. Read approval prompts before answering, and don't use `--yolo`.
5. When you're done, remove everything with `bash docker/workshop.sh reset`.

## What's in this repository

```text
docker/         Dockerfile and workshop.sh: build, start and reset the container
scripts/        the numbered steps: 01 and 02 on your machine, the rest inside the container
data/           the two sales datasets
skills/         the csv-reporting skill
lab-template/   AGENTS.md, copied into the lab folder
```

## References

- Hermes Agent source: <https://github.com/NousResearch/hermes-agent>
- Documentation: <https://hermes-agent.nousresearch.com/docs/>
- Installation: <https://hermes-agent.nousresearch.com/docs/getting-started/installation>
- Skills: <https://hermes-agent.nousresearch.com/docs/user-guide/features/skills>
- Scheduled tasks: <https://hermes-agent.nousresearch.com/docs/user-guide/features/cron>
- Security: <https://hermes-agent.nousresearch.com/docs/user-guide/security> and
  <https://hermes-agent.nousresearch.com/docs/guides/secure-hermes-on-a-work-machine>
