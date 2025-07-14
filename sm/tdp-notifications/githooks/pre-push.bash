#!/bin/bash

# An hook script to verify what is about to be pushed.  Called by "git
# push" after it has checked the remote status, but before anything has been
# pushed.  If this script exits with a non-zero status nothing will be pushed.
#
# This hook is called with the following parameters:
#
# $1 -- Name of the remote to which the push is being done
# $2 -- URL to which the push is being done
#
# If pushing without using a named remote those arguments will be equal.
#
# Information about the commits which are being pushed is supplied as lines to
# the standard input in the form:
#
#   <local ref> <local oid> <remote ref> <remote oid>

remote="$1"
url="$2"

echo "Running pre-push hook"

# make target in directory if it exists
# parameters:
# $1 - directory where Makefile exists
# $2 - target to test and run
make_if_exists() {
  DIR=$1
  TARGET=$2

  make --directory=$DIR $TARGET --question 2> /dev/null # do not print error message if target doesn't exist

  # no such target exists, skipping
  if test $? -eq 2; then return 0; fi

  echo "running $TARGET in $DIR"
  make --directory=$DIR $TARGET &> /dev/null #  do not print output on pre-push hook

  # passed
  if test $? -eq 0; then return 0; fi

  echo "FAILED: $TARGET in $DIR" >&2
  return 1
}

# Get the list of directories where files have been changed in commits
CHANGED_DIRS=$(git diff --stat --cached --name-only $remote | xargs dirname | cut -d "/" -f1 | sort | uniq)

exit_code=0

# for each changed directory run unit tests and integration tests if exist
for DIR in $(echo $CHANGED_DIRS);
do
  make_if_exists $DIR utest
  if test $? -gt 0; then exit_code=1; fi

  make_if_exists $DIR itest
  if test $? -gt 0; then exit_code=1; fi
done

if test $exit_code -gt 0; then echo "Push is not permitted, fix failed tests" >&2; fi

exit $exit_code
