#!/bin/bash
#
# Builds the dropbear binaries and runs the tests for ClearML's additions, for one or
# more platforms. CI runs exactly this, so a green run here means a green run there.
#
#   .github/scripts/build_and_test.sh                          # linux/amd64
#   .github/scripts/build_and_test.sh linux/amd64 linux/arm64  # both, in turn
#   platform=linux/arm64 .github/scripts/build_and_test.sh     # as build.sh takes it
#
# Every platform is attempted even if an earlier one fails; the exit code is non-zero
# if any failed. CI calls this once per platform, on a native runner of that
# architecture, so nothing is emulated there.

set -uo pipefail

cd "$(dirname "$0")/../.." # the build scripts expect the repo root

# Platforms from the command line, else $platform (what the other build scripts use).
platforms="$*"
platforms="${platforms:-${platform:-linux/amd64}}"

failed=""
for target in $platforms; do
	printf '\n======== %s\n\n' "$target"
	if (
		export platform="$target"
		./build.sh &&                     # -> build/$platform/dropbearmulti
			./build_openssh_sftp_server.sh && # -> build/$platform/sftp-server
			.github/scripts/test_features.sh
	); then
		echo "OK    $target"
	else
		echo "FAIL  $target"
		failed="$failed $target"
	fi
done

echo
if [ -n "$failed" ]; then
	echo "failed:$failed"
	exit 1
fi
echo "passed: $platforms"
