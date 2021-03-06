//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,
	
	input         CLK_AUDIO,
	
	//output        CLK_AUDIO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

///////// Default values for ports not used in this core /////////

assign USER_OUT = '1;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  

assign AUDIO_S = 0;  // 1 - signed audio samples, 0 - unsigned
assign AUDIO_MIX = status[4:3];

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

assign VIDEO_ARX = status[7] ? 8'd16 : 8'd4;
assign VIDEO_ARY = status[7] ? 8'd9  : 8'd3; 

// Status Bit Map:
//             Upper                             Lower              
// 0         1         2         3          4         5         6   
// 01234567890123456789012345678901 23456789012345678901234567890123
// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
// XXXXXXXX      X X                    


`include "build_id.v" 
localparam CONF_STR = {
	"ZET;;",
	"-;",
	"S,VHD;",
	"OE,Reset after Mount,No,Yes;",
   "-;",
	"O7,Aspect ratio,4:3,16:9;",
	"O56,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"-;",
	"OD,Joysticks Swap,No,Yes;",
	"-;",
	"TF,Soft Reset;",
	"T0,Hard Reset;",
	"R0,Reset and close OSD;",
	"V,v",`BUILD_DATE 
};

//////////////////   HPS I/O   ///////////////////

wire forced_scandoubler;
wire  [1:0] buttons;
wire [63:0] status;
wire [10:0] ps2_key;
wire [24:0] ps2_mouse;

wire [31:0] sd_lba;
wire        sd_rd;
wire        sd_wr;
wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire        img_readonly;
wire [63:0] img_size;
wire        sd_ack_conf;

wire        ps2_kbd_clk_out;
wire        ps2_kbd_data_out;
wire        ps2_kbd_clk_in;
wire        ps2_kbd_data_in;
wire        ps2_mouse_clk_out;
wire        ps2_mouse_data_out;
wire        ps2_mouse_clk_in;
wire        ps2_mouse_data_in;

wire [15:0] joy_0 = status[13] ? joy_B : joy_A;
wire [15:0] joy_1 = status[13] ? joy_A : joy_B;
wire [15:0] joy_A;
wire [15:0] joy_B;

wire [21:0] gamma_bus;

hps_io #(.STRLEN($size(CONF_STR)>>3), .PS2DIV(1000)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),
	.forced_scandoubler(forced_scandoubler),

	.joystick_0(joy_A),
	.joystick_1(joy_B),
	
	.buttons(buttons),
	.status(status),
	
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_ack_conf(sd_ack_conf),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),

	.ioctl_wait(0),
			
   .ps2_kbd_clk_in(ps2_kbd_clk_out),
	.ps2_kbd_data_in(ps2_kbd_data_out),
	.ps2_kbd_clk_out(ps2_kbd_clk_in),
	.ps2_kbd_data_out(ps2_kbd_data_in),
	
	.ps2_mouse_clk_in(ps2_mouse_clk_out),
	.ps2_mouse_data_in(ps2_mouse_data_out),
	.ps2_mouse_clk_out(ps2_mouse_clk_in),
	.ps2_mouse_data_out(ps2_mouse_data_in),
	
	.gamma_bus(gamma_bus)

);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys,sdram_clk,clk_dvi;
wire pll_locked ;
wire reset;


pll pll (
    .refclk (CLK_50M),
	 .rst    (0),
    .outclk_0(sdram_clk),	// 100 Mhz
    .outclk_1(clk_sys),	   // 25 Mhz
    .outclk_2(clk_dvi),		// 125 MHz    
    .locked (pll_locked)
);

assign reset = RESET | status[0] | buttons[1] | !pll_locked | (status[14] && img_mounted);






reg [1:0] SDRAM_DQM;

assign SDRAM_DQML = SDRAM_DQM[0];
assign SDRAM_DQMH = SDRAM_DQM[1];

//////////////////////////////////////////////////////////////////



kotku  kotku
(
   // clocks
	.sdram_clk           (sdram_clk),
	.clk                 (clk_sys),
	.clk_dvi             (clk_dvi),
	.lock                (pll_locked),
 	// sdram signals
	.sdram_addr_         (SDRAM_A),
	.sdram_data_         (SDRAM_DQ),
	.sdram_ba_           (SDRAM_BA), 
	.sdram_ras_n_        (SDRAM_nRAS),
	.sdram_cas_n_        (SDRAM_nCAS),
	.sdram_clk_          (SDRAM_CLK),
	.sdram_we_n_         (SDRAM_nWE),
	.sdram_dqm_          (SDRAM_DQM),
	.sdram_cs_n          (SDRAM_nCS),
	.sdram_cke_          (SDRAM_CKE),
	//PS2
   .ps2_kclk_          (ps2_kbd_clk_out),			// PS2 keyboard Clock
   .ps2_kdat_			   (ps2_kbd_data_out),// PS2 Keyboard Data
   .ps2_mclk_			   (ps2_mouse_clk_out),// PS2 Mouse Clock
   .ps2_mdat_			   (ps2_mouse_clk_out),// PS2 Mouse Data

	
	// SD card signals
	.sd_sclk_            (sdclk),
	.sd_miso_            (sdmiso),
	.sd_mosi_            (sdmosi),
	.sd_ss_              (sdss),
	
	// VGA
	.red                 (rgb_r),
	.green               (rgb_g),
	.blue                (rgb_b),
	.tft_lcd_hsync_      (hs),
	.tft_lcd_vsync_      (vs),
	.horiz_blank         (HBlank),
	.vert_blank          (VBlank),
	
	//Reset
	.reset               (reset),
	// UART signals
	.uart_txd_            (UART_TXD),
	.uart_rxd_            (UART_RXD)
	
);
///////////////////////////////////////////////////



///////////////////////////////////////////////////

assign CLK_VIDEO = clk_sys;

wire [2:0] scale = status[6:5];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;
//wire       scandoubler = scale || forced_scandoubler;

assign VGA_F1 = 0;
assign VGA_SL = sl[1:0];
//assign CE_PIXEL = scandoubler ? ce_pix_out : ce_pix2;


wire hs, vs;
wire HBlank;
wire HSync;
wire VBlank;
wire VSync;
wire ce_pix;

wire [3:0] rgb_r;
wire [3:0] rgb_g;
wire [3:0] rgb_b;

assign HSync = hs;
assign VSync = vs;
assign Rx  = {rgb_r,rgb_r};
assign Gx  = {rgb_g,rgb_g};
assign Bx  = {rgb_b,rgb_b};

wire ce_sys = clk_sys;
reg [1:0] ce_sys2;
always @(posedge clk_sys) ce_sys2 <= {ce_sys2[0],ce_sys};

reg ce_vid;
reg [7:0] Rx, Gx, Bx;
always @(posedge CLK_VIDEO) begin
  reg ce1;
  
  ce1 <= |ce_sys2;
  ce_vid <= ce1;
end

video_mixer #(.LINE_LENGTH(448), .HALF_DEPTH(0), .GAMMA(1)) video_mixer
(
  .*,
  .clk_vid(CLK_VIDEO),
  .ce_pix(ce_vid),
  .ce_pix_out(CE_PIXEL),

  .hq2x(scale == 1),
  .scanlines(0),
  .scandoubler(scale || forced_scandoubler),

  .R(Rx),
  .G(Gx),
  .B(Bx),
  .mono(0)
);

//////////////////   SD   ///////////////////

wire sdclk;
wire sdmosi;
wire sdmiso = vsd_sel ? vsdmiso : SD_MISO;
wire sdss;

reg vsd_sel = 0;
always @(posedge clk_sys) if(img_mounted) vsd_sel <= |img_size;

wire vsdmiso;
sd_card sd_card
(
	.*,
	.clk_spi(CLK_50M),
	.sdhc(1),
	.sck(sdclk),
	.ss(sdss | ~vsd_sel),
	.mosi(sdmosi),
	.miso(vsdmiso)
);

assign SD_CS   = sdss   |  vsd_sel;
assign SD_SCK  = sdclk  & ~vsd_sel;
assign SD_MOSI = sdmosi & ~vsd_sel;



always @(posedge clk_sys) begin
	reg old_mosi, old_miso;
	integer timeout = 0;

	old_mosi <= sdmosi;
	old_miso <= sdmiso;

	if(timeout < 1000000) begin
		timeout <= timeout + 1;
	end

	if((old_mosi ^ sdmosi) || (old_miso ^ sdmiso)) timeout <= 0;
end



endmodule
