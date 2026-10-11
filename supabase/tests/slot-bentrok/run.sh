#!/bin/bash
# usage: run.sh <db> <old|new>
S=/var/tmp/pgt; B=/usr/lib/postgresql/16/bin
P="$B/psql -h 127.0.0.1 -p 55432 -U postgres -v ON_ERROR_STOP=1 -q"
$B/psql -h 127.0.0.1 -p 55432 -U postgres -qc "drop database if exists $1" -c "create database $1" || exit 1
$P -d $1 -f $S/00_base.sql >/dev/null || exit 1
if [ "$2" = old ]; then $P -d $1 -f $S/rb.sql >/dev/null; else $P -d $1 -f $S/mig.sql >/dev/null; fi || exit 1
$P -d $1 -f $S/10_helpers.sql >/dev/null || exit 1
$P -d $1 -f $S/20_tes_bentrok.sql >/dev/null || exit 1
$P -d $1 -f $S/90_laporan.sql
