#!/bin/bash
#
# Verifies that this tree is exactly "upstream <release> + ClearML's own files".
#
# This repo shares no git history with upstream (see .github/CLEARML_SYNC.md), so the only
# definition of "our changes" is the diff against the upstream release we are based
# on. This script asserts that diff touches nothing outside the list below, and that
# the ClearML features are still present - i.e. that a sync did not silently drop or
# widen them.
#
# Usage:
#   .github/scripts/check_patch.sh                 # base = the version in src/sysoptions.h
#   .github/scripts/check_patch.sh DROPBEAR_2026.91
#
# Requires upstream's tags fetched under the upstream/ namespace:
#   git remote add upstream https://github.com/mkj/dropbear.git
#   git fetch upstream --no-tags 'refs/tags/*:refs/tags/upstream/*'

set -u -o pipefail

cd "$(dirname "$0")/../.." # paths below are relative to the repo root

# Every file ClearML owns. Anything else differing from upstream is unexpected drift.
clearml_files=(
	.github/CLEARML_SYNC.md
	.github/scripts/build_and_test.sh
	.github/scripts/check_patch.sh
	.github/scripts/test_features.sh
	.github/workflows/clearml-ci.yml
	.github/workflows/clearml-release.yml
	.github/workflows/clearml-sync.yml
	.gitignore
	Dockerfile
	build.sh
	build_openssh_sftp_server.sh
	openssh_sftp_server_build_static.Dockerfile
	src/svr-auth.c
	src/svr-chansession.c
	test_fixed_password_login.sh
)

# The base is whichever upstream release this tree says it is. Taking it from the tree
# rather than from our latest published release is what makes the check work unchanged on
# master and on a sync branch, where the tree is already the *new* upstream version.
base="${1:-}"
if [ -z "$base" ]; then
	version=$(sed -n 's/^#define DROPBEAR_VERSION "\(.*\)".*/\1/p' src/sysoptions.h)
	[ -n "$version" ] || {
		echo "could not read DROPBEAR_VERSION from src/sysoptions.h;" >&2
		echo "pass the base tag explicitly:  $0 DROPBEAR_2026.91" >&2
		exit 2
	}
	base="DROPBEAR_$version"
fi

ref="upstream/$base"
if ! git rev-parse -q --verify "$ref^{commit}" >/dev/null; then
	echo "missing ref '$ref'. Fetch upstream's tags first:" >&2
	echo "  git fetch upstream --no-tags 'refs/tags/*:refs/tags/upstream/*'" >&2
	exit 2
fi

failures=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }

echo "comparing the working tree against $ref"
echo

# Working tree, not HEAD: a sync is checked after `git apply` and before the commit.
# Untracked files count too, or a stray new file would slip through.
changed=$( { git diff --name-only "$ref"; git ls-files --others --exclude-standard; } | sort -u)
unexpected=$(comm -23 \
	<(printf '%s\n' "$changed") \
	<(printf '%s\n' "${clearml_files[@]}" | sort))

if [ -z "$unexpected" ]; then
	pass "no changes outside ClearML's ${#clearml_files[@]} files"
else
	fail "unexpected differences from upstream:"
	printf '        %s\n' $unexpected
fi

# The features themselves, in case a sync merged our files but ate the contents.
grep -q 'DROPBEAR_CLEARML_FIXED_PASSWORD' src/svr-auth.c &&
	grep -q 'constant_time_memcmp' src/svr-auth.c &&
	pass "svr-auth.c: fixed-password feature present, still constant-time" ||
	fail "svr-auth.c: DROPBEAR_CLEARML_FIXED_PASSWORD feature missing or altered"

grep -q 'getenv("SFTPSERVER_PATH")' src/svr-chansession.c &&
	pass "svr-chansession.c: SFTPSERVER_PATH override present" ||
	fail "svr-chansession.c: SFTPSERVER_PATH override missing"

echo
git diff --shortstat "$ref"
echo
if [ "$failures" -eq 0 ]; then
	echo "tree is upstream $base + ClearML's files, as expected"
else
	echo "$failures check(s) failed"
fi
exit $((failures > 0))
