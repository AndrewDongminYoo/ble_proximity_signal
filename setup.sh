#!/usr/bin/env bash
set -euo pipefail

# cspell:words flutterfire redir tlsv

# Cloud development environment for ble_proximity_signal.
# The environment is defined by merry-setup and pinned to an immutable revision:
# https://github.com/AndrewDongminYoo/merry-setup
#
# To move to a newer merry-setup, change MERRY_SETUP_REVISION to another full commit SHA.
# The options below describe this project and change only when its toolchain does.

readonly MERRY_SETUP_REVISION=a946d67a2071735250fc244842bcd4015052ec47
readonly MERRY_SETUP_URL="https://raw.githubusercontent.com/AndrewDongminYoo/merry-setup/${MERRY_SETUP_REVISION}/bin/merry-setup"
readonly MERRY_SETUP_BIN="${HOME}/.merry-setup/bin/merry-setup-${MERRY_SETUP_REVISION}"

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

[[ ${MERRY_SETUP_REVISION} =~ ^[0-9a-f]{40}$ ]] || die "MERRY_SETUP_REVISION must be a full commit SHA."

# Download to a file and publish it by rename, so a partial transfer never becomes the executable.
if [[ ! -x ${MERRY_SETUP_BIN} ]]; then
	command -v curl >/dev/null 2>&1 || die "curl is required to download merry-setup."
	mkdir -p -- "${MERRY_SETUP_BIN%/*}"
	staged="$(mktemp "${MERRY_SETUP_BIN}.XXXXXX")"
	if ! curl --fail --silent --show-error --location \
		--proto '=https' --proto-redir '=https' --tlsv1.2 \
		--retry 3 --retry-delay 2 \
		--output "${staged}" "${MERRY_SETUP_URL}"; then
		rm -f -- "${staged}"
		die "Failed to download merry-setup ${MERRY_SETUP_REVISION}."
	fi
	chmod 0755 "${staged}"
	mv -f -- "${staged}" "${MERRY_SETUP_BIN}"
fi

exec "${MERRY_SETUP_BIN}" setup \
	--sdk flutter \
	--bootstrap melos \
	--persist-path bashrc \
	--dart-package flutterfire_cli \
	--dart-package fluttium_cli \
	--precache linux,web
