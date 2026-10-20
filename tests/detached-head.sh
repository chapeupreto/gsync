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
project="${projects_directory}/detached"

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
git clone -q "${remote_directory}" "${project}"
git -C "${project}" checkout -q --detach HEAD
detached_commit=$(git -C "${project}" rev-parse HEAD)

assert_detached_at_original_commit() {
	if git -C "${project}" symbolic-ref -q HEAD >/dev/null; then
		echo "the repository was moved off the detached HEAD" >&2
		exit 1
	fi

	if [[ "$(git -C "${project}" rev-parse HEAD)" != "${detached_commit}" ]]; then
		echo "the detached HEAD was moved to another commit" >&2
		exit 1
	fi
}

set +e
output=$("${repository_root}/gsync" "${projects_directory}" 2>&1)
status=$?
set -e

if [[ "${status}" -ne 0 ]]; then
	echo "expected exit status 0 when the synchronization succeeds, got ${status}" >&2
	exit 1
fi

assert_detached_at_original_commit

printf 'two\n' > "${seed_directory}/another-file"
git -C "${seed_directory}" add another-file
git -C "${seed_directory}" commit -qm "second commit"
git -C "${seed_directory}" push -q origin main

set +e
output=$("${repository_root}/gsync" "${projects_directory}" 2>&1)
status=$?
set -e

if [[ "${status}" -ne 0 ]]; then
	echo "expected exit status 0 when the synchronization succeeds, got ${status}" >&2
	exit 1
fi

if [[ "${output}" != *"done!"*"updated"* ]]; then
	echo "the updated repository was not reported as updated" >&2
	exit 1
fi

assert_detached_at_original_commit

if [[ "$(git -C "${project}" rev-parse main)" != "$(git -C "${seed_directory}" rev-parse HEAD)" ]]; then
	echo "the default branch was not updated while the repository was detached" >&2
	exit 1
fi

if [[ -n "$(git -C "${project}" status --porcelain)" ]]; then
	echo "the working tree was left dirty after the synchronization" >&2
	exit 1
fi
