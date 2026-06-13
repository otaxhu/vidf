#!/bin/sh

: >run-tests.sh.log
exec 2>>run-tests.sh.log

_VIDF_TEST=1 . ./vidf

_vidf_style_setup 0

# shellcheck disable=SC2016
_EVAL_EXPECTED_SUCCESS='[ "$?" -ne 0 ] && echo "Expected success, got failure: on line $LINENO" >&2 && exit 1'
# shellcheck disable=SC2016
_EVAL_EXPECTED_FAILURE='[ "$?" -eq 0 ] && echo "Expected failure, got success: on line $LINENO" >&2 && exit 1'

# 1. Pure functions, basic unit tests

# - _vidf_check_args tests

_TEST_CHECK_ARGS_FORMAT="1,--foo,-f,--bar:,-b:"

# Success
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" some-arg --foo -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_SUCCESS"

# Missing argument
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" --foo -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_FAILURE"

# Excess argument
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" some-arg another-arg --foo -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_FAILURE"

# Unknown option
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" some-arg --foo -f --bar bar-arg -b b-arg --unknown
eval "$_EVAL_EXPECTED_FAILURE"

# Missing option, success is expected because they are always optional
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" some-arg -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_SUCCESS"
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" some-arg --foo --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_SUCCESS"
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" some-arg --foo -f -b b-arg
eval "$_EVAL_EXPECTED_SUCCESS"
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" some-arg --foo -f --bar bar-arg
eval "$_EVAL_EXPECTED_SUCCESS"

# Missing value for option
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" some-arg --foo -f --bar bar-arg -b # Missing here
eval "$_EVAL_EXPECTED_FAILURE"

# EOO excess arguments (End Of Options)
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" some-arg -- --foo -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_FAILURE"

# Success argument with leading -, using EOO
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" -- --foo # Treated as argument due to -- EOO
eval "$_EVAL_EXPECTED_SUCCESS"

# Range positional arguments tests

_TEST_CHECK_ARGS_FORMAT="1-2,--foo,-f,--bar:,-b:"

# Success 1 argument
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" some-arg --foo -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_SUCCESS"

# Success 2 arguments
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" some-arg other-arg --foo -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_SUCCESS"

# Missing argument
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" --foo -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_FAILURE"

# Excess argument
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" some-arg other-arg another-arg --foo -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_FAILURE"

# Range positional arguments tests: optional argument (0 minimum)

_TEST_CHECK_ARGS_FORMAT="0-1,--foo,-f,--bar:,-b:"

# Success 0 args
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" --foo -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_SUCCESS"

# Success 1 arg
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" some-arg --foo -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_SUCCESS"

# Excess arguments
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" some-arg other-arg --foo -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_FAILURE"

# Open-ended range (infinite arguments)

_TEST_CHECK_ARGS_FORMAT="0+,--foo,-f,--bar:,-b:"

# Success 0 args
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" --foo -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_SUCCESS"

# Success multiple args (multi-step test)

# Generate a list of random arguments
set --
while read -r rand_num
do
  set -- "$@" "arg_$rand_num"
done << EOF
$(seq 0 $(($(awk '
  BEGIN {
    srand()
    print int(rand()*32768)
  }') % 16)))
EOF

_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" --foo -f --bar bar-arg -b b-arg "$@"
eval "$_EVAL_EXPECTED_SUCCESS"
set --

# Aliased flags

_TEST_CHECK_ARGS_FORMAT="0,--foo/-f,--bar/-b:"

# Success
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" --foo -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_SUCCESS"

# Missing option, success is expected because they are always optional
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_SUCCESS"
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" --foo --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_SUCCESS"
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" --foo -f -b b-arg
eval "$_EVAL_EXPECTED_SUCCESS"
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" --foo -f --bar bar-arg
eval "$_EVAL_EXPECTED_SUCCESS"

# Missing value for option
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" --foo -f --bar bar-arg -b # Missing here
eval "$_EVAL_EXPECTED_FAILURE"
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" --foo -f -b b-arg --bar # Missing here
eval "$_EVAL_EXPECTED_FAILURE"

# Fuzzy cases
_vidf_err "-------------------"
_vidf_err "Begin Fuzzy Testing for _vidf_check_args"
fail_fuzzy=0
for c in $(seq 1 255)
do
  fuzzy_payload="$(awk </dev/null "BEGIN { printf \"--foo%c-suffix\", $c }")"
  fuzzy_payload="${fuzzy_payload%"-suffix"}"

  if _vidf_check_args "0,--foo" "$fuzzy_payload"
  then
    _vidf_err "Expected failure, got success for $c byte"
    fail_fuzzy=1
  fi
done

_vidf_err "End Fuzzy Testing for _vidf_check_args"
_vidf_err "-------------------"

[ "$fail_fuzzy" = 1 ]
eval "$_EVAL_EXPECTED_FAILURE"

# - _vidf_canonize_args

_TEST_CANON_ARGS_FORMAT="--foo,-f,--bar:,-b:"

# TODO: Check returned args are correct.
exec 3>&1 >/dev/null

# Success (already canon)
_vidf_canonize_args "$_TEST_CANON_ARGS_FORMAT" --foo -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_SUCCESS"

# Success (non-canon)
_vidf_canonize_args "$_TEST_CANON_ARGS_FORMAT" --foo -fb b-arg --bar=bar-arg
eval "$_EVAL_EXPECTED_SUCCESS"

# Success, with arguments.
#
# This function doesn't check if the arguments are expected by caller, it just
# canonize everything.
_vidf_canonize_args "$_TEST_CANON_ARGS_FORMAT" --foo -f --bar bar-arg -b b-arg some-args other-one
eval "$_EVAL_EXPECTED_SUCCESS"

# Missing option, success is expected because they are always optional.
_vidf_canonize_args "$_TEST_CANON_ARGS_FORMAT" -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_SUCCESS"

# Missing value for option
_vidf_canonize_args "$_TEST_CANON_ARGS_FORMAT" --foo -f --bar bar-arg -b # Missing value on -b
eval "$_EVAL_EXPECTED_FAILURE"

# Aliased flags

_TEST_CANON_ARGS_FORMAT="--foo/-f,--bar/-b:"

# Success (already canon)
_vidf_canonize_args "$_TEST_CANON_ARGS_FORMAT" --foo -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_SUCCESS"

# Success (non-canon)
_vidf_canonize_args "$_TEST_CANON_ARGS_FORMAT" --foo -fb b-arg --bar=bar-arg
eval "$_EVAL_EXPECTED_SUCCESS"

# Success, with arguments.
#
# This function doesn't check if the arguments are expected by caller, it just
# canonize everything.
_vidf_canonize_args "$_TEST_CANON_ARGS_FORMAT" --foo -f --bar bar-arg -b b-arg some-args other-one
eval "$_EVAL_EXPECTED_SUCCESS"

# Missing option, success is expected because they are always optional.
_vidf_canonize_args "$_TEST_CANON_ARGS_FORMAT" -f --bar bar-arg -b b-arg
eval "$_EVAL_EXPECTED_SUCCESS"

# Missing value for option
_vidf_canonize_args "$_TEST_CANON_ARGS_FORMAT" --foo -f --bar bar-arg -b # Missing value on -b
eval "$_EVAL_EXPECTED_FAILURE"

exec >&3 3>&-

exit 0
