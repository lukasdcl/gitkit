#!/usr/bin/env bash
#
# gitkit - put any folder on GitHub, then handle everyday git jobs from a menu.
#
# Drop this file into a folder and run it:
#
#   ./gitkit.sh              menu (or first-time setup if the folder isn't a repo yet)
#   ./gitkit.sh <command>    run one command directly, e.g. ./gitkit.sh branch my-idea
#   ./gitkit.sh help         list every command
#
# Every run also makes sure the folder has a sensible .gitignore and a push.sh
# helper, and that both helper scripts are ignored so they never get committed.
#
# Assumes you connect to GitHub over SSH and your key is already set up.
# Works with the bash that ships with macOS (3.2) as well as newer versions.

VERSION="1.0.0"

# Where repos live. Override only for testing, e.g. GITKIT_REMOTE_BASE=/tmp/remotes/
REMOTE_BASE="${GITKIT_REMOTE_BASE:-git@github.com:}"

SELF_NAME="$(basename "$0")"
cd "$(dirname "$0")" || exit 1
HERE="$(pwd -P)"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

if [ -t 1 ]; then
    B=$'\033[1m'; D=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
    YEL=$'\033[33m'; CYN=$'\033[36m'; R=$'\033[0m'
else
    B=''; D=''; RED=''; GRN=''; YEL=''; CYN=''; R=''
fi

say()   { printf '%s\n' "$*"; }
info()  { printf '%s\n' "${CYN}>${R} $*"; }
ok()    { printf '%s\n' "${GRN}✓${R} $*"; }
warn()  { printf '%s\n' "${YEL}!${R} $*"; }
err()   { printf '%s\n' "${RED}✗${R} $*" >&2; }
die()   { err "$*"; exit 1; }
title() { printf '\n%s\n' "${B}$*${R}"; }

# ask "Question" [default]  -> answer in $REPLY
ask() {
    if [ -n "$2" ]; then
        read -r -p "$1 ${D}[$2]${R} " REPLY
        [ -z "$REPLY" ] && REPLY="$2"
    else
        read -r -p "$1 " REPLY
    fi
}

# confirm "Question"  -> success only on y / yes (default is no)
confirm() {
    local a
    read -r -p "$1 [y/N] " a
    case "$a" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# confirm_typed "word"  -> success only if the user types the word exactly
confirm_typed() {
    local a
    read -r -p "Type ${B}$1${R} to confirm (anything else cancels): " a
    [ "$a" = "$1" ]
}

# ---------------------------------------------------------------------------
# .gitignore
# ---------------------------------------------------------------------------

gitignore_defaults() {
cat <<'EOF'
# macOS
.DS_Store
.AppleDouble
.LSOverride
._*
.Spotlight-V100
.Trashes
.fseventsd
.TemporaryItems
.DocumentRevisions-V100
.VolumeIcon.icns
.AppleDB
.AppleDesktop

# Windows
Thumbs.db
Thumbs.db:encryptable
ehthumbs.db
ehthumbs_vista.db
[Dd]esktop.ini
$RECYCLE.BIN/
*.lnk
*.stackdump

# Linux
*~
.directory
.Trash-*
.nfs*

# Editors
.idea/
*.swp
*.swo
*.sublime-workspace

# Secrets and local settings
.env
.env.*
!.env.example

# Logs
*.log

# Dependencies and caches
node_modules/
__pycache__/
*.py[cod]
.venv/
EOF
}

# The helper scripts themselves. A file called .gitkit-source marks gitkit's own
# repo, where the script is the thing being published and must not be ignored.
helper_ignore_lines() {
    [ -f .gitkit-source ] || printf '/%s\n' "$SELF_NAME"
    [ "$SELF_NAME" = "push.sh" ] || printf '/push.sh\n'
}

# Is this rule already in the file? Accepts common equivalents, so "/push.sh",
# "push.sh" and "**/push.sh" all count as the same rule.
ignore_has() {
    local rule="$1" bare="${1#/}"
    printf '%s\n' "$IGNORE_TEXT" | grep -qxF -e "$rule" -e "$bare" -e "/$bare" -e "**/$bare"
}

ensure_gitignore() {
    if [ ! -f .gitignore ]; then
        {
            gitignore_defaults
            printf '\n# Local helper scripts (not part of the project)\n'
            helper_ignore_lines
        } > .gitignore
        ok "Created .gitignore"
        return
    fi

    # Strip Windows line endings so matching works on files saved on Windows.
    IGNORE_TEXT="$(tr -d '\r' < .gitignore)"
    local missing=() line last_added=0
    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        case "$line" in
            '!'*)
                # An exception like !.env.example only works if it comes AFTER
                # the rule it overrides, so re-add it whenever we add that rule.
                if [ "$last_added" = 1 ] || ! ignore_has "$line"; then
                    missing+=("$line")
                fi
                ;;
            *)
                if ignore_has "$line"; then
                    last_added=0
                else
                    missing+=("$line"); last_added=1
                fi
                ;;
        esac
    done < <(gitignore_defaults; helper_ignore_lines)

    [ ${#missing[@]} -eq 0 ] && return

    # Make sure the existing file ends with a newline before appending.
    [ -n "$(tail -c 1 .gitignore)" ] && printf '\n' >> .gitignore
    {
        printf '\n# Added by gitkit\n'
        printf '%s\n' "${missing[@]}"
    } >> .gitignore
    ok "Added ${#missing[@]} missing rule(s) to .gitignore"
}

# ---------------------------------------------------------------------------
# push.sh helper (written out if the folder doesn't have one)
# ---------------------------------------------------------------------------

ensure_push_helper() {
    [ "$SELF_NAME" = "push.sh" ] && return
    [ -e push.sh ] && return
    cat > push.sh <<'PUSH_SH'
#!/bin/bash
# Stage everything, ask what changed, commit and push.
# Usage:  ./push.sh          (asks for the message)
#         ./push.sh "text"   (uses that message)
#

set -e
cd "$(dirname "$0")"

# Nothing to do?
if [ -z "$(git status --porcelain)" ]; then
    echo "Nothing has changed since the last commit."
    exit 0
fi

echo "Changes to be committed:"
git status --short
echo

if [ -n "$1" ]; then
    msg="$1"
else
    read -r -p "What changed? " msg
fi

# An empty message would abort the commit half way, so stop cleanly instead.
if [ -z "$msg" ]; then
    echo "No message given - nothing committed."
    exit 1
fi

git add -A
git commit -m "$msg"
git push
echo "Pushed."
PUSH_SH
    chmod +x push.sh
    ok "Created push.sh"
}

# ---------------------------------------------------------------------------
# Git state helpers
# ---------------------------------------------------------------------------

current_branch() { git symbolic-ref --short -q HEAD; }
has_commits()    { git rev-parse -q --verify HEAD >/dev/null 2>&1; }
upstream()       { git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null; }
origin_url()     { git remote get-url origin 2>/dev/null; }

# owner/name from the origin URL (empty if it isn't a GitHub-style URL)
repo_slug() {
    local u; u="$(origin_url)"
    u="${u#git@github.com:}"; u="${u#ssh://git@github.com/}"; u="${u#https://github.com/}"
    u="${u#"$REMOTE_BASE"}"; u="${u%.git}"
    printf '%s' "$u"
}

# Accepts owner/name, or a full SSH/HTTPS GitHub URL, and prints owner/name.
normalise_repo() {
    local s="$1"
    s="${s#git@github.com:}"; s="${s#ssh://git@github.com/}"
    s="${s#https://}"; s="${s#http://}"; s="${s#www.}"; s="${s#github.com/}"
    s="${s%/}"; s="${s%.git}"
    local re='^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$'
    [[ $s =~ $re ]] || return 1
    printf '%s' "$s"
}

valid_branch_name() { git check-ref-format --branch "$1" >/dev/null 2>&1; }

pause() { [ -t 0 ] && read -r -p "${D}Press Enter to go back to the menu${R} " _; }

# Look at a remote without changing anything. Sets:
#   REMOTE_STATE  missing | empty | content | noauth | error
#   REMOTE_HEAD   its default branch (if any)
#   REMOTE_HEADS  its branches, one per line
#   REMOTE_TAGS   its tags, one per line
probe_remote() {
    local url="$1" out
    REMOTE_HEAD=''; REMOTE_HEADS=''; REMOTE_TAGS=''; REMOTE_ERR=''
    if ! out="$(GIT_TERMINAL_PROMPT=0 git ls-remote --symref "$url" 2>&1)"; then
        REMOTE_ERR="$out"
        case "$out" in
            *"Permission denied"*|*"publickey"*|*"Host key verification failed"*)
                REMOTE_STATE=noauth ;;
            *"not found"*|*"Not Found"*|*"does not appear to be a git repository"*|*"does not exist"*)
                REMOTE_STATE=missing ;;
            *)  REMOTE_STATE=error ;;
        esac
        return
    fi
    REMOTE_HEAD="$(printf '%s\n' "$out" | sed -n 's#^ref: refs/heads/\([^[:space:]]*\)[[:space:]]*HEAD$#\1#p')"
    REMOTE_HEADS="$(printf '%s\n' "$out" | sed -n 's#^[0-9a-f]*[[:space:]]*refs/heads/##p')"
    REMOTE_TAGS="$(printf '%s\n' "$out" | sed -n 's#^[0-9a-f]*[[:space:]]*refs/tags/##p' | grep -v '\^{}$')"
    if [ -z "$REMOTE_HEADS" ] && [ -z "$REMOTE_TAGS" ]; then
        REMOTE_STATE=empty
    else
        REMOTE_STATE=content
    fi
}

ensure_identity() {
    if [ -n "$(git config user.name)" ] && [ -n "$(git config user.email)" ]; then
        return
    fi
    warn "Git needs a name and email to label your commits. Both are public on GitHub."
    say  "  Tip: GitHub gives you a private no-reply address under Settings > Emails."
    local n e
    ask "Name for commits:";  n="$REPLY"
    ask "Email for commits:"; e="$REPLY"
    [ -n "$n" ] && [ -n "$e" ] || die "Both a name and an email are needed."
    git config --global user.name "$n"
    git config --global user.email "$e"
    ok "Saved (for every repo on this computer)."
}

# Warn about tracked files that the .gitignore now says should be ignored.
check_tracked_ignored() {
    has_commits || return
    local list n
    list="$(git ls-files -ci --exclude-standard 2>/dev/null)"
    [ -z "$list" ] && return
    n="$(printf '%s\n' "$list" | wc -l | tr -d ' ')"
    warn "$n file(s) are in the repo but match .gitignore, e.g. $(printf '%s\n' "$list" | head -n 1)"
    say  "  Run ${B}untrack${R} to remove them from the repo (they stay on your disk)."
}

# Refuse files GitHub would reject (over 100 MB) before trying to push them.
check_big_files() {
    local big f
    big="$(find . -path ./.git -prune -o -type f -size +100M -print 2>/dev/null | while IFS= read -r f; do
        git check-ignore -q "$f" || printf '%s\n' "$f"; done)"
    [ -z "$big" ] && return 0
    err "These files are over GitHub's 100 MB limit, so the push would be rejected:"
    printf '%s\n' "$big" | sed 's/^/    /'
    say "  Add them to .gitignore (or use Git LFS) and run gitkit again."
    return 1
}

# ---------------------------------------------------------------------------
# First-time setup: connect this folder to a GitHub repo and push it
# ---------------------------------------------------------------------------

create_remote_repo() {
    local repo="$1" url="$2" vis
    warn "github.com/$repo doesn't exist (or your SSH key can't see it)."

    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        confirm "Create it on GitHub now?" || return 1
        ask "Public or private?" "private"; vis="$REPLY"
        case "$vis" in pub*|Pub*) vis="--public" ;; *) vis="--private" ;; esac
        gh repo create "$repo" "$vis" >/dev/null || { err "GitHub didn't create the repo."; return 1; }
        ok "Created github.com/$repo (${vis#--})"
    else
        if command -v gh >/dev/null 2>&1; then
            say "  The GitHub CLI is installed but not logged in. Run ${B}gh auth login${R} to"
            say "  let gitkit create repos for you next time."
        else
            say "  Install the GitHub CLI (https://cli.github.com) to let gitkit create repos."
        fi
        say "  For now, create an EMPTY repo called ${B}${repo#*/}${R} at https://github.com/new"
        say "  (no README, licence or .gitignore), then come back here."
        read -r -p "Press Enter once it exists (Ctrl-C to stop) " _
    fi

    probe_remote "$url"
    [ "$REMOTE_STATE" = "missing" ] && { err "Still can't see github.com/$repo."; return 1; }
    return 0
}

setup_repo() {
    title "Connect this folder to GitHub"
    say "Folder: $HERE"

    local created_git=0 repo url branch n msg parent
    if [ ! -e .git ]; then
        parent="$(git rev-parse --show-toplevel 2>/dev/null)"
        if [ -n "$parent" ]; then
            warn "This folder is inside another git repo ($parent)."
            confirm "Make it a separate repo anyway?" || exit 0
        fi
    fi

    while :; do
        ask "GitHub repo to push to (e.g. your-name/my-project):"
        [ -z "$REPLY" ] && exit 0
        repo="$(normalise_repo "$REPLY")" && break
        warn "That doesn't look like owner/repo-name - try again, or press Enter to quit."
    done
    url="${REMOTE_BASE}${repo}.git"

    info "Checking github.com/$repo ..."
    probe_remote "$url"
    case "$REMOTE_STATE" in
        noauth)  die "GitHub refused your SSH key. Check it with:  ssh -T git@github.com" ;;
        error)   die "Couldn't reach GitHub:"$'\n'"$REMOTE_ERR" ;;
        missing) create_remote_repo "$repo" "$url" || exit 1 ;;
    esac

    # Use the remote's default branch name so we replace it rather than adding a
    # second branch next to it. Brand-new repos get "main".
    branch="${REMOTE_HEAD:-main}"

    ensure_identity

    if [ ! -e .git ]; then
        git init -q -b "$branch" 2>/dev/null || { git init -q && git symbolic-ref HEAD "refs/heads/$branch"; }
        created_git=1
    fi

    if ! check_big_files; then
        [ "$created_git" = 1 ] && rm -rf .git
        exit 1
    fi

    git add -A
    n="$(git ls-files | wc -l | tr -d ' ')"
    if [ "$n" -eq 0 ]; then
        warn "There's nothing to upload - every file here is ignored or the folder is empty."
        [ "$created_git" = 1 ] && rm -rf .git
        exit 1
    fi

    title "Ready to upload $n file(s) to github.com/$repo  (as branch: $branch)"
    git ls-files | head -n 15 | sed 's/^/    /'
    [ "$n" -gt 15 ] && say "    ... and $((n - 15)) more"
    echo

    local go=1
    if [ "$REMOTE_STATE" = "content" ]; then
        warn "github.com/$repo already has content:"
        say  "    branches: $(printf '%s ' $REMOTE_HEADS)"
        [ -n "$REMOTE_TAGS" ] && say "    tags:     $(printf '%s ' $REMOTE_TAGS)"
        warn "Its '$branch' branch - files AND history - will be replaced by this folder."
        confirm_typed "$repo" || go=0
    else
        confirm "Push these files to github.com/$repo?" || go=0
    fi
    if [ "$go" = 0 ]; then
        say "Cancelled - nothing was pushed."
        if [ "$created_git" = 1 ]; then rm -rf .git; else git reset -q; fi
        exit 0
    fi

    # Match the remote's branch name (only now that you've said yes).
    if [ "$(current_branch)" != "$branch" ]; then
        if has_commits; then git branch -M "$branch"; else git symbolic-ref HEAD "refs/heads/$branch"; fi
    fi

    if [ -n "$(git diff --cached --name-only)" ] || ! has_commits; then
        if has_commits; then ask "Commit message:" "Upload from gitkit"; else ask "Commit message:" "Initial commit"; fi
        msg="$REPLY"
        git commit -q -m "$msg" || die "The commit failed."
    fi

    if git remote get-url origin >/dev/null 2>&1; then
        git remote set-url origin "$url"
    else
        git remote add origin "$url"
    fi

    info "Pushing..."
    git push -q -u --force origin "$branch" || die "The push failed (see the message above)."
    ok "github.com/$repo now matches this folder."

    # Anything else left over on GitHub from before?
    local others=() b t
    for b in $REMOTE_HEADS; do [ "$b" != "$branch" ] && others+=("$b"); done
    if [ ${#others[@]} -gt 0 ] || [ -n "$REMOTE_TAGS" ]; then
        echo
        warn "GitHub still has things this folder doesn't:"
        [ ${#others[@]} -gt 0 ] && say "    branches: ${others[*]}"
        [ -n "$REMOTE_TAGS" ] && say "    tags:     $(printf '%s ' $REMOTE_TAGS)"
        if confirm "Delete them too, so GitHub matches this folder exactly?"; then
            local refs=()
            for b in "${others[@]}"; do refs+=("refs/heads/$b"); done
            for t in $REMOTE_TAGS; do refs+=("refs/tags/$t"); done
            git push -q origin --delete "${refs[@]}" && ok "Deleted."
        fi
    fi

    echo
    say "From now on, run ${B}./$SELF_NAME${R} for the menu, or ${B}./push.sh${R} to commit and push."
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_status() {
    title "Status"
    local br up counts ahead behind
    br="$(current_branch)"
    say "Folder:  $HERE"
    say "GitHub:  $(repo_slug)"
    say "Branch:  ${br:-"(not on a branch)"}"
    up="$(upstream)"
    if [ -n "$up" ]; then
        GIT_TERMINAL_PROMPT=0 git fetch -q 2>/dev/null
        counts="$(git rev-list --left-right --count "HEAD...$up" 2>/dev/null)"
        ahead="${counts%%[[:space:]]*}"; behind="${counts##*[[:space:]]}"
        if [ "$ahead" = 0 ] && [ "$behind" = 0 ]; then
            say "Sync:    up to date with GitHub"
        else
            say "Sync:    $ahead commit(s) not pushed yet, $behind on GitHub you don't have"
        fi
    else
        say "Sync:    this branch isn't on GitHub yet ('push' will publish it)"
    fi
    echo
    if [ -z "$(git status --porcelain)" ]; then
        ok "No uncommitted changes."
    else
        say "Uncommitted changes:"
        git -c color.status=always status --short | sed 's/^/  /'
    fi
}

cmd_push() {
    local msg="$1" up ahead
    if [ -n "$(git status --porcelain)" ]; then
        say "Changes to be committed:"
        git status --short
        echo
        if [ -z "$msg" ]; then ask "What changed?"; msg="$REPLY"; fi
        if [ -z "$msg" ]; then warn "No message given - nothing committed."; return 1; fi
        git add -A
        git commit -q -m "$msg" || return 1
    fi

    up="$(upstream)"
    if [ -z "$up" ]; then
        has_commits || { say "Nothing to push yet."; return 0; }
        git push -q -u origin HEAD || return 1
        ok "Published branch '$(current_branch)' to GitHub."
        return 0
    fi

    ahead="$(git rev-list --count "$up..HEAD" 2>/dev/null)"
    if [ "${ahead:-0}" -eq 0 ]; then
        ok "Nothing to push - GitHub is up to date."
        return 0
    fi
    if ! git push -q; then
        warn "GitHub rejected the push - it probably has commits you don't. Run 'pull' first."
        return 1
    fi
    ok "Pushed."
}

cmd_pull() {
    info "Getting the latest from GitHub..."
    if git pull -q --ff-only 2>/dev/null; then
        ok "Up to date."
        return 0
    fi
    warn "Couldn't simply fast-forward: you and GitHub both have new commits,"
    say  "  or you have uncommitted changes in the way."
    confirm "Put your commits on top of GitHub's (rebase)?" || return 1
    if git pull --rebase --autostash; then
        ok "Done - your commits now sit on top of the latest from GitHub."
    else
        err "There are conflicts to sort out. Fix the files git lists, then run:"
        say "    git add -A && git rebase --continue"
        say "  or give up and go back to how things were with:  git rebase --abort"
        return 1
    fi
}

pick_branch() {
    # pick_branch "prompt" [include_remote]  -> branch name in $REPLY
    local i=1 b list
    list="$(git for-each-ref --format='%(refname:short)' refs/heads/)"
    if [ -n "$2" ]; then
        GIT_TERMINAL_PROMPT=0 git fetch -q 2>/dev/null
        list="$(printf '%s\n%s\n' "$list" "$(git for-each-ref --format='%(refname:short)' refs/remotes/origin/ \
            | sed 's#^origin/##' | grep -vxE 'HEAD|origin')" | awk 'NF && !seen[$0]++')"
    fi
    [ -z "$list" ] && { warn "No branches found."; return 1; }
    for b in $list; do
        if [ "$b" = "$(current_branch)" ]; then say "  $i) $b ${D}(current)${R}"; else say "  $i) $b"; fi
        i=$((i + 1))
    done
    ask "$1"
    case "$REPLY" in
        ''|*[!0-9]*) ;;
        *) REPLY="$(printf '%s\n' $list | sed -n "${REPLY}p")" ;;
    esac
    [ -n "$REPLY" ]
}

cmd_branch() {
    local name="$1"
    [ -z "$name" ] && { ask "Name for the new branch (e.g. new-homepage):"; name="$REPLY"; }
    [ -z "$name" ] && return 1
    valid_branch_name "$name" || { err "'$name' isn't a valid branch name (no spaces or odd symbols)."; return 1; }
    if git show-ref -q --verify "refs/heads/$name"; then
        warn "Branch '$name' already exists."
        confirm "Switch to it?" && git switch -q "$name" && ok "Now on '$name'."
        return
    fi
    git switch -q -c "$name" || return 1
    ok "Created and switched to '$name'. Any uncommitted changes came with you."
    if confirm "Publish it to GitHub now?"; then
        git push -q -u origin "$name" && ok "Published."
    else
        say "  It'll be published the first time you push from it."
    fi
}

cmd_switch() {
    local name="$1"
    if [ -z "$name" ]; then pick_branch "Switch to (number or name):" remote || return 1; name="$REPLY"; fi
    local out
    if out="$(git switch -q "$name" 2>&1)"; then
        ok "Now on '$name'."
    else
        printf '%s\n' "$out" >&2
        warn "Commit or 'stash' your changes first if git says they'd be overwritten."
        return 1
    fi
}

cmd_merge() {
    local name="$1" here
    here="$(current_branch)"
    if [ -z "$name" ]; then pick_branch "Merge which branch into '$here'? (number or name):" || return 1; name="$REPLY"; fi
    [ "$name" = "$here" ] && { warn "That's the branch you're on."; return 1; }
    if git merge --no-edit "$name"; then
        ok "Merged '$name' into '$here'. Run 'push' to send it to GitHub."
    else
        err "Conflicts. Edit the files git lists, then:  git add -A && git commit --no-edit"
        say "  or cancel the merge with:  git merge --abort"
        return 1
    fi
}

cmd_delete_branch() {
    local name="$1"
    if [ -z "$name" ]; then pick_branch "Delete which branch? (number or name):" || return 1; name="$REPLY"; fi
    [ "$name" = "$(current_branch)" ] && { err "You're on '$name' - switch to another branch first."; return 1; }
    if git show-ref -q --verify "refs/heads/$name"; then
        if ! git branch -q -d "$name" 2>/dev/null; then
            warn "'$name' has commits that aren't merged anywhere - deleting it loses them."
            confirm "Delete it anyway?" || return 1
            git branch -q -D "$name"
        fi
        ok "Deleted '$name' on this computer."
    fi
    if git ls-remote --exit-code --heads origin "$name" >/dev/null 2>&1; then
        confirm "Delete '$name' from GitHub too?" && git push -q origin --delete "$name" && ok "Deleted from GitHub."
    fi
}

cmd_stash() {
    [ -z "$(git status --porcelain)" ] && { ok "No changes to put aside."; return 0; }
    local msg; ask "Note to remember them by:" "work in progress"; msg="$REPLY"
    git stash push -q -u -m "$msg" && ok "Changes put aside. Use 'unstash' to bring them back."
}

cmd_unstash() {
    [ -z "$(git stash list)" ] && { ok "Nothing has been put aside."; return 0; }
    git stash list | sed 's/^/  /'
    if git stash pop -q; then ok "Brought back the most recent set of changes."; else
        err "They clash with current files. Sort out the conflicts; the stash is kept until you do."
        return 1
    fi
}

cmd_undo() {
    has_commits || { warn "There are no commits to undo."; return 1; }
    say "Last commit:"
    git --no-pager log -1 --format='  %h  %s  (%cr)'
    local up; up="$(upstream)"
    if [ -n "$up" ] && git merge-base --is-ancestor HEAD "$up" 2>/dev/null; then
        warn "That commit is already on GitHub."
        say  "  The safe way to undo it is a new commit that reverses it (history is kept)."
        confirm "Make that reversing commit?" || return 1
        git revert --no-edit HEAD && ok "Reversed. Run 'push' to send it to GitHub."
        return
    fi
    confirm "Undo it? The changes stay in your files, just uncommitted." || return 1
    if git rev-parse -q --verify HEAD~1 >/dev/null; then
        git reset -q --soft HEAD~1
    else
        git update-ref -d HEAD   # it was the very first commit
    fi
    ok "Undone. Your changes are still there, ready to commit again."
}

cmd_discard() {
    [ -z "$(git status --porcelain)" ] && { ok "Nothing to throw away."; return 0; }
    git status --short | sed 's/^/  /'
    warn "This throws away every uncommitted change above. It can't be undone."
    confirm_typed "discard" || { say "Cancelled."; return 1; }
    git reset -q --hard
    if [ -n "$(git clean -nd)" ]; then
        say "New files that were never committed:"
        git clean -nd | sed 's/^Would remove /  /'
        confirm "Delete those too?" && git clean -qfd
    fi
    ok "Back to the last commit."
}

cmd_log() {
    git --no-pager log --graph --decorate --color=auto -n "${1:-25}" \
        --format='%C(yellow)%h%C(reset) %s %C(dim)(%cr, %an)%C(reset)%C(auto)%d'
}

cmd_tag() {
    local name="$1"
    has_commits || { warn "Commit something first."; return 1; }
    if [ -n "$(git tag)" ]; then say "Existing tags: $(git tag | tr '\n' ' ')"; fi
    [ -z "$name" ] && { ask "Tag name for this version (e.g. v1.0):"; name="$REPLY"; }
    [ -z "$name" ] && return 1
    git tag -a "$name" -m "$name" || return 1
    git push -q origin "$name" && ok "Tagged this commit as '$name' and pushed the tag."
}

cmd_untrack() {
    if [ -n "$1" ]; then
        git rm -r -q --cached -- "$@" || return 1
        ok "No longer tracking: $*  (still on your disk). Run 'push' to update GitHub."
        return
    fi
    local list; list="$(git ls-files -ci --exclude-standard)"
    [ -z "$list" ] && { ok "Nothing tracked matches .gitignore."; return 0; }
    say "These are in the repo but match .gitignore:"
    printf '%s\n' "$list" | sed 's/^/  /'
    confirm "Remove them from the repo? (They stay on your disk.)" || return 1
    printf '%s\n' "$list" | while IFS= read -r f; do git rm -q --cached -- "$f"; done
    ok "Done. Run 'push' to update GitHub."
}

cmd_remote() {
    local repo
    say "Currently connected to: $(origin_url)"
    if [ -n "$1" ]; then REPLY="$1"; else ask "New GitHub repo (owner/name), or Enter to keep it:"; fi
    [ -z "$REPLY" ] && return 0
    repo="$(normalise_repo "$REPLY")" || { err "That doesn't look like owner/repo-name."; return 1; }
    git remote set-url origin "${REMOTE_BASE}${repo}.git"
    git branch -q --unset-upstream 2>/dev/null
    ok "Now connected to github.com/$repo. Nothing was pushed."
    say "  Use 'push' to publish the current branch there."
}

cmd_wipe_history() {
    local b msg tmp="gitkit-wipe-$$"
    b="$(current_branch)"
    [ -z "$b" ] && { err "Switch to a branch first."; return 1; }
    has_commits || { warn "There's no history to wipe yet."; return 1; }

    title "Replace all history on '$b' with one fresh commit"
    say "  - Keeps your files exactly as they are now (uncommitted changes included)."
    say "  - Deletes every earlier version of '$b', here and on GitHub."
    say "  - Useful after committing a password or a huge file by mistake."
    say "  - Other branches and tags are left alone (they may still hold old history)."
    warn "Anyone else with a copy will need to re-clone. This can't be undone."
    confirm_typed "$b" || { say "Cancelled."; return 1; }
    ask "Commit message:" "Fresh start"; msg="$REPLY"

    git checkout -q --orphan "$tmp" || return 1
    git add -A
    git commit -q -m "$msg" || { git checkout -q "$b"; return 1; }
    git branch -q -D "$b"
    git branch -m "$b"
    git push -q --force -u origin "$b" || { err "The push failed, but the local history has been replaced."; return 1; }
    ok "'$b' now has a single commit, here and on GitHub."

    if confirm "Also purge the old versions from this computer's git storage?"; then
        git reflog expire --expire=now --all && git gc -q --prune=now && ok "Purged."
    fi
    say "  If a password or key was ever pushed, change it anyway - assume it was seen."
}

cmd_open() {
    local slug url; slug="$(repo_slug)"
    url="https://github.com/$slug"
    [ -n "$(upstream)" ] && url="$url/tree/$(current_branch)"
    if command -v open >/dev/null 2>&1; then open "$url"
    elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1
    elif command -v explorer.exe >/dev/null 2>&1; then explorer.exe "$url"
    else say "$url"; fi
}

cmd_help() {
cat <<EOF
${B}gitkit $VERSION${R} - put a folder on GitHub and manage it.

Usage:  ./$SELF_NAME             menu (or first-time setup)
        ./$SELF_NAME <command>   run one command directly

  ${B}status${R}                 what's changed, and how you compare to GitHub
  ${B}push${R} ["message"]       commit everything and push
  ${B}pull${R}                   get the latest from GitHub
  ${B}branch${R} [name]          make a new branch and switch to it
  ${B}switch${R} [name]          switch to another branch
  ${B}merge${R} [name]           merge another branch into this one
  ${B}delete-branch${R} [name]   delete a branch (here and/or on GitHub)
  ${B}stash${R}                  put uncommitted changes aside
  ${B}unstash${R}                bring them back
  ${B}undo${R}                   undo the last commit, keeping its changes
  ${B}discard${R}                throw away all uncommitted changes
  ${B}log${R} [count]            recent history
  ${B}tag${R} [name]             mark this version, e.g. v1.0
  ${B}untrack${R} [path...]      stop tracking files (default: anything now in .gitignore)
  ${B}remote${R} [owner/name]    point this folder at a different GitHub repo
  ${B}wipe-history${R}           replace all history with one fresh commit
  ${B}open${R}                   open the repo on GitHub
  ${B}setup${R}                  connect this folder to a GitHub repo
  ${B}help${R}                   this list

Every run also makes sure .gitignore has the usual macOS/Windows/Linux junk
rules and ignores this script and push.sh, and creates push.sh if it's missing.
EOF
}

run_cmd() {
    local c="$1"; shift
    case "$c" in
        status|st)                  cmd_status ;;
        push|p)                     cmd_push "$*" ;;
        pull)                       cmd_pull ;;
        branch|new-branch|nb)       cmd_branch "$1" ;;
        switch|sw|checkout)         cmd_switch "$1" ;;
        merge)                      cmd_merge "$1" ;;
        delete-branch|db)           cmd_delete_branch "$1" ;;
        stash)                      cmd_stash ;;
        unstash|pop)                cmd_unstash ;;
        undo)                       cmd_undo ;;
        discard)                    cmd_discard ;;
        log|history)                cmd_log "$1" ;;
        tag)                        cmd_tag "$1" ;;
        untrack)                    cmd_untrack "$@" ;;
        remote)                     cmd_remote "$1" ;;
        wipe-history|wipe)          cmd_wipe_history ;;
        open|web)                   cmd_open ;;
        setup)                      say "Already connected to $(repo_slug). Use 'remote' to change it." ;;
        help|-h|--help)             cmd_help ;;
        *) err "Unknown command: $c"; say "Run ./$SELF_NAME help for the list."; return 1 ;;
    esac
}

menu() {
    local items="status push pull branch switch merge delete-branch stash unstash undo discard log tag untrack remote wipe-history open"
    local descs=(
        "See what's changed and how you compare to GitHub"
        "Commit everything and push"
        "Get the latest from GitHub"
        "Make a new branch"
        "Switch to another branch"
        "Merge another branch into this one"
        "Delete a branch"
        "Put uncommitted changes aside"
        "Bring them back"
        "Undo the last commit (keep the changes)"
        "Throw away all uncommitted changes"
        "Show recent history"
        "Mark this version (e.g. v1.0)"
        "Stop tracking files that are now in .gitignore"
        "Point this folder at a different GitHub repo"
        "Replace all history with one fresh commit"
        "Open the repo on GitHub"
    )
    local choice i name changes
    while :; do
        changes="$(git status --porcelain | wc -l | tr -d ' ')"
        title "gitkit  ${D}$(repo_slug)  ·  branch: $(current_branch)  ·  $changes uncommitted change(s)${R}"
        i=0
        for name in $items; do
            printf '  %2d) %-14s %s\n' $((i + 1)) "$name" "${D}${descs[$i]}${R}"
            i=$((i + 1))
        done
        say "   q) quit"
        read -r -p "> " choice || { echo; return; }
        case "$choice" in
            q|Q|quit|exit) return ;;
            '') continue ;;
            *[!0-9]*) ;;
            *) choice="$(printf '%s\n' $items | sed -n "${choice}p")" ;;
        esac
        [ -z "$choice" ] && { warn "Pick a number from the list."; continue; }
        echo
        run_cmd $choice
        echo
        pause
    done
}

# ---------------------------------------------------------------------------

main() {
    command -v git >/dev/null 2>&1 || die "git isn't installed."
    case "$1" in
        help|-h|--help) cmd_help; exit 0 ;;
        -v|--version)   say "gitkit $VERSION"; exit 0 ;;
    esac

    ensure_gitignore
    ensure_push_helper

    if [ ! -e .git ]; then
        setup_repo; exit $?
    fi
    if ! git remote get-url origin >/dev/null 2>&1; then
        warn "This is a git repo, but it isn't connected to GitHub yet."
        setup_repo; exit $?
    fi

    [ "$1" = "untrack" ] || check_tracked_ignored
    if [ $# -gt 0 ]; then
        run_cmd "$@"; exit $?
    fi
    menu
}

main "$@"
