#!/bin/sh

set -euo pipefail

SCRIPT_PATH="$(realpath "$0")"
SCRIPT_ROOT="$(dirname "$SCRIPT_PATH")"

crystal=$SCRIPT_ROOT/../../../bin/crystal

function test() {
  input_cr="$SCRIPT_ROOT/$1"
  output_ll="$SCRIPT_ROOT/$1.ll"

  DUMP=1 $crystal build -Dhle_unions --prelude=empty --no-debug --no-color --emit=llvm-ir $input_cr 2>$output_ll
  cat $output_ll | FileCheck $input_cr
  rm $output_ll

  # uncomment to run program
  # $crystal run -Dhle_unions $input_cr
}

test "01_local_variable.cr"
test "02_closured_variable.cr"
test "03_variable_assignment.cr"


