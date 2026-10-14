#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/door-lock-tests.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
run_test() {
    top=$1
    shift
    iverilog -g2012 -s "$top" "$@" -o "$build_dir/$top" ./*.v "testbench/$top.v"
    vvp "$build_dir/$top" > "$build_dir/$top.log"
    cat "$build_dir/$top.log"
    if grep -Eq 'FAIL|FATAL|TEST FAILED' "$build_dir/$top.log"; then exit 1; fi
}
run_test tb_pin_entry
run_test tb_pin_compare
run_test tb_keypad_input
run_test tb_keypad_input -Ptb_keypad_input.TEST_CLK_HZ=1000
run_test tb_keypad_input -Ptb_keypad_input.TEST_CLK_HZ=2000
run_test tb_door_lock_top
run_test tb_lcd_boot
run_test tb_lcd_boot -Ptb_lcd_boot.RESET_ACTIVE_LOW=0
run_test tb_lcd_privacy
run_test tb_lcd_timing
# Real board timing; keep this slower check opt-in.
if [ "${1:-}" = "--50mhz" ]; then
    run_test tb_lcd_boot -Ptb_lcd_boot.CLK_HZ=50000000 -Ptb_lcd_boot.QUICK=1
fi
