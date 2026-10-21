#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_directory="$(mktemp -d)"

cleanup() {
	[[ -n "${temporary_directory}" && -d "${temporary_directory}" ]] && rm -rf -- "${temporary_directory}"
}

trap cleanup EXIT

# Creates '<base>/updated' (one commit behind the remote) and '<base>/unchanged',
# both backed by an isolated remote so that scenario preparations never make
# repositories from earlier scenarios stale.
prepare_project_pair() {
	local base="$1"
	local remote="${base}/remote.git"
	local seed="${base}/seed"

	mkdir -p "${base}"

	git init -q --bare -b main "${remote}"
	git init -q -b main "${seed}"
	git -C "${seed}" config user.email "gsync@example.com"
	git -C "${seed}" config user.name "gsync test"
	printf 'one\n' > "${seed}/file"
	git -C "${seed}" add file
	git -C "${seed}" commit -qm "initial commit"
	git -C "${seed}" remote add origin "${remote}"
	git -C "${seed}" push -qu origin main

	git clone -q "${remote}" "${base}/updated"

	# One commit is pushed after '<base>/updated' was cloned, so it becomes
	# outdated, while '<base>/unchanged' (cloned afterwards) is up to date.
	printf 'change\n' >> "${seed}/file"
	git -C "${seed}" add file
	git -C "${seed}" commit -qm "change"
	git -C "${seed}" push -q origin main

	git clone -q "${remote}" "${base}/unchanged"

	rm -rf -- "${seed}"
}

# Several paths, each with its own pair of repositories, must all be scanned.
first_directory="${temporary_directory}/first"
second_directory="${temporary_directory}/second"
mkdir -p "${first_directory}" "${second_directory}"
prepare_project_pair "${first_directory}"
prepare_project_pair "${second_directory}"

set +e
output=$("${repository_root}/gsync" "${first_directory}" "${second_directory}" 2>&1)
status=$?
set -e

if [[ "${status}" -ne 0 ]]; then
	echo "expected exit status 0 when every directory path contains repositories, got ${status}: ${output}" >&2
	exit 1
fi

if [[ "${output}" != *"summary: 4 repositories - 2 updated, 2 unchanged, 0 skipped, 0 failed"* ]]; then
	echo "the summary line does not report the combined counts of all paths: ${output}" >&2
	exit 1
fi

# The same path given repeatedly must behave exactly as if given once.
third_directory="${temporary_directory}/third"
mkdir -p "${third_directory}"
prepare_project_pair "${third_directory}"

set +e
output=$("${repository_root}/gsync" "${third_directory}" "${third_directory}" "${third_directory}" 2>&1)
status=$?
set -e

if [[ "${status}" -ne 0 ]]; then
	echo "expected exit status 0 when the same path is given repeatedly, got ${status}: ${output}" >&2
	exit 1
fi

if [[ "${output}" != *"summary: 2 repositories - 1 updated, 1 unchanged, 0 skipped, 0 failed"* ]]; then
	echo "repeated paths must not double the repository count: ${output}" >&2
	exit 1
fi

if [[ "${output}" == *$'\n'"warning: "* ]] || [[ "${output}" == "warning: "* ]]; then
	echo "repeated identical paths must not produce warnings: ${output}" >&2
	exit 1
fi

# Nested paths sharing the same repositories must collapse the duplicate
# reports into a single warning about the redundant path itself.
nested_directory="${temporary_directory}/nested"
mkdir -p "${nested_directory}"
prepare_project_pair "${nested_directory}"

set +e
output=$("${repository_root}/gsync" "${nested_directory}" "${nested_directory}/updated" 2>&1)
status=$?
set -e

if [[ "${status}" -ne 0 ]]; then
	echo "expected exit status 0 when a nested path duplicates a repository, got ${status}: ${output}" >&2
	exit 1
fi

if [[ "${output}" != *"summary: 2 repositories - 1 updated, 1 unchanged, 0 skipped, 0 failed"* ]]; then
	echo "the repository shared by nested paths must be counted only once: ${output}" >&2
	exit 1
fi

if [[ "${output}" != *"warning: ignoring repository entry '${nested_directory}/updated' because it is already inside '${nested_directory}'."* ]]; then
	echo "expected a single warning about the redundant path: ${output}" >&2
	exit 1
fi

if [[ "${output}" == *"ignoring duplicate repository"* ]]; then
	echo "a fully redundant path must not produce per-repository warnings: ${output}" >&2
	exit 1
fi

# If the redundant path also contributes new repositories, the duplicates go
# back to per-repository warnings for just those duplicates.
mixed_directory="${temporary_directory}/mixed"
mkdir -p "${mixed_directory}"
ln -s "${nested_directory}/updated" "${mixed_directory}/same"
git clone -q "${nested_directory}/remote.git" "${mixed_directory}/extra"

set +e
output=$("${repository_root}/gsync" "${nested_directory}" "${mixed_directory}" 2>&1)
status=$?
set -e

if [[ "${status}" -ne 0 ]]; then
	echo "expected exit status 0 for a partially redundant path, got ${status}: ${output}" >&2
	exit 1
fi

if [[ "${output}" != *"summary: 3 repositories"* ]]; then
	echo "a partially redundant path must still contribute its new repositories: ${output}" >&2
	exit 1
fi

if [[ $(printf '%s\n' "${output}" | grep -c "'${mixed_directory}/same' because it is already inside '${nested_directory}'") -ne 1 ]]; then
	echo "expected per-repository warnings for just the duplicated repositories: ${output}" >&2
	exit 1
fi

if [[ $(printf '%s\n' "${output}" | grep -c 'warning: ignoring repository entry') -ne 0 ]]; then
	echo "a partially redundant path must not be reported as a repository entry: ${output}" >&2
	exit 1
fi

# On a terminal, a blank line must separate the warnings from the progress bar.
set +e
output=$(script -q -e -c "'${repository_root}/gsync' '${nested_directory}' '${nested_directory}/updated'" /dev/null 2>&1)
status=$?
set -e
output=${output//$'\r'/} # the emulated terminal turns line feeds into CRLFs

if [[ "${status}" -ne 0 ]]; then
	echo "expected exit status 0 for the terminal-emulated run, got ${status}: ${output}" >&2
	exit 1
fi

if [[ "${output}" != *"already inside"*$'\n\n'*"Sync progress"* ]]; then
	echo "expected a blank line between the warnings and the progress bar: ${output}" >&2
	exit 1
fi

# A path without repositories must warn but not fail the run.
fourth_directory="${temporary_directory}/fourth"
empty_directory="${temporary_directory}/empty"
mkdir -p "${fourth_directory}" "${empty_directory}"
prepare_project_pair "${fourth_directory}"

set +e
output=$("${repository_root}/gsync" "${fourth_directory}" "${empty_directory}" 2>&1)
status=$?
set -e

if [[ "${status}" -ne 0 ]]; then
	echo "expected exit status 0 when one path is empty but another is not, got ${status}: ${output}" >&2
	exit 1
fi

if [[ "${output}" != *"summary: 2 repositories - 1 updated, 1 unchanged, 0 skipped, 0 failed"* ]]; then
	echo "the empty path must not prevent the other paths from syncing: ${output}" >&2
	exit 1
fi

if [[ $(printf '%s\n' "${output}" | grep -c 'warning: no .git directories found') -ne 1 ]]; then
	echo "expected exactly one warning for the empty path, got: ${output}" >&2
	exit 1
fi

# An invalid path must fail the run, even when other paths are valid.
invalid_directory="${temporary_directory}/does-not-exist"

set +e
output=$("${repository_root}/gsync" "${fourth_directory}" "${invalid_directory}" 2>&1)
status=$?
set -e

if [[ "${status}" -ne 1 ]]; then
	echo "expected exit status 1 when a path is invalid, got ${status}: ${output}" >&2
	exit 1
fi

if [[ "${output}" != *"not found or is unreadable or is not a directory"* ]]; then
	echo "the invalid path was not reported: ${output}" >&2
	exit 1
fi

if [[ "${output}" == *"summary:"* ]]; then
	echo "no summary may be printed when a path is invalid: ${output}" >&2
	exit 1
fi

# '--' must stop option parsing so paths may be treated as arguments.
fifth_directory="${temporary_directory}/fifth"
mkdir -p "${fifth_directory}"
prepare_project_pair "${fifth_directory}"

set +e
output=$("${repository_root}/gsync" -- "${fifth_directory}" 2>&1)
status=$?
set -e

if [[ "${status}" -ne 0 ]]; then
	echo "expected exit status 0 when using '--' before the path, got ${status}: ${output}" >&2
	exit 1
fi

if [[ "${output}" != *"summary: 2 repositories - 1 updated, 1 unchanged, 0 skipped, 0 failed"* ]]; then
	echo "the path after '--' was not scanned: ${output}" >&2
	exit 1
fi

# The help text must document the variadic usage.
set +e
output=$("${repository_root}/gsync" --help 2>&1)
status=$?
set -e

if [[ "${status}" -ne 0 ]]; then
	echo "expected exit status 0 for --help, got ${status}: ${output}" >&2
	exit 1
fi

if [[ "${output}" != *"Usage: gsync [<directory-path>...]"* ]]; then
	echo "the help text does not document the variadic usage: ${output}" >&2
	exit 1
fi

# An unknown option must fail before any synchronization happens.
set +e
output=$("${repository_root}/gsync" --unknown-option 2>&1)
status=$?
set -e

if [[ "${status}" -ne 1 ]]; then
	echo "expected exit status 1 for an unknown option, got ${status}: ${output}" >&2
	exit 1
fi

if [[ "${output}" != *"unknown option '--unknown-option'"* ]]; then
	echo "the unknown option was not reported: ${output}" >&2
	exit 1
fi

if [[ "${output}" == *"summary:"* ]]; then
	echo "an unknown option must not start a synchronization run: ${output}" >&2
	exit 1
fi
