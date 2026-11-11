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

## What you need

You should be comfortable with a terminal. You don't need to know Hermes or
Python, and neither gets installed on your machine.

- **Docker**, with at least 4 GB of memory and 5 GB of free disk:
  - Linux (x86_64 or arm64): Docker Engine, with your user allowed to run `docker`
  - macOS (Apple Silicon or Intel): Docker Desktop, or Colima started with `colima start --memory 4`
  - Windows: WSL 2 with Docker Desktop's WSL integration, or Docker Engine
    inside WSL; run every command in the WSL terminal
- **Bash, curl** and `sha256sum` or `shasum`
- **HTTPS access** to `hermes-agent.nousresearch.com`, `github.com`, Docker Hub,
  the Ubuntu package mirrors and your model provider (`openrouter.ai` by default)
- **An API key** with a small credit limit (see below)

If your organisation restricts Docker Desktop, arrange another runtime or
machine before the day.

## Before the workshop

Please do this at home rather than on conference Wi-Fi: the build downloads
several hundred megabytes, and the finished image is about 2.7 GB.

```bash
git clone <this repository> hermes-workshop && cd hermes-workshop   # or unzip the archive
bash scripts/01-check-prerequisites.sh      # checks Docker, disk space and network (read-only)
bash scripts/02-download-installer.sh       # downloads the official Hermes installer for review
less .downloads/hermes-install.sh           # read it
bash docker/workshop.sh build               # installs Hermes INSIDE the image, pinned to the file you read
bash docker/workshop.sh start --web         # opens a shell inside the container (--web: see "Hermes in your browser")
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

## Hermes in your browser

Hermes also has a web dashboard: a chat, plus pages for settings, API keys and
sessions. It works when the container was started with `--web`, as in the
steps above. Set up your key and model first (see the quick reference), then,
inside the container:

```bash
cd ~/hermes-workshop-lab && hermes dashboard --host 0.0.0.0 --skip-build --no-open
```

Start it in the lab, as with the terminal: its chat works in the folder the
dashboard starts in, and the lab's `AGENTS.md` applies only there.

Then open <http://127.0.0.1:9119> on your machine. The first time, Hermes asks
you to set up a login: choose "Username & password", with a password you don't
use anywhere else. Ctrl+C stops the dashboard.

- Container created without `--web`? Docker can't add the port later. Recreate
  the container; the volume with Hermes, your key, sessions and lab is kept:
  `docker rm -f hermes-workshop && bash docker/workshop.sh start --web`
- Port 9119 already in use on your machine? Choose another one when you create
  the container, e.g. `HERMES_WS_WEB_PORT=9200 bash docker/workshop.sh start --web`,
  and open <http://127.0.0.1:9200>.
- The port is published on 127.0.0.1 only, so nobody else on your network can
  reach it.

## Safety rules

1. Run Hermes only inside the workshop container, and start it in
   `~/hermes-workshop-lab`. The `AGENTS.md` in that folder keeps the agent in
   scope, but it's only an instruction. The container is the real boundary.
2. Use the fictional workshop data only.
3. Use your own API key with a credit limit, and revoke it afterwards.
4. Read approval prompts before answering, and don't use `--yolo`.
5. When you're done, remove everything (see [Removing everything](#removing-everything)).

## Removing everything

After the workshop, or to start again from scratch, run this in the repository:

```bash
bash docker/workshop.sh reset --yes   # the container and its volume: Hermes, API key, sessions, lab
docker rmi hermes-workshop:latest     # the image (add hermes-workshop:prereqs if you ran install-demo)
rm -rf .downloads                     # the installer you reviewed
```

Each of these should then list nothing:

```bash
docker ps -a --filter name=hermes-workshop
docker volume ls --filter name=hermes-workshop
docker images 'hermes-workshop*'
```

Then revoke your API key in your provider's dashboard. Nothing else needs
cleaning: Hermes was never installed on your machine.

To start again, repeat the steps in "Before the workshop", but build with
`bash docker/workshop.sh build --refresh`. Docker's build cache outlives the
image, and without `--refresh` the build restores the old Hermes install from
it. That cache can also hold a few GB; `docker builder prune` frees it, but it
clears every project's build cache, not just this one.

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
