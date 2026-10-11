# GitHub and Codex repository setup prompt package

Use this package to set up your brother's existing game project as a GitHub repository, give you the access needed to help, and keep later changes on reviewable branches. It includes a setup prompt for his Codex and a work prompt for yours. The repository remains in his GitHub account; sharing a link to a private repository alone does not give access.

## What to send your brother

Ask him to open the game's existing project folder in Codex and paste **Prompt 1** below. Codex should identify the current project, protect existing work, and finish the local repository setup before creating or pushing to GitHub. The default is a private repository. If he has no GitHub CLI authentication, Codex can finish the local checks and explain the one-time browser sign-in he needs.

After setup, he sends you the repository link and invites the GitHub account you want to use. Accept the invitation before asking your Codex to clone or branch the private repository. For this workspace, the configured GitHub origin is `johnwestons/the-picture-shop`; if `johnwestons` is the account you want invited, give your brother that GitHub username.

## Prompt 1: prepare my existing game for GitHub collaboration

Copy this prompt into Codex while it has the **existing game project folder** open:

```text
Prepare this existing game project for collaboration through GitHub. This is my game and my local project. Keep ownership under my own GitHub account and make the GitHub repository private by default. I want my brother, whose GitHub username I will provide, to be able to work with his Codex on separate branches and propose changes for me to review. This prompt authorizes you to create one private repository under my clearly identified, currently authenticated GitHub account and publish a carefully checked initial game baseline only if there is no destination ambiguity, no pre-existing uncommitted Git work, and no credentials or local saves in the files to be published. If those conditions are not met, finish safe local preparation and show me exactly what requires a decision before changing anything on GitHub.

Work in this order and keep the project intact:

1. Inspect this exact project before changing anything. Report the absolute project root, detected game engine and tools, whether this is already a Git repository, current branch, configured remotes, recent history if present, and `git status --short --branch`. Look for local instructions such as AGENTS.md, the README, engine configuration, test/build scripts, save locations, generated output, and existing GitHub configuration. Treat the current source, authored game assets, and existing branch history as valuable work.

2. Preserve all existing work. Do not delete files, reset, clean, stash, rebase, amend, force-push, replace an existing remote, or rewrite history. Do not stage or commit existing uncommitted game changes. Do not copy this project's files or Git history into another checkout. If this folder already has a GitHub remote for the game, inspect and use it instead of creating a duplicate. If it has another remote, or you cannot determine whether an existing repository is the correct game, leave the remote alone and ask me which repository to use. If the game folder contains an unrelated project, do not initialize Git here.

3. Review the existing `.gitignore` and add only engine-appropriate rules that are missing. Keep source code, required configuration, authored source assets, generated runtime assets needed to build the game, and useful documentation tracked. Exclude local game saves and profiles, secrets and environment files, editor caches, temporary files, crash dumps, build folders, installers, exported game packages, test reports, and generated previews when they are reproducible and are not required build inputs. Before ignoring a broad directory such as `output`, `assets`, or `build`, inspect its contents and the build tools so you do not hide required source art or delete anything. Never put real player saves, signing keys, passwords, access tokens, or API keys in GitHub. Add a `.env.example` containing names and safe placeholders only when this project uses environment configuration. Do not add a license unless I choose one.

4. Check for likely credentials in files proposed for the initial commit without printing any credential values. If a real secret was already committed or is found in history, do not assume deleting the current copy removes it from history; tell me the affected file and safe remediation steps, and do not push exposed secrets. Identify oversized binary assets that may need deliberate asset hosting or Git LFS. Explain the options before adopting LFS or changing an asset pipeline.

5. Make the smallest useful onboarding improvements while preserving existing docs. Create or update a concise README that accurately names the game, explains its current engine/prerequisites, gives the real launch and test commands discovered in this repo, describes its important top-level folders, and tells a new contributor how we use task branches and pull requests. Do not invent commands, missing tests, project features, contact details, or releases. Add a lightweight CONTRIBUTING.md only if it makes the actual branch, test, asset, and review steps clearer. Do not copy The Picture Shop's art, LÖVE configuration, save paths, tests, assets, or release scripts into this project.

6. If there is no repository yet, initialize Git in this folder without removing or moving game files. Use the conventional `main` branch only if doing so preserves the current history and intent. If Git is already initialized, preserve its current branch names and history. Determine my GitHub account with `gh auth status`; never guess an owner or use credentials copied from chat. If the GitHub CLI is not installed or authenticated, tell me how to finish its official browser sign-in (`gh auth login`) and complete all safe local setup first.

7. If no matching GitHub repository exists and the authenticated account clearly belongs to me, create a private repository for this existing game and connect it as `origin`. Choose the name from the project itself, and show me the exact owner/name before creating it if more than one choice is plausible. For an existing local Git repository, `gh repo create OWNER/NAME --private --source=. --remote=origin` is the standard form; finish the staged-file review before pushing. Verify that the actual default branch matches this project's intended branch. Do not add GitHub Actions, branch-protection rules, bots, webhooks, releases, deployment, or other optional services unless this project already uses them or I ask. If its real automated test command is known and suitable for GitHub-hosted runners, describe a minimal CI option; do not add a workflow that cannot run or that needs a secret I have not configured.

8. Before any initial commit or push, inspect `git status --short --ignored`, the exact staged-file list, the target GitHub owner/repository and visibility, and the current branch. If this was already a Git repository, preserve it; do not add or commit any pre-existing uncommitted changes. If Git did not exist before this setup and the checked files are the clean initial game baseline, this prompt authorizes one baseline commit containing the project's intended source, build inputs, and onboarding files, then pushing that commit to the new private repository. Exclude saves, credentials, caches, temporary files, packages, and unrelated material. Never use `git add .` to sweep up changes in an existing repository. Never use force. If existing local history and GitHub history disagree, stop before pushing and explain the mismatch.

9. Give me a concrete handoff: the exact GitHub URL and `OWNER/REPOSITORY`, visibility, default branch, configured local remote, what you changed, what remains uncommitted, whether the source baseline was pushed, tests or checks actually run, any issue that needs me to sign in or choose, and the exact GitHub username I should invite. Do not claim a repository, invitation, push, or test succeeded unless you verified it. Leave inviting my brother's account to me unless I give you his exact username and ask you to send the invitation.

Use short, reviewable commits if a new setup commit is safe and contains only the onboarding changes you created. Otherwise, leave those local changes ready for my review and give me exact commands to commit and push them. Protect the game first; the goal is a working, understandable GitHub home for this project, not a speculative automation setup.
```

## Add your account to the repository

The repository owner should invite your GitHub username from the repository's **Settings → Collaborators** page. Your brother should send the invitation to the exact username you give him, then you accept it from GitHub. For a personal-account repository, collaborators can read and push code after they accept; a collaborator does not become the owner. Organization-owned repositories use organization roles instead. [GitHub collaborator instructions](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/repository-access-and-collaboration/inviting-collaborators-to-a-personal-repository)

## Prompt 2: work on my brother's game in a separate Codex project

After you have accepted the invitation, open the new repository in **its own Codex project or checkout** and paste this prompt, replacing the two bracketed values:

```text
Help me work on my brother's game in its own repository: [GITHUB_REPOSITORY_URL]. My task is: [DESCRIBE THE CHANGE]. I have accepted the repository invitation with write access.

First verify that this Codex workspace is a separate checkout for that repository. Print/check its project root, `git remote -v`, current branch and `git status --short --branch`. The `origin` URL must match the repository link above. Never change the origin in my other game workspace, copy this game into The Picture Shop, delete another checkout, or push to the wrong repository. If this repo is not available to Codex yet, explain how I can clone/open it as a separate project; do not reconfigure an unrelated project.

Use the repository's instructions and conventions. Fetch the latest default branch from origin. If the worktree is clean, create a fresh task branch named `codex/[SHORT_TASK_SLUG]` from that default branch. If it has local changes, preserve them and resolve with me how to isolate the task; do not overwrite or sweep them into my branch. If the branch name already exists, choose a fresh name and preserve the existing branch.

Inspect the relevant source, assets, tests, and build pipeline, then implement the requested change end-to-end with the smallest coherent set of edits. Keep my brother's existing game design and source assets. Use its real test and build commands, and report any verification you cannot run. Check the staged file list before committing; do not stage saves, keys, generated build packages, credentials, or unrelated changes. Do not force-push, merge to the default branch, publish a release, change visibility, or invite/remove collaborators.

When the task is ready, commit it on the task branch, push that branch to this same repository, and open a pull request against its default branch if GitHub CLI/auth permits. If a PR cannot be opened, still report the branch and give the owner a direct link or exact next step. Finish with the repository URL, branch, commit, pull-request URL if created, concise behavior summary, and exact tests/build checks that passed or failed. Leave the merge to my brother unless he explicitly authorizes it.
```

## Daily branch workflow

Use a fresh task branch per change, such as `codex/jump-controls` or `codex/fix-save-load`. Start these commands from the game's separate checkout when the worktree is clean, substituting the repository's actual default branch and a short task slug:

```text
git status --short --branch
git remote -v
git fetch origin
git switch <DEFAULT_BRANCH>
git pull --ff-only origin <DEFAULT_BRANCH>
git switch -c codex/<SHORT_TASK_SLUG>
```

After making and checking one focused change, review each staged path, commit on the task branch, and send it to GitHub for the owner to review:

```text
git add <REVIEWED_FILES>
git diff --cached --stat
git commit -m "describe the change"
git push -u origin codex/<SHORT_TASK_SLUG>
gh pr create --base <DEFAULT_BRANCH> --title "describe the change"
```

Before editing, check the repository path, remote, branch, and worktree so you can spot the wrong project or existing local edits. Keep a pull request focused on one change and include the test result and relevant screenshots or build notes. Let the owner review and merge it. Start each task from an updated default branch after the previous work merges; never reuse an old feature branch as the new baseline.

The Picture Shop currently uses the `origin` remote `johnwestons/the-picture-shop`, has `main` tracking `origin/main`, and names Codex work branches with the `codex/` prefix. Its tracked source-control rules are in [`docs/source_control.md`](source_control.md). That project deliberately keeps saves, local LÖVE builds, and most test output out of Git while retaining authored asset inputs needed to reproduce runtime art. Your brother's Codex should inspect his own game and apply the same care with his engine's saves, assets, and builds. This is a branching and review model, not a request to copy The Picture Shop's game code or setup.

This workspace uses an existing GitHub remote and a `main` branch. Its `docs/source_control.md` describes the local tracked-file boundary, but the repo currently has no tracked `.github` workflow or `CONTRIBUTING.md`. The prompts therefore ask Codex to document working commands and propose only CI that fits the actual game, rather than pretending a shared automation pipeline already exists.

The setup steps follow the official [`gh repo create` guide](https://cli.github.com/manual/gh_repo_create) and [browser-based `gh auth login` guide](https://cli.github.com/manual/gh_auth_login). Inviting the owner and accepting the request is essential before Codex can access a private repository; see [GitHub's invitation instructions](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/repository-access-and-collaboration/inviting-collaborators-to-a-personal-repository).
