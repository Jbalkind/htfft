
set hdlin_use_sv_include 1
set hdlin_include_directories [list ../../../../../include ../../../../../protocols/tcp_hw/basejump_files/include ../../../../../protocols/tcp_hw/include/common ../../../../../protocols/tcp_hw/include/tcp ../../../../../util/common_noc_adapters/include ../../../../../util/logging/include ../../../../../network_tiles/eth/include ../../../../../apps/udp_echo_app/include ../../../../../network_tiles/ip/include ../../../../../network_tiles/udp/include .]
set hdlin_include_files [list ../../../../../protocols/tcp_hw/include/common/noc_defs.vh]

source $READ_SOURCES.tcl

analyze -format sverilog [glob -nocomplain ./*.sv]
analyze -format verilog [glob -nocomplain ./*.v]
elaborate $TOP_MODULE

current_design $TOP_MODULE
link

create_clock -name "clk" -period 10 [get_ports clk]
set_clock_uncertainty 0.25 [get_clocks clk]
set_input_delay 2 -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay 2 -clock clk [all_outputs]

set_operating_conditions -max typical

check_design > ${REPORT_DIR}/${TOP_MODULE}_check_design.rpt

compile_ultra -no_seq_output_inversion -no_boundary_optimization

report_qor > ${REPORT_DIR}/${TOP_MODULE}_qor.rpt
report_timing -max_paths 20 -input_pins -nets -transition_time -nosplit -significant_digits 3 -sort_by group > ${REPORT_DIR}/${TOP_MODULE}_timing.rpt
report_area -hierarchy -nosplit > ${REPORT_DIR}/${TOP_MODULE}_area.rpt
report_power -analysis_effort high -hierarchy -levels 2 > ${REPORT_DIR}/${TOP_MODULE}_power.rpt
report_constraint -all_violators > ${REPORT_DIR}/${TOP_MODULE}_violations.rpt
report_reference > ${REPORT_DIR}/${TOP_MODULE}_cells.rpt

write -format verilog -hierarchy -output ${TOP_MODULE}_netlist.v
write -format ddc -hierarchy -output ${TOP_MODULE}_netlist.ddc
write_sdc ${TOP_MODULE}.sdc
