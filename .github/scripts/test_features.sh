#!/bin/bash
#
# Non-interactive tests for ClearML's additions to Dropbear, run against the binaries
# in build/$platform/. This is what CI gates on.
#
#   1. DROPBEAR_CLEARML_FIXED_PASSWORD lets any username log in with that password,
#      as the user the server runs as               (src/svr-auth.c)
#   2. a wrong password is still rejected           (src/svr-auth.c)
#   3. SFTPSERVER_PATH picks the sftp-server binary (src/svr-chansession.c)
#   4. without DROPBEAR_CLEARML_FIXED_PASSWORD there is no password bypass
#
# Usage:
#   ./build.sh && ./build_openssh_sftp_server.sh    # produce the binaries first
#   .github/scripts/test_features.sh
#   platform=linux/arm64 .github/scripts/test_features.sh
#
# Prints PASS/FAIL per case and exits non-zero if any case failed. Needs docker and an
# OpenSSH client >= 8.4 (for SSH_ASKPASS_REQUIRE); no other tools.
#
# For a hands-on login instead of a pass/fail run, use ./test_fixed_password_login.sh,
# which starts the same server and drops you into an interactive SSH session.

set -u -o pipefail

cd "$(dirname "$0")/../.." # binaries are looked up relative to the repo root

platform="${platform:-linux/amd64}"
port="${port:-10022}"
password="pa55w0rD"
bin_dir="$PWD/build/$platform"
image="ubuntu:24.04"
container="dropbear-test-$$"
tmp_dir="$(mktemp -d)"
failures=0

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }

cleanup() {
	docker rm -f "$container" >/dev/null 2>&1
	rm -rf "$tmp_dir"
}
trap cleanup EXIT

# --- ssh/sftp without an interactive prompt -----------------------------------
# SSH_ASKPASS_REQUIRE=force makes OpenSSH ask this helper for the password even
# when it has a terminal, so no sshpass/expect is needed.
printf '#!/bin/sh\nprintf %%s "$TEST_PASSWORD"\n' >"$tmp_dir/askpass"
chmod +x "$tmp_dir/askpass"
export SSH_ASKPASS="$tmp_dir/askpass" SSH_ASKPASS_REQUIRE=force

ssh_opts=(
	-o "Port=$port"
	-o UserKnownHostsFile=/dev/null
	-o StrictHostKeyChecking=no
	-o PreferredAuthentications=password
	-o PubkeyAuthentication=no
	-o NumberOfPasswordPrompts=1
	-o ConnectTimeout=10
	-o LogLevel=ERROR
)

# --- the server under test ----------------------------------------------------
# Wait for dropbear's SSH banner. Docker's port proxy accepts connections before
# the server inside is listening, so "the port is open" proves nothing.
wait_for_ssh_banner() {
	local banner
	for _ in $(seq 60); do
		if exec 3<>/dev/tcp/127.0.0.1/"$port" 2>/dev/null; then
			read -t 2 -u 3 banner
			exec 3<&-
			[[ ${banner:-} == SSH-* ]] && return 0
		fi
		docker ps -q --filter "name=$container" | grep -q . || break
		sleep 0.5
	done
	echo "no SSH banner on port $port; container log:" >&2
	docker logs "$container" >&2 2>&1
	return 1
}

# $@ is passed to docker run, so the caller decides which env vars dropbear sees.
# Extra dropbear command-line args come from DROPBEAR_ARGS (default: -r /tmp/hostkey);
# set DROPBEAR_AS_ROOT=1 to run the server as root (needed by the usermap case).
start_server() {
	local user_args="--user 1000"
	[ -n "${DROPBEAR_AS_ROOT:-}" ] && user_args=""
	docker rm -f "$container" >/dev/null 2>&1
	docker run -d --name "$container" --platform "$platform" $user_args \
		-p "$port:$port" -v "$bin_dir:/dropbear:ro" \
		-e SFTPSERVER_PATH=/dropbear/sftp-server "$@" \
		"$image" sh -c "
			/dropbear/dropbearmulti dropbearkey -t ed25519 -f /tmp/hostkey >/dev/null &&
			exec /dropbear/dropbearmulti dropbear -e -F -p $port ${DROPBEAR_ARGS:--r /tmp/hostkey}" >/dev/null || return 1
	wait_for_ssh_banner
}

echo "platform=$platform  binaries=$bin_dir"
for binary in dropbearmulti sftp-server; do
	if [ ! -f "$bin_dir/$binary" ]; then
		echo "missing $bin_dir/$binary - run ./build.sh and ./build_openssh_sftp_server.sh first" >&2
		exit 2
	fi
done

# The binary runs at all on this platform, and says which version it is.
docker run --rm --platform "$platform" -v "$bin_dir:/dropbear:ro" "$image" \
	/dropbear/dropbearmulti dropbear -V || exit 2

# --- cases 1-3: server started WITH the fixed password ------------------------
start_server -e "DROPBEAR_CLEARML_FIXED_PASSWORD=$password" || exit 2

# Any username is accepted and remapped to the user the server runs as (uid 1000).
if out=$(TEST_PASSWORD="$password" ssh "${ssh_opts[@]}" anyuser@localhost 'echo READY_$(id -u)' 2>"$tmp_dir/err") &&
	[ "$out" = "READY_1000" ]; then
	pass "fixed-password login as any user, remapped to uid 1000"
else
	fail "fixed-password login (got '${out:-}', stderr: $(tr '\n' ' ' <"$tmp_dir/err"))"
fi

if TEST_PASSWORD="wrong-$password" ssh "${ssh_opts[@]}" anyuser@localhost true 2>/dev/null; then
	fail "wrong password was ACCEPTED"
else
	pass "wrong password rejected"
fi

echo "clearml-sftp-payload" >"$tmp_dir/up.txt"
# BatchMode=no must come before -b, which would otherwise turn password auth off.
if TEST_PASSWORD="$password" sftp "${ssh_opts[@]}" -o BatchMode=no -b - anyuser@localhost \
	>"$tmp_dir/sftp.log" 2>&1 <<-EOF &&
		put $tmp_dir/up.txt /tmp/roundtrip.txt
		get /tmp/roundtrip.txt $tmp_dir/down.txt
	EOF
	cmp -s "$tmp_dir/up.txt" "$tmp_dir/down.txt"; then
	pass "SFTP round-trip via SFTPSERVER_PATH"
else
	fail "SFTP round-trip ($(tr '\n' ' ' <"$tmp_dir/sftp.log"))"
fi

# --- case 4: server started WITHOUT the fixed password ------------------------
start_server || exit 2
if TEST_PASSWORD="$password" ssh "${ssh_opts[@]}" anyuser@localhost true 2>/dev/null; then
	fail "login succeeded with DROPBEAR_CLEARML_FIXED_PASSWORD unset - auth bypass!"
else
	pass "no password bypass when DROPBEAR_CLEARML_FIXED_PASSWORD is unset"
fi

# --- cases 5-6: usermap -------------------------------------------------------
# --user-map maps a login name to a system uid with a fixed password. The target
# must exist in /etc/passwd, so this server runs as root and maps to uid 0.
# DROPBEAR_ARGS replaces the default "-r /tmp/hostkey", so it is given again.
DROPBEAR_AS_ROOT=1 DROPBEAR_ARGS="-r /tmp/hostkey --user-map usermapuser:0:${password}" start_server || exit 2

if out=$(TEST_PASSWORD="$password" ssh "${ssh_opts[@]}" usermapuser@localhost 'echo MAP_$(id -u)' 2>"$tmp_dir/err") &&
	[ "$out" = "MAP_0" ]; then
	pass "usermap login maps to the target uid"
else
	fail "usermap login (got '${out:-}', stderr: $(tr '\n' ' ' <"$tmp_dir/err"))"
fi

if TEST_PASSWORD="wrong-$password" ssh "${ssh_opts[@]}" usermapuser@localhost true 2>/dev/null; then
	fail "usermap wrong password was ACCEPTED"
else
	pass "usermap wrong password rejected"
fi

# A user not in the usermap must not be able to log in with the usermap password.
if TEST_PASSWORD="$password" ssh "${ssh_opts[@]}" nomapuser@localhost true 2>/dev/null; then
	fail "non-usermap user logged in with the usermap password"
else
	pass "non-usermap user rejected"
fi

# --- case 7: --memory-host-key ------------------------------------------------
# Host keys are generated in memory; no key file is needed on disk.
DROPBEAR_ARGS="--memory-host-key" start_server -e "DROPBEAR_CLEARML_FIXED_PASSWORD=$password" || exit 2
if out=$(TEST_PASSWORD="$password" ssh "${ssh_opts[@]}" anyuser@localhost 'echo MEMORY_$(id -u)' 2>"$tmp_dir/err") &&
	[ "$out" = "MEMORY_1000" ]; then
	pass "in-memory host key login"
else
	fail "in-memory host key login (got '${out:-}', stderr: $(tr '\n' ' ' <"$tmp_dir/err"))"
fi

echo
if [ "$failures" -eq 0 ]; then
	echo "all tests passed"
else
	echo "$failures test(s) failed"
fi
exit $((failures > 0))
