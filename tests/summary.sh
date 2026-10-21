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

git init -q --bare -b main "${remote_directory}"
git init -q -b main "${seed_directory}"
git -C "${seed_directory}" config user.email "gsync@example.com"
git -C "${seed_directory}" config user.name "gsync test"
printf 'one\n' > "${seed_directory}/file"
git -C "${seed_directory}" add file
git -C "${seed_directory}" commit -qm "initial commit"
git -C "${seed_directory}" remote add origin "${remote_directory}"
git -C "${seed_directory}" push -qu origin main

propagate_main() {
	printf 'change %s\n' "$1" >> "${seed_directory}/file"
	git -C "${seed_directory}" add file
	git -C "${seed_directory}" commit -qm "change $1"
	git -C "${seed_directory}" push -q origin main
}

# One repository updated and one unchanged, so the summary must use status 0.
healthy_projects_directory="${temporary_directory}/healthy-projects"
mkdir -p "${healthy_projects_directory}"
git clone -q "${remote_directory}" "${healthy_projects_directory}/updated"
propagate_main "first"
git clone -q "${remote_directory}" "${healthy_projects_directory}/unchanged"

set +e
output=$("${repository_root}/gsync" "${healthy_projects_directory}" 2>&1)
status=$?
set -e

if [[ "${status}" -ne 0 ]]; then
	echo "expected exit status 0 when all repositories synchronize, got ${status}" >&2
	exit 1
fi

if [[ "${output}" != *"summary: 2 repositories - 1 updated, 1 unchanged, 0 skipped, 0 failed"* ]]; then
	echo "the summary line does not report the expected counts: ${output}" >&2
	exit 1
fi

# A skipped repository (dirty tree, no failures) makes the summary use status 2.
skipped_projects_directory="${temporary_directory}/skipped-projects"
mkdir -p "${skipped_projects_directory}"
git clone -q "${remote_directory}" "${skipped_projects_directory}/dirty"
printf 'untracked\n' > "${skipped_projects_directory}/dirty/untracked-file"

set +e
output=$("${repository_root}/gsync" "${skipped_projects_directory}" 2>&1)
status=$?
set -e

if [[ "${status}" -ne 2 ]]; then
	echo "expected exit status 2 when a repository is skipped without failures, got ${status}" >&2
	exit 1
fi

if [[ "${output}" != *"summary: 1 repository - 0 updated, 0 unchanged, 1 skipped, 0 failed"* ]]; then
	echo "the summary line does not report the skipped repository: ${output}" >&2
	exit 1
fi

if [[ "${output}" != *"because it is dirty"* ]]; then
	echo "the skipped repository was not reported" >&2
	exit 1
fi

# A failed synchronization takes precedence over a skipped one, using status 1.
mixed_projects_directory="${temporary_directory}/mixed-projects"
mkdir -p "${mixed_projects_directory}"
git clone -q "${remote_directory}" "${mixed_projects_directory}/dirty"
printf 'untracked\n' > "${mixed_projects_directory}/dirty/untracked-file"
git clone -q "${remote_directory}" "${mixed_projects_directory}/broken"
git -C "${mixed_projects_directory}/broken" remote set-url origin "${temporary_directory}/missing.git"

set +e
output=$("${repository_root}/gsync" "${mixed_projects_directory}" 2>&1)
status=$?
set -e

if [[ "${status}" -ne 1 ]]; then
	echo "expected exit status 1 when a repository fails to synchronize, got ${status}" >&2
	exit 1
fi

if [[ "${output}" != *"summary: 2 repositories - 0 updated, 0 unchanged, 1 skipped, 1 failed"* ]]; then
	echo "the summary line does not report the failed and skipped repositories: ${output}" >&2
	exit 1
fi
