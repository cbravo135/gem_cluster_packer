`timescale 1ns / 100 ps

//----------------------------------------------------------------------------------------------------------------------
//
//----------------------------------------------------------------------------------------------------------------------

//synthesis attribute ALLCLOCKNETS of cluster_packer is "160MHz"

module cluster_packer (
    input  clock4x,
    input  global_reset,
    input  reverse_priority_order,
    input  truncate_clusters,

    input  [MXSBITS-1:0] vfat0,
    input  [MXSBITS-1:0] vfat1,
    input  [MXSBITS-1:0] vfat2,
    input  [MXSBITS-1:0] vfat3,
    input  [MXSBITS-1:0] vfat4,
    input  [MXSBITS-1:0] vfat5,
    input  [MXSBITS-1:0] vfat6,
    input  [MXSBITS-1:0] vfat7,
    input  [MXSBITS-1:0] vfat8,
    input  [MXSBITS-1:0] vfat9,
    input  [MXSBITS-1:0] vfat10,
    input  [MXSBITS-1:0] vfat11,
    input  [MXSBITS-1:0] vfat12,
    input  [MXSBITS-1:0] vfat13,
    input  [MXSBITS-1:0] vfat14,
    input  [MXSBITS-1:0] vfat15,
    input  [MXSBITS-1:0] vfat16,
    input  [MXSBITS-1:0] vfat17,
    input  [MXSBITS-1:0] vfat18,
    input  [MXSBITS-1:0] vfat19,
    input  [MXSBITS-1:0] vfat20,
    input  [MXSBITS-1:0] vfat21,
    input  [MXSBITS-1:0] vfat22,
    input  [MXSBITS-1:0] vfat23,

    output [MXCLSTBITS-1:0] cluster0,
    output [MXCLSTBITS-1:0] cluster1,
    output [MXCLSTBITS-1:0] cluster2,
    output [MXCLSTBITS-1:0] cluster3,
    output [MXCLSTBITS-1:0] cluster4,
    output [MXCLSTBITS-1:0] cluster5,
    output [MXCLSTBITS-1:0] cluster6,
    output [MXCLSTBITS-1:0] cluster7,
);

parameter MXSBITS    = 64;         // S-bits per vfat
parameter MXKEYS     = 3*MXSBITS;  // S-bits per partition
parameter MXPADS     = 24*MXSBITS; // S-bits per chamber
parameter MXROWS     = 8;          // Eta partitions per chamber
parameter MXCNTBITS  = 3;          // Number of count   bits per cluster
parameter MXADRBITS  = 11;         // Number of address bits per cluster
parameter MXCLSTBITS = 14;         // Number of total   bits per cluster
parameter MXOUTBITS  = 56;         // Number of total   bits per packet
parameter MXCLUSTERS = 8;          // Number of clusters per bx

//----------------------------------------------------------------------------------------------------------------------
// State machine power-up reset + global reset
//----------------------------------------------------------------------------------------------------------------------

  // Startup -- keeps outputs off during powerup
  //---------------------------------------------

  wire [3:0] powerup_dly = 4'd8;

  reg powerup_ff  = 0;
  srl16e_bbl #(1) u_startup (.clock(clock4x), .ce(!powerup), .adr(powerup_dly),  .d(1'b1), .q(powerup));
  always @(posedge clock4x) begin
    powerup_ff <= powerup;
  end

  // Reset -- keeps outputs off during reset time
  //--------------------------------------------------------------
  reg reset_done_ff = 1;
  wire [3:0] reset_dly=4'd4;

  srl16e_bbl #(1) u_reset_dly (.clock(clock4x), .ce(1'b1), .adr(reset_dly),  .d(global_reset), .q(reset_delayed));

  always @(posedge clock4x) begin
    if      (global_reset && reset_done_ff)                    reset_done_ff <= 1'b0;
    else if (!global_reset && reset_delayed && !reset_done_ff) reset_done_ff <= 1'b1;
    else                                                       reset_done_ff <= reset_done_ff;
  end

  wire ready = powerup_ff && reset_done_ff;
  wire reset = !ready;

//----------------------------------------------------------------------------------------------------------------------
// clock 1: Count cluster multiplicity for each pad
//----------------------------------------------------------------------------------------------------------------------

  // remap vfats into partitions
  //--------------------------------------------------------------------------------

  wire  [MXKEYS-1:0] partition0 = {vfat16, vfat8,  vfat0};
  wire  [MXKEYS-1:0] partition1 = {vfat17, vfat9,  vfat1};
  wire  [MXKEYS-1:0] partition2 = {vfat18, vfat10, vfat2};
  wire  [MXKEYS-1:0] partition3 = {vfat19, vfat11, vfat3};
  wire  [MXKEYS-1:0] partition4 = {vfat20, vfat12, vfat4};
  wire  [MXKEYS-1:0] partition5 = {vfat21, vfat13, vfat5};
  wire  [MXKEYS-1:0] partition6 = {vfat22, vfat14, vfat6};
  wire  [MXKEYS-1:0] partition7 = {vfat23, vfat15, vfat7};

  // pad the partition to handle the edge cases
  //--------------------------------------------------------------------------------
  wire [(MXKEYS-1)+7:0] partition_padded [MXROWS-1:0];

  assign partition_padded[0] = {{7{1'b0}}, partition0};
  assign partition_padded[1] = {{7{1'b0}}, partition1};
  assign partition_padded[2] = {{7{1'b0}}, partition2};
  assign partition_padded[3] = {{7{1'b0}}, partition3};
  assign partition_padded[4] = {{7{1'b0}}, partition4};
  assign partition_padded[5] = {{7{1'b0}}, partition5};
  assign partition_padded[6] = {{7{1'b0}}, partition6};
  assign partition_padded[7] = {{7{1'b0}}, partition7};

  // count cluster size and assign valid pattern flags
  //--------------------------------------------------------------------------------
  wire [MXCNTBITS-1:0] cnt [MXROWS-1:0][MXKEYS-1:0];
  wire [0:0]           vpf [MXROWS-1:0][MXKEYS-1:0];

  genvar ikey;
  genvar irow;
  generate
    for (irow=0; irow<MXROWS; irow=irow+1) begin: cluster_count_rowloop
    for (ikey=0; ikey<MXKEYS; ikey=ikey+1) begin: cluster_count_keyloop

      // count the number of hit pads immediately adjacent to the key pad
      assign cnt[irow][ikey] = count_seq (partition_padded[irow][ikey+8:ikey+1]);

      // first pad is always a cluster if it has an S-bit
      // other pads are cluster if they:
      //    (1) are preceded by a Zero (i.e. they start a cluster)
      // or (2) are preceded by a Size=8 cluster (and cluster truncation is turned off)
      //        if we have size > 16 cluster, the end will get cut off
      if      (ikey==0) assign vpf [irow][ikey] = partition_padded[irow][ikey];
      else if (ikey <9) assign vpf [irow][ikey] = partition_padded[irow][ikey:ikey-1]==2'b10;
      else              assign vpf [irow][ikey] = partition_padded[irow][ikey:ikey-1]==2'b10 || (!truncate_clusters && partition_padded[irow][ikey-1:ikey-9]==9'b111111110) ;

    end // row loop
    end // key_loop
  endgenerate

  // rollup copies of vpf/cnt into ff'd register
  //--------------------------------------------------------------------------------
  reg  [0:0]           vpfs [MXPADS-1:0];
  reg  [MXCNTBITS-1:0] cnts [MXPADS-1:0];
  generate
    for (irow=0; irow<MXROWS; irow=irow+1) begin: rollup_rowloop
    for (ikey=0; ikey<MXKEYS; ikey=ikey+1) begin: rollup_keyloop
      always @(posedge clock4x) begin
      vpfs [(MXKEYS*irow)+ikey] <= (reset) ? 1'b0 : vpf[irow][ikey];
      cnts [(MXKEYS*irow)+ikey] <= (reset) ? 3'b0 : cnt[irow][ikey];
      end
    end
    end
  endgenerate


  // delay counts to be readout at output
  //--------------------------------------------------------------------------------
  parameter [3:0] output_dly = 4'd12;

  wire [MXCNTBITS-1:0] cnts_delayed [MXPADS-1:0];
  genvar ipad;
  generate
    for (ipad=0; ipad<MXPADS; ipad=ipad+1) begin: pad_loop
      srl16e_bbl #(3) srl_cnts  (.clock(clock4x), .ce(1'b1), .adr(output_dly),  .d(cnts[ipad]), .q(cnts_delayed[ipad]));
    end
  endgenerate

//----------------------------------------------------------------------------------------------------------------------
// clock 2: reverse order
//----------------------------------------------------------------------------------------------------------------------

  // reverse order of cluster flags
  //--------------------------------
  wire [MXPADS-1:0] vpfs_rev;
  generate
    for (ipad=0; ipad<MXPADS; ipad=ipad+1) begin: rev_loop
      assign vpfs_rev [ipad] = vpfs[MXPADS-1-ipad];
    end
  endgenerate

  wire [MXPADS-1:0] vpfs_enc = (reverse_priority_order) ? vpfs_rev : vpfs;

//----------------------------------------------------------------------------------------------------------------------
// clock 3-12: priority encoding
//----------------------------------------------------------------------------------------------------------------------
  // clock 3:                latch local copies at first8 priority encoders & cluster truncators
  // clock 4:  produce (n-1) truncated clusters
  // clock 5:  produce (n-2) truncated clusters    ;  latch 1st cluster result
  // clock 6:  produce (n-3) truncated clusters    ;  latch 2nd cluster result
  // clock 7:  produce (n-4) truncated clusters    ;  latch 3rd cluster result
  // clock 8:  produce (n-5) truncated clusters    ;  latch 4th cluster result
  // clock 9:  produce (n-6) truncated clusters    ;  latch 5th cluster result
  // clock 10: produce (n-7) truncated clusters    ;  latch 6th cluster result
  // clock 11: produce (n-8) truncated clusters    ;  latch 7th cluster result
  // clock 12:                                     ;  latch clusters (1-8)
  //--------------------------------------------------------------------------------------------------------------------

  wire [MXADRBITS-1:0] adr_encoder [MXCLUSTERS-1:0];

  first8of1536_mux u_first8_mux (
    .clock4x (clock4x),

    .reset (reset),

    .vpfs (vpfs_enc),

    .adr0 (adr_encoder[0]),
    .adr1 (adr_encoder[1]),
    .adr2 (adr_encoder[2]),
    .adr3 (adr_encoder[3]),
    .adr4 (adr_encoder[4]),
    .adr5 (adr_encoder[5]),
    .adr6 (adr_encoder[6]),
    .adr7 (adr_encoder[7])
  );

//----------------------------------------------------------------------------------------------------------------------
// clock 13: unreverse address outputs, extract counts from SRL, build data packet
//----------------------------------------------------------------------------------------------------------------------

  wire [MXCNTBITS-1:0]  cnt_out [MXCLUSTERS-1:0];
  wire [MXADRBITS-1:0]  adr_out [MXCLUSTERS-1:0];

  reg  [MXCLSTBITS-1:0] cluster [MXCLUSTERS-1:0];

  genvar icluster;
  generate
    for (icluster=0; icluster<MXROWS; icluster=icluster+1) begin: adrloop

      //--------------------------
      // unreverse address outputs
      //--------------------------
      assign adr_out[icluster] = (reverse_priority_order) ? (adr_encoder[icluster]) : ((MXPADS-1)-adr_encoder[icluster]);

      //---------------------------------------------------------
      // extract counts
      //---------------------------------------------------------
      assign cnt_out[icluster] = cnts_delayed[adr_out[icluster]];

      //--------------------------------------------
      //  14 bit hit format encoding
      //   hit[10:0]  = pad
      //   hit[13:11] = n adjacent pads hit  up to 7
      //--------------------------------------------
      always @(posedge clock4x)
        cluster [icluster] <= (ready) ? {cnt_out[icluster], adr_out[icluster]} : {3'd0, 11'h7FE};
    end
  endgenerate

  assign cluster0 = cluster[0];
  assign cluster1 = cluster[1];
  assign cluster2 = cluster[2];
  assign cluster3 = cluster[3];
  assign cluster4 = cluster[4];
  assign cluster5 = cluster[5];
  assign cluster6 = cluster[6];
  assign cluster7 = cluster[7];

//----------------------------------------------------------------------------------------------------------------------
// count_seq: procedural function to count the number of consecutive 1 bits in an 8-bit number
//----------------------------------------------------------------------------------------------------------------------

  function [2:0] count_seq;
  input [6:0] s;
  reg [2:0] count;
  begin
    casex (s[6:0])
      7'b1111111: count=3'd7;
      7'b0111111: count=3'd6;
      7'bx011111: count=3'd5;
      7'bxx01111: count=3'd4;
      7'bxxx0111: count=3'd3;
      7'bxxxx011: count=3'd2;
      7'bxxxxx01: count=3'd1;
      7'bxxxxxx0: count=3'd0;
    endcase
    count_seq=count;
  end
  endfunction

//----------------------------------------------------------------------------------------------------------------------
endmodule
//----------------------------------------------------------------------------------------------------------------------