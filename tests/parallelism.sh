#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_directory="$(mktemp -d)"

cleanup() {
	[[ -n "${temporary_directory}" && -d "${temporary_directory}" ]] && rm -rf -- "${temporary_directory}"
}

trap cleanup EXIT

projects_directory="${temporary_directory}/projects"
fake_bin_directory="${temporary_directory}/bin"
state_directory="${temporary_directory}/state"
mkdir -p "${projects_directory}" "${fake_bin_directory}" "${state_directory}"
printf '0\n' > "${state_directory}/active"
printf '0\n' > "${state_directory}/maximum"

for number in $(seq -w 1 9); do
	mkdir -p "${projects_directory}/project-${number}/.git"
done

cat > "${fake_bin_directory}/git" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

state_directory="${GSYNC_TEST_STATE:?}"

with_lock() {
	until mkdir "${state_directory}/lock" 2>/dev/null; do
		sleep 0.01
	done
	"$@"
	rmdir "${state_directory}/lock"
}

increment_active_pulls() {
	local active maximum
	active=$(<"${state_directory}/active")
	active=$((active + 1))
	printf '%s\n' "${active}" > "${state_directory}/active"
	maximum=$(<"${state_directory}/maximum")
	if (( active > maximum )); then
		printf '%s\n' "${active}" > "${state_directory}/maximum"
	fi
}

decrement_active_pulls() {
	local active
	active=$(<"${state_directory}/active")
	printf '%s\n' "$((active - 1))" > "${state_directory}/active"
}

case "$1" in
	branch)
		printf 'feature\n'
		;;
	rev-parse)
		printf 'deadbeef\n'
		;;
	symbolic-ref)
		exit 1
		;;
	ls-remote)
		printf 'ref: refs/heads/main\tHEAD\n'
		;;
	status)
		;;
	remote)
		printf 'upstream\n'
		;;
	switch)
		;;
	pull)
		with_lock increment_active_pulls
		sleep 0.2
		with_lock decrement_active_pulls
		;;
esac
EOF
chmod +x "${fake_bin_directory}/git"

output=$(PATH="${fake_bin_directory}:${PATH}" GSYNC_TEST_STATE="${state_directory}" "${repository_root}/gsync" "${projects_directory}" 2>&1)

maximum=$(<"${state_directory}/maximum")
if [[ "${maximum}" -ne 4 ]]; then
	echo "expected exactly 4 concurrent pulls, got ${maximum}" >&2
	exit 1
fi

for number in $(seq -w 1 9); do
	if [[ "${output}" != *"project-${number}"* ]]; then
		echo "missing result for project-${number}" >&2
		exit 1
	fi
done

previous_position=-1
for number in $(seq -w 1 9); do
	match="syncing '${projects_directory}/project-${number}' ('main' branch)..."
	before_match="${output%%"${match}"*}"
	if [[ "${before_match}" == "${output}" ]]; then
		echo "missing sync result for project-${number}" >&2
		exit 1
	fi
	position=${#before_match}
	if (( position <= previous_position )); then
		echo "results are not reported in repository order" >&2
		exit 1
	fi
	previous_position=${position}
done
