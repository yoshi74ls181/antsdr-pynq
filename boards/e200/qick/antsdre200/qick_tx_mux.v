// Selects what drives the AD9361 transmit port: the stock ADI DMA/DDS path, or
// the QICK signal generator.
//
// sel defaults to 0 (the DMA path) so that a QICK build which fails to produce
// samples still leaves the board's existing loopback behaviour intact -- the
// generator has to be asked for explicitly.
//
// sel arrives from an axi_gpio in the sys_cpu_clk domain and is resynchronised
// here into l_clk. It is a mode bit, changed between experiments rather than
// per-sample, so a two-flop synchroniser is sufficient; there is no coherency
// requirement against the sample stream.

module qick_tx_mux (
    input  wire        clk,
    input  wire        resetn,

    // Mode select, asynchronous to clk.
    input  wire        sel,

    // Stock path, from axi_ad9361_dac_fifo.
    input  wire [15:0] dma_data_i,
    input  wire [15:0] dma_data_q,

    // QICK generator: one AXI-Stream carrying {Q,I}, 16 bits each.
    input  wire [31:0] qick_tdata,
    input  wire        qick_tvalid,
    output wire        qick_tready,

    // To axi_ad9361.
    output wire [15:0] dac_data_i,
    output wire [15:0] dac_data_q
);

    reg [1:0] sel_sync;
    always @(posedge clk) begin
        if (~resetn) sel_sync <= 2'b00;
        else         sel_sync <= {sel_sync[0], sel};
    end
    wire sel_r = sel_sync[1];

    // The AD9361 consumes one sample per l_clk unconditionally, so the
    // generator is never back-pressured. When sel_r is low its samples are
    // simply discarded.
    assign qick_tready = 1'b1;

    reg [15:0] data_i_r, data_q_r;
    always @(posedge clk) begin
        if (~resetn) begin
            data_i_r <= 16'h0000;
            data_q_r <= 16'h0000;
        end
        else if (sel_r) begin
            // Hold the last sample when the generator is not presenting one,
            // rather than emitting zeros, which would splatter the spectrum.
            if (qick_tvalid) begin
                data_i_r <= qick_tdata[15:0];
                data_q_r <= qick_tdata[31:16];
            end
        end
        else begin
            data_i_r <= dma_data_i;
            data_q_r <= dma_data_q;
        end
    end

    assign dac_data_i = data_i_r;
    assign dac_data_q = data_q_r;

endmodule
