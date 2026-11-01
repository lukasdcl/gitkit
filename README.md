# gitkit

One script that puts a folder on GitHub and then handles the everyday git jobs from a simple menu. You don't need to remember any git commands.

Copy `gitkit.sh` into any folder and run it:

- **If the folder is empty** (apart from gitkit), it asks which GitHub repo to use, for example `your-name/my-project`, and downloads it into the folder. It then applies its usual tidy-up to the downloaded copy (see below).
- **If the folder has files but isn't a git repo yet**, it asks whether to upload or download:
  - **Upload** shows you what's about to go up, asks you to confirm, and pushes. Whatever is in that GitHub repo gets replaced.
  - **Download** pulls the repo in alongside your files. If anything in the repo has the same name as something already in the folder, it stops and changes nothing.
- **If it already is one**, you get a menu for pushing, pulling, branching, undoing, tagging, and more.

Every time it runs, it also tidies the folder:

- creates a `.gitignore` with the usual junk files from macOS, Windows, Linux and code editors (`.DS_Store`, `Thumbs.db`, `desktop.ini`, `.env` and so on). If you already have a `.gitignore`, it adds only the rules that are missing and leaves the rest alone.
- adds `gitkit.sh` itself to the `.gitignore`, so the script never ends up in your project.
- creates `push.sh` if the folder doesn't have one. It's a tiny helper that commits everything and pushes, and it's gitignored too.

## Requirements

- `git`
- An SSH key already set up with GitHub. Check it with `ssh -T git@github.com`.
- Optional: the [GitHub CLI](https://cli.github.com) (`gh`), logged in with `gh auth login`. With it, gitkit can create the GitHub repo for you if it doesn't exist yet. Without it, gitkit tells you to create an empty repo on github.com and waits until you have.

It works on macOS (including the old bash 3.2 that macOS ships with), on Linux, and on Windows through Git Bash or WSL.

## Install

```sh
curl -O https://raw.githubusercontent.com/<owner>/gitkit/main/gitkit.sh
chmod +x gitkit.sh
```

Or just download `gitkit.sh` and drop it into the folder you want to manage.

## Usage

```sh
./gitkit.sh                     # menu (or first-time setup)
./gitkit.sh push "Fix typo"     # run one command directly
./gitkit.sh help                # list every command
```

| Command | What it does |
|---|---|
| `status` | Shows what's changed, and whether you're ahead of or behind GitHub |
| `push ["message"]` | Commits everything and pushes. Publishes new branches automatically |
| `pull` | Gets the latest from GitHub. If both sides have new commits, it offers to put yours on top |
| `branch [name]` | Makes a new branch, switches to it, and offers to publish it |
| `switch [name]` | Switches branch. Picks from a numbered list, including branches that only exist on GitHub |
| `merge [name]` | Merges another branch into the current one |
| `delete-branch [name]` | Deletes a branch here and, if you say so, on GitHub. Warns you if it has unmerged work |
| `stash` / `unstash` | Puts uncommitted changes aside, then brings them back |
| `undo` | Undoes the last commit and keeps its changes. If that commit is already on GitHub, it makes a reversing commit instead |
| `discard` | Throws away all uncommitted changes. You have to type `discard` to confirm |
| `log [count]` | Shows recent history as a graph |
| `tag [name]` | Marks the current commit, e.g. `v1.0`, and pushes the tag |
| `untrack [path...]` | Stops tracking files but keeps them on disk. With no path, it untracks everything that now matches `.gitignore` |
| `remote [owner/name]` | Points the folder at a different GitHub repo |
| `wipe-history` | Replaces the branch's whole history with one fresh commit of your current files, and force-pushes it. Handy after committing a password or a huge file by mistake |
| `open` | Opens the repo on github.com |
| `upload` / `download` | First run only: skips the question and goes straight to uploading or downloading |

After a download, any rules gitkit added to the repo's `.gitignore` are left uncommitted, so downloading never changes anything on GitHub by itself. Your next `push` includes them. If the repo already tracks a `push.sh` of its own, gitkit keeps it and tells you that you can `untrack` it.

## Safety

gitkit asks before it does anything that loses work:

- **Overwriting a GitHub repo that already has content** lists its branches and tags. You confirm by typing the repo name, and nothing is pushed until you do. If you cancel, the folder goes back to how it was.
- **Leftover branches or tags on GitHub** after an overwrite are only deleted if you say yes.
- **Files over 100 MB**, which GitHub rejects, are caught before anything is committed.
- **Commits that are already pushed** are undone with a reversing commit, so the history others have stays valid.
- **`discard` and `wipe-history`** both make you type a word to confirm.

## Notes

- The menu and commands work on the folder the script is in, wherever you run it from.
- When gitkit replaces a GitHub repo, it uses that repo's default branch name (for example `main` or `master`). That way it replaces the branch instead of adding a second one beside it. Brand-new repos get `main`.
- A file called `.gitkit-source` stops the script from ignoring itself. It only exists in this repo, where the script is the thing being published.
- To test without touching GitHub, set `GITKIT_REMOTE_BASE` to a folder of bare repos, e.g. `GITKIT_REMOTE_BASE=/tmp/remotes/ ./gitkit.sh`.

## License

MIT. See [LICENSE](LICENSE).
