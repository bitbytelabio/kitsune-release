#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# The server's database role, on a new data directory only: the postgres image
# skips this folder when one already exists.
#
# Not left to POSTGRES_USER, because the image makes that role a superuser, and
# a superuser bypasses row security outright. Every policy in the migrations
# would be decoration. ci.yml measures the same thing and refuses to run the
# RLS tests that way.
set -eu
psql -v ON_ERROR_STOP=1 -v app_password="$KITSUNE_DB_PASSWORD" --username "$POSTGRES_USER" <<'SQL'
CREATE ROLE kitsune LOGIN PASSWORD :'app_password';
CREATE DATABASE kitsune OWNER kitsune;
SQL
