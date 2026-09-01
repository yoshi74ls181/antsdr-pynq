// Selects what supplies the AD9361 transmit samples: the stock ADI DMA/DDS path,
// or the QICK signal generator.
//
// Sits on the supply side of axi_ad9361_dac_fifo, which is a util_rfifo and so
// pull based: the fifo requests a sample by asserting its read enable, and the
// supplier answers with data and valid_in. Note din_enable_* is an *output* of
// that fifo, not an input -- the channel enables originate in axi_ad9361 from
// the cf_axi_dds driver and propagate backwards to upack, so they are not
// something this mux can or should drive.
//
// Two properties here were each established the hard way on hardware.
//
// Combinational, no pipelining. An earlier version registered the sample data
// while leaving valid_in wired straight from upack, putting data one clock behind
// its own valid so the fifo latched the previous sample. That corrupted the
// transmit path enough to fail the AD9361 driver's digital interface calibration,
// which left the chip asleep -- and since the AD9361 sources the LVDS DATA_CLK
// the whole QICK datapath is clocked from, everything downstream died with it and
// only a power cycle recovered the board. With no registers, sel=0 is a wire and
// the stock path is bit-identical to the base design.
//
// qick_tready is asserted whenever the generator is selected, NOT gated on the
// fifo's read request. Gating it couples the generator to the stock transmit
// path: with the ADI DAC datapath idle the fifo never requests a sample, so the
// generator cannot advance. Measured, that is not a dropped sample but a
// deadlock -- it back-pressures sg_translator and stalls the tProc on the very
// instruction that writes the waveform descriptor. Both sides run on the same
// divided clock at one complex sample per clock, so they are inherently rate
// matched and the handshake bought nothing.
//
// sel defaults to 0, so a QICK build that produces nothing still leaves the
// board's existing behaviour intact; the generator has to be asked for.

module qick_tx_mux (
    input  wire        clk,
    input  wire        resetn,

    // Mode select, asynchronous to clk.
    input  wire        sel,

    // Stock path, from util_ad9361_dac_upack.
    input  wire [15:0] dma_data_i,
    input  wire [15:0] dma_data_q,
    input  wire        dma_valid_in,

    // QICK generator: one AXI-Stream carrying {Q,I}, 16 bits each.
    input  wire [31:0] qick_tdata,
    input  wire        qick_tvalid,
    output wire        qick_tready,

    // To axi_ad9361_dac_fifo.
    output wire [15:0] dac_data_i,
    output wire [15:0] dac_data_q,
    output wire        dac_valid_in
);

    // sel is a mode bit, changed between experiments rather than per sample, so
    // a two-flop synchroniser is sufficient. These are the only registers here.
    reg [1:0] sel_sync;
    always @(posedge clk) begin
        if (~resetn) sel_sync <= 2'b00;
        else         sel_sync <= {sel_sync[0], sel};
    end
    wire sel_r = sel_sync[1];

    assign qick_tready  = sel_r;

    assign dac_data_i   = sel_r ? qick_tdata[15:0]  : dma_data_i;
    assign dac_data_q   = sel_r ? qick_tdata[31:16] : dma_data_q;
    // While the generator is selected it is always supplying: it produces a
    // sample every clock, so the fifo can take one whenever it asks.
    assign dac_valid_in = sel_r ? 1'b1 : dma_valid_in;

endmodule
