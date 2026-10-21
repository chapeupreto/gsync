`gsync` - a tool that recursively synchronizes the default branch for one or more git repositories

![demo](./demo.png)

# About

Suppose you have under your `~/code/` directory a structure like the one below:

```sh
├── awesome-project-1/
├── awesome-project-2/
├── awesome-project-3/
├── pet-project-1/
└── pet-project-2/
```

Now, you'd like to make sure all those projects have their local `main` (or `master`) git branch updated with the latest changes from the corresponding branch on the remote.
Instead of entering each one of those directories and then issuing a command like `git pull <remote> main`, you can just do `gsync ~/code/`
(or `gsync .` in case your current working directory is already `~/code/`) and gsync will perform that operation for you, recursively.

You can also pass several directory paths at once, e.g. `gsync ~/code ~/work`; every given path is scanned recursively, in the order the paths were given.

This "synchronization" (i.e., `git pull`) action only works if the git project being synchronized has exactly 1 remote configured.
Up to five repositories are synchronized concurrently; a progress bar tracks completed repositories while the sync is running. Their results are displayed in directory traversal order once synchronization completes.

The default branch name (i.e, `master`, `main`, etc) is determined by the tool from the configured remote; its name does not need to be `origin`.
Also, `gsync` will not mess your git repository in case it is in a state considered "dirty" (i.e., `git status` identified uncommitted changes).

# Requirements

- [Git](https://git-scm.com/)
- [Bash](https://www.gnu.org/software/bash/), version 5.1 or newer
- [wc](https://www.gnu.org/software/coreutils/wc) - available on every Linux distro
- [realpath](https://www.gnu.org/software/coreutils/realpath) - available on every Linux distro

# Installation

`gsync` is installed to `$HOME/.local/bin/`, which must exist and be defined on your shell `PATH` so the `gsync` command can be invoked from anywhere.

Make sure `$HOME/.local/bin/` exists and is on your `PATH` before installing:

```sh
mkdir -vp $HOME/.local/bin
```

If `$HOME/.local/bin/` is not yet on your `PATH`, add the following line to your shell configuration file (`~/.bashrc` for Bash or `~/.zshrc` for Zsh):

```sh
export PATH=$HOME/.local/bin:$PATH
```

For Fish, whose syntax differs, add the following line to `~/.config/fish/config.fish` instead:

```fish
fish_add_path $HOME/.local/bin
```

Then, restart your shell (or run `source ~/.bashrc`, `source ~/.zshrc` or `source ~/.config/fish/config.fish`, depending on your shell) so the new `PATH` takes effect. Note that `fish_add_path` stores the change persistently, so Fish picks it up automatically in new sessions.

Finally, install `gsync`:

```sh
git clone https://github.com/chapeupreto/gsync
cd gsync
chmod +x gsync
cp -vip gsync $HOME/.local/bin/gsync
```

You can verify the installation worked by running:

```sh
gsync --version
```

# Usage

```sh
gsync [<directory-path>...]
```

When no argument is given, `gsync` uses the current working directory by default; otherwise every `<directory-path>` argument names a directory that is scanned recursively for git repositories, in the order the paths are given. You can pass `--` before the directory paths (e.g. `gsync -- -weird-dir`) so they are never interpreted as options; `-h`/`-v` are accepted anywhere in the argument list.

A path that does not exist, is unreadable, or is not a directory makes the run fail immediately. A path that contains no git repository produces a warning, and the run fails with an error only when no repository is found across all the given paths. Paths given more than once (identically, or resolving to the same directory through symlinks) are silently treated as if given once. When *distinct* paths share repositories (e.g. one path nested inside another), a repository is still synchronized only once: if a path contributes nothing new, a single warning about the path itself is printed (`warning: ignoring repository entry '<path>' because it is already inside '<other path>'.`); if it also contributes new repositories, a warning is printed for each duplicated repository.

At the end of the run, `gsync` prints a summary of every repository it examined:

```
summary: 10 repositories - 3 updated, 6 unchanged, 1 skipped, 0 failed
```

`gsync` exits with status `0` when every repository was updated or already up to date, with status `1` when any repository failed to synchronize, and with status `2` when at least one repository was skipped (e.g. because it was dirty or did not have exactly 1 remote configured) but none failed. An invalid invocation (an unknown option, or a directory path that does not exist, is unreadable, or is not a directory) also exits with status `1`, before any repository is synchronized. When a pull fails, the error reported by git is shown and the repository is left on its original branch (or detached commit).

# Tests

Run the test suite with:

```sh
for test in tests/*.sh; do bash "$test"; done
```

- `tests/parallelism.sh` checks the synchronization concurrency limit and progress bar.
- `tests/failures.sh` checks failure reporting, the exit status, and that a failed synchronization does not change the checked-out branch.
- `tests/summary.sh` checks the end-of-run summary line and the exit status for updated, unchanged, skipped, and failed repositories.
- `tests/multiple-paths.sh` checks variadic directory paths, repository deduplication and its warnings, empty and invalid paths, `--`, help, and unknown options.
- `tests/detached-head.sh` checks that a detached HEAD is preserved.
