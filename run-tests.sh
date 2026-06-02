#!/bin/sh

_VIDF_TEST=1 source ./vidf

# 1. Pure functions, basic unit tests

# - _vidf_check_args tests

_TEST_CHECK_ARGS_FORMAT="1,--foo,-f,--bar:,-b:"

_EVAL_EXPECTED_SUCCESS='[ "$?" -ne 0 ] && echo "Expected success, got failure: on line $LINENO" >&2 && exit 1'
_EVAL_EXPECTED_FAILURE='[ "$?" -eq 0 ] && echo "Expected failure, got success: on line $LINENO" >&2 && exit 1'

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

# Missing value for option
_vidf_check_args "$_TEST_CHECK_ARGS_FORMAT" some-arg --foo -f --bar bar-arg -b # Missing here
eval "$_EVAL_EXPECTED_FAILURE"

exit 0
