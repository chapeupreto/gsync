`gysnc` - a tool that recursively synchronizes the default branch for one or more git repositories

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
Instead of entering each one of those directories and then issuing a command like `git pull origin main`, you can just do `gsync ~/code/`
(or `gsync .` in case your current working directory is already `~/code/`) and gsync will perform that operation for you, recursively.

This "synchronization" (i.e., `git pull`) action only works if the git project being synchronized has exactly 1 remote configured.

The default branch name (i.e, `master`, `main`, etc) is determined by the tool.
Also, `gsync` will not mess your git repository in case it is in a state considered "dirty" (i.e., `git status` identified uncommitted changes).

# Requirements

- [Git](https://git-scm.com/)
- [Bash](https://www.gnu.org/software/bash/), version 5.1 or newer
- [wc](https://www.gnu.org/software/coreutils/wc) - available on every Linux distro

# Installation

```sh
git clone https://github.com/chapeupreto/gsync
cd gsync
chmod +x gsync
cp -vip gsync $HOME/.local/bin
```

# Usage

```sh
gsync <directory-path>
```

`gsync` requires only one argument which is the directory path where your git repositories live in.
