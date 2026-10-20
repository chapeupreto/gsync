#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_directory="$(mktemp -d)"

cleanup() {
	[[ -n "${temporary_directory}" && -d "${temporary_directory}" ]] && rm -rf -- "${temporary_directory}"
}

trap cleanup EXIT

remote_directory="${temporary_directory}/remote.git"
seed_directory="${temporary_directory}/seed"
projects_directory="${temporary_directory}/projects"

git init -q --bare -b main "${remote_directory}"
git init -q -b main "${seed_directory}"
git -C "${seed_directory}" config user.email "gsync@example.com"
git -C "${seed_directory}" config user.name "gsync test"
printf 'one\n' > "${seed_directory}/file"
git -C "${seed_directory}" add file
git -C "${seed_directory}" commit -qm "initial commit"
git -C "${seed_directory}" remote add origin "${remote_directory}"
git -C "${seed_directory}" push -qu origin main

mkdir -p "${projects_directory}"
git clone -q "${remote_directory}" "${projects_directory}/healthy"
git clone -q "${remote_directory}" "${projects_directory}/broken"
git -C "${projects_directory}/broken" checkout -q -b feature
git -C "${projects_directory}/broken" remote set-url origin "${temporary_directory}/missing.git"

set +e
output=$("${repository_root}/gsync" "${projects_directory}" 2>&1)
status=$?
set -e

if [[ "${status}" -ne 1 ]]; then
	echo "expected exit status 1 when a repository fails to sync, got ${status}" >&2
	exit 1
fi

broken_output=${output#*"syncing '${projects_directory}/broken'"}
broken_output=${broken_output%%"syncing '"*}
if [[ "${broken_output}" != *"failed."* ]]; then
	echo "the failed pull was not reported as failed" >&2
	exit 1
fi

if [[ "${broken_output}" == *"done!"* ]]; then
	echo "the failed pull was reported as successful" >&2
	exit 1
fi

if [[ "${broken_output}" != *"does not appear to be a git repository"* ]]; then
	echo "git's pull error was not reported" >&2
	exit 1
fi

healthy_output=${output#*"syncing '${projects_directory}/healthy'"}
healthy_output=${healthy_output%%"syncing '"*}
if [[ "${healthy_output}" != *"done!"* ]]; then
	echo "the healthy repository was not synchronized" >&2
	exit 1
fi

if [[ "$(git -C "${projects_directory}/broken" branch --show-current)" != "feature" ]]; then
	echo "the original branch was not restored after a failed pull" >&2
	exit 1
fi

# A repository whose default branch is checked out in another worktree cannot
# switch to it; gsync must fail instead of pulling into the current branch.
worktree_projects_directory="${temporary_directory}/worktree-projects"
worktree_project="${worktree_projects_directory}/repo"

mkdir -p "${worktree_projects_directory}"
git clone -q "${remote_directory}" "${worktree_project}"
git -C "${worktree_project}" config user.email "gsync@example.com"
git -C "${worktree_project}" config user.name "gsync test"
git -C "${worktree_project}" checkout -q -b feature
printf 'local\n' > "${worktree_project}/local-file"
git -C "${worktree_project}" add local-file
git -C "${worktree_project}" commit -qm "local work"
feature_commit=$(git -C "${worktree_project}" rev-parse HEAD)
main_commit=$(git -C "${worktree_project}" rev-parse main)
git -C "${worktree_project}" worktree add -q "${temporary_directory}/main-worktree" main

printf 'two\n' > "${seed_directory}/another-file"
git -C "${seed_directory}" add another-file
git -C "${seed_directory}" commit -qm "advance main"
git -C "${seed_directory}" push -q origin main

set +e
output=$("${repository_root}/gsync" "${worktree_projects_directory}" 2>&1)
status=$?
set -e

if [[ "${status}" -ne 1 ]]; then
	echo "expected exit status 1 when the default branch cannot be checked out, got ${status}" >&2
	exit 1
fi

if [[ "${output}" != *"could not switch to 'main' branch"* ]]; then
	echo "the failed branch switch was not reported" >&2
	exit 1
fi

if [[ "$(git -C "${worktree_project}" branch --show-current)" != "feature" ]]; then
	echo "the repository was left on the wrong branch" >&2
	exit 1
fi

if [[ "$(git -C "${worktree_project}" rev-parse HEAD)" != "${feature_commit}" ]]; then
	echo "the current branch was changed by the failed synchronization" >&2
	exit 1
fi

if [[ "$(git -C "${worktree_project}" rev-parse main)" != "${main_commit}" ]]; then
	echo "the default branch was changed by the failed synchronization" >&2
	exit 1
fi
