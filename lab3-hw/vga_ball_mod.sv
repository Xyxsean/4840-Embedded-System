/*
 * Avalon memory-mapped peripheral that generates VGA
 *
 * Stephen A. Edwards
 * Columbia University
 */

module vga_ball(input logic        clk,
	        input logic 	   reset,
		input logic [7:0]  writedata,
		input logic 	   write,
		input 		   chipselect,
		input logic [2:0]  address,

		output logic [7:0] VGA_R, VGA_G, VGA_B,
		output logic 	   VGA_CLK, VGA_HS, VGA_VS,
		                   VGA_BLANK_n,
		output logic 	   VGA_SYNC_n);

   logic [10:0]   hcount;
   logic [9:0]    vcount;
   logic [7:0] 	  background_r, background_g, background_b;
   logic [9:0]    x_set;
   logic [9:0]    y_set;

   logic [9:0]    VGA_x;
   logic [9:0]    VGA_y;

	
   vga_counters counters(.clk50(clk), .*);

   always_ff @(posedge clk)
     if (reset) begin
	background_r <= 8'd120;
	background_g <= 8'd10;
	background_b <= 8'd40;
     end else if (chipselect && write)
       case (address)
	 3'h0 : begin x_set[1:0] <= writedata[1:0];y_set[1:0] <= writedata[3:2]; end
	 3'h1 : x_set[9:2] <= writedata;
	 3'h2 : y_set[9:2] <= writedata;
       endcase

/*
   always_comb begin
      {VGA_R, VGA_G, VGA_B} = {8'h0, 8'h0, 8'h0};
      if (VGA_BLANK_n )
	      if (hcount[10:3] == x_set && vcount[9:2] == y_set && !(hcount[2:1]==0 && vcount[1:0]==0) && !(hcount[2:1]==0 && vcount[1:0]==3) && !(hcount[2:1] == 3 && vcount[1:0]==0) && !(hcount[2:1]==3 && vcount[1:0]==3))
	      {VGA_R, VGA_G, VGA_B} = {8'hff, 8'hff, 8'hff};
	      else
	      {VGA_R, VGA_G, VGA_B} = {background_r, background_g, background_b};
   end
*/

   parameter R = 20;

   always_comb begin
	{VGA_R, VGA_G, VGA_B} = {8'h0, 8'h0, 8'h0};
     	if (VGA_BLANK_n ) begin
	int dist_sq ;
	dist_sq = ((hcount[10:1] - VGA_x)*(hcount[10:1] - VGA_x) + (vcount - VGA_y)*(vcount - VGA_y));
	    if (dist_sq <= R*R)
	  	{VGA_R, VGA_G, VGA_B} = {8'hff, 8'hff, 8'hff};
	    else
	  	{VGA_R, VGA_G, VGA_B} = {background_r, background_g, background_b};
	end
   end

   always_ff @(posedge clk) begin
      if (reset)
	{VGA_x, VGA_y} <= {8'h0, 8'h0};
      else if (vcount == 524)
     	{VGA_x, VGA_y} <= {x_set,y_set};
      else
        {VGA_x, VGA_y} <= {VGA_x, VGA_y};
   end

	       
endmodule

module vga_counters(
 input logic 	     clk50, reset,
 output logic [10:0] hcount,  // hcount[10:1] is pixel column
 output logic [9:0]  vcount,  // vcount[9:0] is pixel row
 output logic 	     VGA_CLK, VGA_HS, VGA_VS, VGA_BLANK_n, VGA_SYNC_n);

/*
 * 640 X 480 VGA timing for a 50 MHz clock: one pixel every other cycle
 * 
 * HCOUNT 1599 0             1279       1599 0
 *             _______________              ________
 * ___________|    Video      |____________|  Video
 * 
 * 
 * |SYNC| BP |<-- HACTIVE -->|FP|SYNC| BP |<-- HACTIVE
 *       _______________________      _____________
 * |____|       VGA_HS          |____|
 */
   // Parameters for hcount
   parameter HACTIVE      = 11'd 1280, //1280
             HFRONT_PORCH = 11'd 32,
             HSYNC        = 11'd 192,
             HBACK_PORCH  = 11'd 96,   
             HTOTAL       = HACTIVE + HFRONT_PORCH + HSYNC +
                            HBACK_PORCH; // 1600
   
   // Parameters for vcount
   parameter VACTIVE      = 10'd 480,
             VFRONT_PORCH = 10'd 10,
             VSYNC        = 10'd 2,
             VBACK_PORCH  = 10'd 33,
             VTOTAL       = VACTIVE + VFRONT_PORCH + VSYNC +
                            VBACK_PORCH; // 525

   logic endOfLine;
   
   always_ff @(posedge clk50 or posedge reset)
     if (reset)          hcount <= 0;
     else if (endOfLine) hcount <= 0;
     else  	         hcount <= hcount + 11'd 1;

   assign endOfLine = hcount == HTOTAL - 1;
       
   logic endOfField;
   
   always_ff @(posedge clk50 or posedge reset)
     if (reset)          vcount <= 0;
     else if (endOfLine)
       if (endOfField)   vcount <= 0;
       else              vcount <= vcount + 10'd 1;

   assign endOfField = vcount == VTOTAL - 1;

   // Horizontal sync: from 0x520 to 0x5DF (0x57F)
   // 101 0010 0000 to 101 1101 1111
   assign VGA_HS = !( (hcount[10:8] == 3'b101) & !(hcount[7:5] == 3'b111));
   assign VGA_VS = !( vcount[9:1] == (VACTIVE + VFRONT_PORCH) / 2);

   assign VGA_SYNC_n = 1'b0; // For putting sync on the green signal; unused
   
   // Horizontal active: 0 to 1279     Vertical active: 0 to 479
   // 101 0000 0000  1280	       01 1110 0000  480
   // 110 0011 1111  1599	       10 0000 1100  524
   assign VGA_BLANK_n = !( hcount[10] & (hcount[9] | hcount[8]) ) &
			!( vcount[9] | (vcount[8:5] == 4'b1111) );

   /* VGA_CLK is 25 MHz
    *             __    __    __
    * clk50    __|  |__|  |__|
    *        
    *             _____       __
    * hcount[0]__|     |_____|
    */
   assign VGA_CLK = hcount[0]; // 25 MHz clock: rising edge sensitive
   
endmodule
