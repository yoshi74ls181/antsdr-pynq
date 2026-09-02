###############################################################################
## Clock-domain constraints for the QICK blocks.
##
## QICK ships an equivalent file per project (firmware/projects/*/timing.xdc);
## this is the E200 version. Without it the build fails with roughly -2.9 ns on
## paths like avg0/axi_slv_i/slv_reg2 -> avg0/avg_buffer_i/.../len_r, an AXI-lite
## configuration register in the PS clock domain feeding datapath logic in the
## sample clock domain.
##
## Those crossings are not meant to be timed. clk_fpga_0 comes from the PS PLL
## and the sample clock is divided down from the AD9361's DATA_CLK, so the two
## are physically asynchronous -- there is no fixed phase relationship for the
## timer to analyse, and an alignment it happens to pick is not one the hardware
## honours. The QICK registers involved are quasi-static: written while the block
## is idle, then held constant for the duration of a measurement. The bulk data
## crossings go through proper asynchronous FIFOs (util_wfifo / util_rfifo on the
## ADI side, synchronizer_n and the AXI-Stream FIFOs inside the QICK IP).
##
## Clocks are found by object rather than by name: util_clkdiv's generated clock
## names (clk_div_sel_0_s, clk_div_sel_1_s) are tool-derived and would be brittle
## to hardcode. Both selectable divide ratios are returned, which is what we
## want -- the datapath has to be correct for either.
##
## Note: XDC files do not accept `if` or `puts`, so this cannot sanity-check the
## lookups inline; a failed lookup surfaces as an empty -group and a Vivado
## warning on the set_clock_groups line.
###############################################################################

set clk_axi [get_clocks -of_objects [get_nets -of_objects \
    [get_pins -hier -filter {name =~ */sys_ps7/FCLK_CLK0}]]]

set clk_dp  [get_clocks -of_objects [get_nets -of_objects \
    [get_pins -hier -filter {name =~ */util_ad9361_divclk/clk_out}]]]


set_clock_groups -name qick_axi_to_datapath -asynchronous \
    -group $clk_axi \
    -group $clk_dp

# The tProc's trigger outputs are single-cycle strobes into the buffer blocks and
# are resynchronised where they land; QICK false-paths them for the same reason.
set_false_path -quiet -through [get_pins -quiet -hier -filter {name =~ */qick_processor_0/trig_*_o}]
