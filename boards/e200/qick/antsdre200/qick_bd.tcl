###############################################################################
## QICK block design additions for the AntSDR E200 (Zynq-7020, xc7z020clg400-2)
##
## Sourced from system_bd.tcl, i.e. from inside adi_project's create step, so
## the project and the ADI base design already exist at this point.
##
## Two clock domains are in play:
##   util_ad9361_divclk/clk_out   QICK datapath (tProc core, generator, readout)
##   sys_cpu_clk       100 MHz    PS AXI, i.e. every s_axi_* port
## QICK's IP take these as separate inputs and cross domains internally, which
## is what lets ad_cpu_interconnect wire the register maps on sys_cpu_clk.
##
## NOT axi_ad9361/l_clk. l_clk is rx_clk, the AD9361 LVDS DATA_CLK, which
## system.xdc constrains at 4 ns / 250 MHz -- the part's maximum for that
## interface, not the sample rate. Clocking the QICK datapath there fails
## timing badly (WNS -2.031 ns, 4934 failing endpoints, the worst path inside
## the tProc ALU). util_ad9361_divclk is a runtime-selectable divide of l_clk
## and is where the base design puts the ADC/DAC sample datapath and the DMAs.
## Vivado analyses both selectable ratios:
##   clk_div_sel_1_s   8 ns / 125 MHz   (divide by 2)
##   clk_div_sel_0_s  16 ns /  62.5 MHz (divide by 4)
## so the datapath must close at 125 MHz worst case, and with l_clk at the
## AD9361's 245.76 MHz that is 122.88 MHz in hardware.
###############################################################################

# QICK's IP live outside the ADI library tree. adi_project sets ip_repo_paths
# from a proc-local $lib_dirs before sourcing system_bd.tcl, so the list cannot
# be extended from the outside -- append to the fileset property here instead.
if {[info exists ::env(QICK_IP_DIR)]} {
  set qick_ip_dir $::env(QICK_IP_DIR)
} else {
  set qick_ip_dir [file normalize $ad_hdl_dir/../../pluto-qick/third_party/qick/firmware/ip]
}
if {![file isdirectory $qick_ip_dir]} {
  return -code error "QICK_IP_DIR does not exist: $qick_ip_dir"
}
set_property ip_repo_paths \
  [concat [get_property ip_repo_paths [current_fileset]] $qick_ip_dir] \
  [current_fileset]
update_ip_catalog -rebuild

# The base design already provides a synchronous active-low reset for the
# divided clock, so no extra proc_sys_reset is needed.
set qick_clk  util_ad9361_divclk/clk_out
set qick_rstn util_ad9361_divclk_reset/peripheral_aresetn

###############################################################################
## tProcessor v2
##
## ARITH=0 leaves dsp_macro_0 out: it is a 27x18 macro (DSP48E2) and a 7-series
## DSP48E1 is 25x18, so it would only map by spilling across slices.
## s_axi rides on ps_clk_i; there is no separate s_axi_aclk on this IP.
###############################################################################
ad_ip_instance qick_processor tproc
ad_ip_parameter tproc CONFIG.ARITH         0
ad_ip_parameter tproc CONFIG.DIVIDER       0
ad_ip_parameter tproc CONFIG.IN_PORT_QTY   1
ad_ip_parameter tproc CONFIG.OUT_WPORT_QTY 1

ad_connect $qick_clk  tproc/t_clk_i
ad_connect $qick_clk  tproc/c_clk_i
ad_connect sys_cpu_clk       tproc/ps_clk_i
ad_connect $qick_rstn        tproc/t_resetn
ad_connect $qick_rstn        tproc/c_resetn
ad_connect sys_cpu_resetn    tproc/ps_resetn

###############################################################################
## Signal generator
##
## N_DDS=1: the E200 datapath is one complex sample per sample clock, not the 16
## lanes an RFSoC tile delivers. ENVELOPE_TYPE=COMPLEX is the default and is kept.
## s0_axis is the envelope memory write port and has its own clock; s1_axis is
## the waveform descriptor port and runs on aclk.
###############################################################################
ad_ip_instance axis_signal_gen_v6 sg0
ad_ip_parameter sg0 CONFIG.N_DDS         1
ad_ip_parameter sg0 CONFIG.ENVELOPE_TYPE COMPLEX
ad_ip_parameter sg0 CONFIG.GEN_DDS       TRUE

ad_connect $qick_clk  sg0/aclk
ad_connect $qick_rstn        sg0/aresetn
ad_connect $qick_clk  sg0/s0_axis_aclk
ad_connect $qick_rstn        sg0/s0_axis_aresetn
ad_connect sys_cpu_clk       sg0/s_axi_aclk
ad_connect sys_cpu_resetn    sg0/s_axi_aresetn

###############################################################################
## Readout
## s_axis has no clock of its own and runs on aclk.
###############################################################################
ad_ip_instance axis_readout_v2 ro0
ad_connect $qick_clk  ro0/aclk
ad_connect $qick_rstn        ro0/aresetn
ad_connect sys_cpu_clk       ro0/s_axi_aclk
ad_connect sys_cpu_resetn    ro0/s_axi_aresetn

###############################################################################
## Averaging buffer
## No plain aclk on this IP: the stream sides are clocked separately.
###############################################################################
ad_ip_instance axis_avg_buffer avg0
ad_connect $qick_clk  avg0/s_axis_aclk
ad_connect $qick_rstn        avg0/s_axis_aresetn
ad_connect $qick_clk  avg0/m_axis_aclk
ad_connect $qick_rstn        avg0/m_axis_aresetn
ad_connect sys_cpu_clk       avg0/s_axi_aclk
ad_connect sys_cpu_resetn    avg0/s_axi_aresetn

###############################################################################
## Streams and triggers internal to QICK
###############################################################################
# tProc's m0_axis is a 168-bit waveform descriptor and the generator's s0_axis is
# 32 bits: they are never connected directly. QICK routes every generator port
# through sg_translator, which reformats the v2 descriptor for the target
# generator. Default OUT_TYPE selects the m_gen_v6_axis output, which is the one
# axis_signal_gen_v6 wants (OUT_TYPE 2 would select m_mux4_axis instead).
#
# The descriptor lands on s1_axis (160 bits), NOT s0_axis. s0_axis is the 32-bit
# envelope memory write port, which is why it has a clock of its own -- it is fed
# by DMA. Cross-check: QICK wires sg_translator/m_gen_v6_axis to s1_axis too.
ad_ip_instance sg_translator sgt0
ad_connect $qick_clk  sgt0/aclk
ad_connect $qick_rstn        sgt0/aresetn
ad_connect tproc/m0_axis     sgt0/s_tproc_axis
ad_connect sgt0/m_gen_v6_axis sg0/s1_axis

# Single-shot readout results feed back into the tProc for branching. Both sides
# are 64 bits and both are on the sample clock, so no axis_clock_converter is
# needed here (QICK's RFSoC designs need one because those run on different tiles).
ad_connect avg0/m2_axis   tproc/s0_axis

# m1_axis is the decimated output, m0_axis the full-rate raw one -- QICK feeds
# avg_buffer from m1_axis and sends m0_axis to a multi-rate buffer we do not
# instantiate. Both are 32 bits, matching avg0/s_axis.
ad_connect ro0/m1_axis    avg0/s_axis
# tProc arms the accumulator.
ad_connect tproc/trig_0_o avg0/trigger

###############################################################################
## AXI-lite register maps
##
## NOT QICK's usual 0x8400_0000 base: that lands in the Zynq-7000 M_AXI_GP1
## aperture (0x8000_0000-0xBFFF_FFFF), while ADI's axi_cpu_interconnect hangs
## off GP0 (0x4000_0000-0x7FFF_FFFF) -- see the base design's 0x79020000 /
## 0x7C400000 entries. 0x4800_xxxx is free in GP0 and passes through unmapped
## (ad_cpu_interconnect only rebases 0x4xxx_xxxx for sys_zynq 2 and 3).
###############################################################################
ad_cpu_interconnect 0x48000000 tproc
ad_cpu_interconnect 0x48010000 sg0
ad_cpu_interconnect 0x48020000 ro0
ad_cpu_interconnect 0x48030000 avg0

###############################################################################
## RX: AD9361 -> readout -> averaging buffer
##
## Tapped after util_ad9361_adc_fifo, which is the crossing from l_clk into the
## divided clock -- taking axi_ad9361/adc_data_* directly would land the readout
## back in the 250 MHz l_clk domain. dout_data_0/1 are I0/Q0, 16 bits each, with
## dout_valid_0.
##
## The readout's s_axis is 32 bits of {Q,I} (patch 0006 gives it a complex input
## rather than the upstream real one), so concatenate the pair: xlconcat puts In0
## in the low bits, which is I.
##
## These pins already drive util_ad9361_adc_pack. They are outputs, so the extra
## fanout to the readout is fine and the stock capture path keeps working.
###############################################################################
ad_ip_instance xlconcat qick_adc_cat
ad_ip_parameter qick_adc_cat CONFIG.NUM_PORTS  2
ad_ip_parameter qick_adc_cat CONFIG.IN0_WIDTH 16
ad_ip_parameter qick_adc_cat CONFIG.IN1_WIDTH 16
ad_connect util_ad9361_adc_fifo/dout_data_0  qick_adc_cat/In0
ad_connect util_ad9361_adc_fifo/dout_data_1  qick_adc_cat/In1
ad_connect qick_adc_cat/dout        ro0/s_axis_tdata
ad_connect util_ad9361_adc_fifo/dout_valid_0 ro0/s_axis_tvalid

###############################################################################
## TX: mux between the stock DAC path and the QICK generator
##
## Defaults to the stock path, so a QICK build that produces nothing still
## leaves the board's loopback behaviour intact. Selected by a dedicated
## axi_gpio rather than by borrowing a bit of axi_gpreg's gp_out_*, which are
## already routed out to system_top.v.
###############################################################################
# system_bd.tcl is sourced from inside adi_project, before adi_project_files
# adds anything, so the module reference has to be put in the project here.
add_files -norecurse -fileset sources_1 [list [file normalize ./qick_tx_mux.v]]
update_compile_order -fileset sources_1

ad_ip_instance axi_gpio qick_gpio
ad_ip_parameter qick_gpio CONFIG.C_GPIO_WIDTH   1
ad_ip_parameter qick_gpio CONFIG.C_ALL_OUTPUTS  1
ad_connect sys_cpu_clk     qick_gpio/s_axi_aclk
ad_connect sys_cpu_resetn  qick_gpio/s_axi_aresetn

create_bd_cell -type module -reference qick_tx_mux qick_tx_mux_0
ad_connect $qick_clk     qick_tx_mux_0/clk
ad_connect $qick_rstn           qick_tx_mux_0/resetn
ad_connect qick_gpio/gpio_io_o  qick_tx_mux_0/sel

# Sits between util_ad9361_dac_upack and axi_ad9361_dac_fifo, i.e. on the
# divided clock, so the fifo still performs the crossing up to l_clk. Putting
# the mux at the fifo's output instead would require the generator to run at
# 250 MHz. The base design wires upack straight to the fifo, so those nets have
# to go before the mux can sit in between.
delete_bd_objs [get_bd_nets -of_objects [get_bd_pins axi_ad9361_dac_fifo/din_data_0]]
delete_bd_objs [get_bd_nets -of_objects [get_bd_pins axi_ad9361_dac_fifo/din_data_1]]

ad_connect util_ad9361_dac_upack/fifo_rd_data_0  qick_tx_mux_0/dma_data_i
ad_connect util_ad9361_dac_upack/fifo_rd_data_1  qick_tx_mux_0/dma_data_q
ad_connect sg0/m_axis_tdata                      qick_tx_mux_0/qick_tdata
ad_connect sg0/m_axis_tvalid                     qick_tx_mux_0/qick_tvalid
ad_connect sg0/m_axis_tready                     qick_tx_mux_0/qick_tready
ad_connect qick_tx_mux_0/dac_data_i              axi_ad9361_dac_fifo/din_data_0
ad_connect qick_tx_mux_0/dac_data_q              axi_ad9361_dac_fifo/din_data_1

ad_cpu_interconnect 0x48040000 qick_gpio

# Iteration aid: validate the block design and stop, skipping the ~1 h
# synthesis + implementation run. Unset in normal builds.
if {[info exists ::env(QICK_BD_ONLY)]} {
  validate_bd_design
  save_bd_design
  puts "QICK_BD_OK"
  exit 0
}
