#!/bin/sh

# this script prints all comments marked with "TODO:" or "FIXME:"

ABSOLUTE_PATH="$(readlink -f $0)";
TOOLS_DIR="$(dirname $ABSOLUTE_PATH)";
PROJECT_DIR="$(dirname $TOOLS_DIR)";

find "$PROJECT_DIR" -type f -name '*.sh' -o -name '*.fcgi' -o -name '*.pm' -o -name '*.pl' | grep -v TODO.sh | xargs egrep --line-number --with-filename --only-matching '#.*(TODO:|FIXME:).*'
