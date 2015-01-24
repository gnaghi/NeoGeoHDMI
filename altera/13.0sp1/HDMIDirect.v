// Charlie Cole 2015
// HDMI output for Neo Geo MVS
//   Originally based on fpga4fun.com HDMI/DVI sample code (c) fpga4fun.com & KNJN LLC 2013
//   Added Neo Geo MVS input, scan doubling, HDMI data packets and audio
//   HDMI output is out of spec by necessity so won't work on all TVs/monitors
//   Offers fake scanline generation (select via button)
//		0: Line doubled but even lines are half brightness
//		1: Line doubled but even lines are half brightness on even frames and vice versa
//		2: Only show even lines (odd lines are black)
//		3: Show even lines on even frames, odd lines on odd frames
//		4: Line doubled

module HDMIDirectV(
	input pixclk, clk_TMDS,  // 24MHz + 120MHz
	input [16:0] videobus,
	input [4:0] Rin, Gin, Bin,
	input dak, sha,
	input button,
	input sync,
	input audioLR,
	input audioClk,
	input audioData,
	output [2:0] TMDSp, TMDSn,
	output TMDSp_clock, TMDSn_clock,
	output [10:0] videoaddressw,
	output videoramenable,
	output videoramclk,
	output videoramoutclk,
	output videowrite,
	output [10:0] videoaddressoutw,
	output [16:0] videobusoutw
);

////////////////////////////////////////////////////////////////////////

// Defines to do with video signal generation
`define DISPLAY_WIDTH			640
`define DISPLAY_HEIGHT			480
`define FULL_WIDTH				768 // Should be 800 for 640x480p
`define FULL_HEIGHT				528 // Should be 525 for 640x480p
`define H_FRONT_PORCH			16
`define H_SYNC						96 
`define V_FRONT_PORCH			10 
`define V_SYNC 					2
`define NEOGEO_VSYNC_LENGTH	80
`define NEOGEO_VSYNC_OFFSET	12	// For centering
`define NEOGEO_HSYNC_OFFSET	8	// For centering

// Defines to do with data packet sending
`define DATA_START		(`DISPLAY_WIDTH+`H_FRONT_PORCH+4) // Need 4 cycles of control data first
`define DATA_PREAMBLE	8
`define DATA_GUARDBAND	2
`define DATA_SIZE			32
`define VIDEO_PREAMBLE	8
`define VIDEO_GUARDBAND	2
`define CTL_END			(`FULL_WIDTH-`VIDEO_PREAMBLE-`VIDEO_GUARDBAND)

////////////////////////////////////////////////////////////////////////
// Line doubler
// Takes the 480i video data from the NeoGeo and doubles the line
// frequency by storing a line in RAM and then displaying it twice.
// Also takes care of centring the picture (using the sync input).
////////////////////////////////////////////////////////////////////////

reg [7:0] red, green, blue;
reg [9:0] CounterX, CounterY;
reg [10:0] videoaddress;
reg [10:0] videoaddressout;
reg [16:0] videobusout;
reg [2:0] scanlineType;
reg hSync, vSync, DrawArea, frame;

initial
begin
	red=0;
	green=0;
	blue=0;
	CounterX=0;
	CounterY=0;
	videoaddress=0;
	videoaddressout=0;
	videobusout=0;
	scanlineType=0;
	hSync=0;
	vSync=0;
	DrawArea=0;
	frame=0;
end

assign videoramenable=1'b1;
assign videoramclk=!pixclk;
assign videoramoutclk=!pixclk;
assign videowrite=1'b1;
assign videoaddressoutw=videoaddressout;
assign videobusoutw=videobusout;
assign videoaddressw=videoaddress;

always @(posedge pixclk) DrawArea <= (CounterX<`DISPLAY_WIDTH) && (CounterY<`DISPLAY_HEIGHT);
always @(posedge pixclk) hSync <= (CounterX>=(`DISPLAY_WIDTH+`H_FRONT_PORCH)) && (CounterX<(`DISPLAY_WIDTH+`H_FRONT_PORCH+`H_SYNC));
always @(posedge pixclk) vSync <= (CounterY>=(`DISPLAY_HEIGHT+`V_FRONT_PORCH)) && (CounterY<(`DISPLAY_HEIGHT+`V_FRONT_PORCH+`V_SYNC));

always @(posedge pixclk)
begin
	CounterX <= (CounterX==(`FULL_WIDTH-1)) ? 0 : CounterX+1;
	if(CounterX==(`FULL_WIDTH-1)) begin
		if (CounterY==(`FULL_HEIGHT-1)) begin
			CounterY <= 0;
			if (scanlineType[0])
				frame <= !frame;
		end else begin
			CounterY <= CounterY+1;
		end
	end
	if (sync) begin
		if ((CounterY <= `NEOGEO_VSYNC_OFFSET || CounterY > `FULL_HEIGHT-`NEOGEO_VSYNC_LENGTH+`NEOGEO_VSYNC_OFFSET))
			CounterY <= `FULL_HEIGHT-`NEOGEO_VSYNC_LENGTH+`NEOGEO_VSYNC_OFFSET+1;
		if (
			(CounterX>>1)+(CounterY[0]?`FULL_WIDTH/2:0)<`FULL_WIDTH-`NEOGEO_HSYNC_OFFSET &&
			(CounterX>>1)+(CounterY[0]?`FULL_WIDTH/2:0)>=`DISPLAY_WIDTH-`NEOGEO_HSYNC_OFFSET)
			CounterX <= (2*(`DISPLAY_WIDTH-`NEOGEO_HSYNC_OFFSET)-`FULL_WIDTH);
	end
	
	if ((CounterX>>1)+(CounterY[0]?`FULL_WIDTH/2:0)<`DISPLAY_WIDTH) begin
		if (CounterX[0]) begin
			videoaddressout<=(CounterY[1]?`DISPLAY_WIDTH:0)+(CounterY[0]?`FULL_WIDTH/2:0)+(CounterX>>1);
			videobusout[4:0]<=Rin;
			videobusout[9:5]<=Gin;
			videobusout[14:10]<=Bin;
			videobusout[15]<=!dak;
			videobusout[16]<=!sha;
		end
	end
	if (CounterX<`DISPLAY_WIDTH) begin
		videoaddress<=(CounterY[1]?0:`DISPLAY_WIDTH) + CounterX;
		if (CounterY[0]==frame || scanlineType==4) begin
			red <= ((videobus[4:0]<<1)|videobus[15])*3 + (videobus[16]?((videobus[4:0]<<1)|videobus[15]):0);
			green <= ((videobus[9:5]<<1)|videobus[15])*3 + (videobus[16]?((videobus[9:5]<<1)|videobus[15]):0);
			blue <= ((videobus[14:10]<<1)|videobus[15])*3 + (videobus[16]?((videobus[14:10]<<1)|videobus[15]):0);
		end else begin
			if (!scanlineType[1]) begin
				red <= (((videobus[4:0]<<1)|videobus[15])*3 + (videobus[16]?((videobus[4:0]<<1)|videobus[15]):0)) >> 1;
				green <= (((videobus[9:5]<<1)|videobus[15])*3 + (videobus[16]?((videobus[9:5]<<1)|videobus[15]):0)) >> 1;
				blue <= (((videobus[14:10]<<1)|videobus[15])*3 + (videobus[16]?((videobus[14:10]<<1)|videobus[15]):0)) >> 1;
			end else begin
				red <= 0;
				green <= 0;
				blue <= 0;
			end
		end
	end
end

////////////////////////////////////////////////////////////////////////
// Neo Geo audio input
////////////////////////////////////////////////////////////////////////

reg [15:0] audioInput [1:0];
reg [15:0] curSampleL;
reg [15:0] curSampleR;

initial
begin
	audioInput[0]=0;
	audioInput[1]=0;
	curSampleL=0;
	curSampleR=0;
end

always @(posedge audioClk) if (audioLR) audioInput[0]<=(audioInput[0]<<1)|audioData; else audioInput[1]<=(audioInput[1]<<1)|audioData;
always @(negedge audioLR) begin curSampleL<=audioInput[0]; curSampleR<=audioInput[1]; end

////////////////////////////////////////////////////////////////////////
// HDMI audio packet generator
////////////////////////////////////////////////////////////////////////

localparam [191:0] channelStatus = 192'hc203004004; // 32KHz 16-bit LPCM audio
reg [23:0] audioPacketHeader;
reg [55:0] audioSubPacket[3:0];
reg [7:0] channelStatusIdx;
reg [10:0] audioTimer;
reg [9:0] audioSamples;
reg [1:0] samplesHead;
reg sendRegenPacket;

initial
begin
	audioPacketHeader=0;
	audioSubPacket[0]=0;
	audioSubPacket[1]=0;
	audioSubPacket[2]=0;
	audioSubPacket[3]=0;
	channelStatusIdx=0;
	audioTimer=0;
	audioSamples=0;
	samplesHead=0;
	sendRegenPacket=0;
end

task AudioPacketGeneration;
	begin
		// Buffer up an audio sample every 750 pixel clocks (32KHz output from 24MHz pixel clock)
		// Don't add to the audio output if we're currently sending that packet though
		if (audioTimer>=749 && !(
			CounterX>=(`DATA_START+`DATA_PREAMBLE+`DATA_GUARDBAND+`DATA_SIZE) &&
			CounterX<(`DATA_START+`DATA_PREAMBLE+`DATA_GUARDBAND+`DATA_SIZE+`DATA_SIZE)
		)) begin
			audioTimer<=audioTimer-749;
			audioPacketHeader<=audioPacketHeader|24'h000002|((channelStatusIdx==0?24'h100100:24'h000100)<<samplesHead);
			audioSubPacket[samplesHead]<=((curSampleL<<8)|(curSampleR<<32)
								|((^curSampleL)?56'h08000000000000:56'h0)		// parity bit for left channel
								|((^curSampleR)?56'h80000000000000:56'h0))	// parity bit for right channel
								^(channelStatus[channelStatusIdx]?56'hCC000000000000:56'h0); // And channel status bit and adjust parity
			if (channelStatusIdx<191)
				channelStatusIdx<=channelStatusIdx+1;
			else
				channelStatusIdx<=0;
			samplesHead<=samplesHead+1;
			audioSamples<=audioSamples+1;
			if (audioSamples[4:0]==0)
				sendRegenPacket<=1;
		end else begin
			audioTimer<=audioTimer+1;
		end
	end
endtask

////////////////////////////////////////////////////////////////////////
// Error correction code generator
// Generates error correction codes needed for verifying HDMI packets
////////////////////////////////////////////////////////////////////////

function [7:0] ECCcode;	// Cycles the error code generator
	input [7:0] code;
	input bita;
	input passthroughData;
	begin
		ECCcode = (code<<1) ^ (((code[7]^bita) && passthroughData)?(1+(1<<6)+(1<<7)):0);
	end
endfunction

task ECCu;
	output outbit;
	inout [7:0] code;
	input bita;
	input passthroughData;
	begin
		outbit <= passthroughData?bita:code[7];
		code <= ECCcode(code, bita, passthroughData);
	end
endtask

task ECC2u;
	output outbita;
	output outbitb;
	inout [7:0] code;
	input bita;
	input bitb;
	input passthroughData;
	begin
		outbita <= passthroughData?bita:code[7];
		outbitb <= passthroughData?bitb:(code[6]^(((code[7]^bita) && passthroughData)?1'b1:1'b0));
		code <= ECCcode(ECCcode(code, bita, passthroughData), bitb, passthroughData);
	end
endtask

////////////////////////////////////////////////////////////////////////
// Packet sending
// During hsync periods send audio data and infoframe data packets
////////////////////////////////////////////////////////////////////////

reg [3:0] dataChannel0;
reg [3:0] dataChannel1;
reg [3:0] dataChannel2;
reg [23:0] packetHeader;
reg [55:0] subpacket[3:0];
reg [7:0] bchHdr;
reg [7:0] bchCode [3:0];
reg [4:0] dataOffset;
reg [3:0] preamble;
reg tercData;
reg dataGuardBand;
reg videoGuardBand;

initial
begin
	dataChannel0=0;
	dataChannel1=0;
	dataChannel2=0;
	packetHeader=0;
	subpacket[0]=0;
	subpacket[1]=0;
	subpacket[2]=0;
	subpacket[3]=0;
	bchHdr=0;
	bchCode[0]=0;
	bchCode[1]=0;
	bchCode[2]=0;
	bchCode[3]=0;
	dataOffset=0;
	preamble=0;
	tercData=0;
	dataGuardBand=0;
	videoGuardBand=0;
end

task SendPacket;
	inout [32:0] pckHeader;
	inout [55:0] pckData0;
	inout [55:0] pckData1;
	inout [55:0] pckData2;
	inout [55:0] pckData3;
	input firstPacket;
begin
	dataChannel0[0]=hSync;
	dataChannel0[1]=vSync;
	dataChannel0[3]=(!firstPacket || dataOffset)?1'b1:1'b0;
	ECCu(dataChannel0[2], bchHdr, pckHeader[0], dataOffset<24?1'b1:1'b0);
	ECC2u(dataChannel1[0], dataChannel2[0], bchCode[0], pckData0[0], pckData0[1], dataOffset<28?1'b1:1'b0);
	ECC2u(dataChannel1[1], dataChannel2[1], bchCode[1], pckData1[0], pckData1[1], dataOffset<28?1'b1:1'b0);
	ECC2u(dataChannel1[2], dataChannel2[2], bchCode[2], pckData2[0], pckData2[1], dataOffset<28?1'b1:1'b0);
	ECC2u(dataChannel1[3], dataChannel2[3], bchCode[3], pckData3[0], pckData3[1], dataOffset<28?1'b1:1'b0);
	pckHeader<=pckHeader[23:1];
	pckData0<=pckData0[55:2];
	pckData1<=pckData1[55:2];
	pckData2<=pckData2[55:2];
	pckData3<=pckData3[55:2];
	dataOffset<=dataOffset+5'b1;
end
endtask

always @(posedge pixclk)
begin
	AudioPacketGeneration();
	// Start sending audio data if we're in the right part of the hsync period
	if (CounterX>=`DATA_START)
	begin
		if (CounterX<(`DATA_START+`DATA_PREAMBLE))
		begin
			// Send the data period preamble
			// A nice "feature" of my test monitor (GL2450) is if you comment out
			// this line you see your data next to your image which is useful for
			// debugging
			preamble<='b0101;
		end
		else if (CounterX<(`DATA_START+`DATA_PREAMBLE+`DATA_GUARDBAND))
		begin
			// Start sending leading data guard band
			tercData<=1;
			dataGuardBand<=1;
			dataChannel0<={1'b1, 1'b1, vSync, hSync};
			preamble<=0;
			// Set up the first of the packets we'll send
			if (sendRegenPacket) begin
				packetHeader<=24'h000001;	// audio clock regeneration packet (N=0x1000 CTS=0x6270)
				subpacket[0]<=56'h001000c05d0000;	// N=0x1000 CTS=0x5dc0 (24MHz pixel clock -> 32KHz audio clock)
				subpacket[1]<=56'h001000c05d0000;
				subpacket[2]<=56'h001000c05d0000;
				subpacket[3]<=56'h001000c05d0000;
				if (CounterX==(`DATA_START+`DATA_PREAMBLE+`DATA_GUARDBAND-1))
					sendRegenPacket<=0;
			end else begin
				if (!CounterY[0]) begin
					packetHeader<=24'h0D0282;	// infoframe AVI packet
					subpacket[0]<=56'h0000010019107b;
					subpacket[1]<=56'h0501000005bf00;
				end else begin
					packetHeader<=24'h0A0184;	// infoframe audio packet
					subpacket[0]<=56'h0000000000115f;
					subpacket[1]<=56'h00000000000000;
				end
				subpacket[2]<=56'h00000000000000;
				subpacket[3]<=56'h00000000000000;
			end
		end
		else if (CounterX<(`DATA_START+`DATA_PREAMBLE+`DATA_GUARDBAND+`DATA_SIZE))
		begin
			dataGuardBand<=0;
			// Send first data packet (Infoframe or audio clock regen)
			SendPacket(packetHeader, subpacket[0], subpacket[1], subpacket[2], subpacket[3], 1);
		end
		else if (CounterX<(`DATA_START+`DATA_PREAMBLE+`DATA_GUARDBAND+`DATA_SIZE+`DATA_SIZE))
		begin
			// Send second data packet (audio data)
			SendPacket(audioPacketHeader, audioSubPacket[0], audioSubPacket[1], audioSubPacket[2], audioSubPacket[3], 0);
		end
		else if (CounterX<(`DATA_START+`DATA_PREAMBLE+`DATA_GUARDBAND+`DATA_SIZE+`DATA_SIZE+`DATA_GUARDBAND))
		begin
			// Trailing guardband for data period
			dataGuardBand<=1;
			dataChannel0<={1'b1, 1'b1, vSync, hSync};	
		end
		else
		begin
			// Back to normal DVI style control data
			tercData<=0;
			dataGuardBand<=0;
		end
	end
	// After we've sent data packets we need to do the video preamble and
	// guardband just before sending active video data
	if (CounterX>=(`CTL_END+`VIDEO_PREAMBLE))
	begin
		preamble<=0;
		videoGuardBand<=1;
	end
	else if (CounterX>=(`CTL_END))
	begin
		preamble<='b0001;
	end
	else
	begin
		videoGuardBand<=0;
	end
end

////////////////////////////////////////////////////////////////////////
// HDMI encoder
// Encodes video data (TMDS) or packet data (TERC4) ready for sending
////////////////////////////////////////////////////////////////////////

reg tercDataDelayed;
reg videoGuardBandDelayed;
reg dataGuardBandDelayed;

initial
begin
	tercDataDelayed=0;
	videoGuardBandDelayed=0;
	dataGuardBandDelayed=0;
end

always @(posedge pixclk)
begin
	tercDataDelayed<=tercData;	// To account for delay through encoder
	videoGuardBandDelayed<=videoGuardBand;
	dataGuardBandDelayed<=dataGuardBand;
end

wire [9:0] TMDS_red, TMDS_green, TMDS_blue;
TMDS_encoder encode_R(.clk(pixclk), .VD(red  ), .CD(preamble[3:2]), .VDE(DrawArea), .TMDS(TMDS_red));
TMDS_encoder encode_G(.clk(pixclk), .VD(green), .CD(preamble[1:0]), .VDE(DrawArea), .TMDS(TMDS_green));
TMDS_encoder encode_B(.clk(pixclk), .VD(blue ), .CD({vSync,hSync}), .VDE(DrawArea), .TMDS(TMDS_blue));

wire [9:0] TERC4_red, TERC4_green, TERC4_blue;
TERC4_encoder encode_R4(.clk(pixclk), .data(dataChannel2), .TERC(TERC4_red));
TERC4_encoder encode_G4(.clk(pixclk), .data(dataChannel1), .TERC(TERC4_green));
TERC4_encoder encode_B4(.clk(pixclk), .data(dataChannel0), .TERC(TERC4_blue));

wire [9:0] redSource = videoGuardBandDelayed ? 10'b1011001100 : (dataGuardBandDelayed ? 10'b0100110011 : (tercDataDelayed ? TERC4_red : TMDS_red));
wire [9:0] greenSource = (dataGuardBandDelayed || videoGuardBandDelayed) ? 10'b0100110011 : (tercDataDelayed ? TERC4_green : TMDS_green);
wire [9:0] blueSource = videoGuardBandDelayed ? 10'b1011001100 : (tercDataDelayed ? TERC4_blue : TMDS_blue);

////////////////////////////////////////////////////////////////////////
// HDMI data serialiser
// Outputs the encoded video data as serial data across the HDMI bus
////////////////////////////////////////////////////////////////////////

reg [3:0] TMDS_mod10;  // modulus 10 counter
reg [9:0] TMDS_shift_red, TMDS_shift_green, TMDS_shift_blue;

initial
begin
  TMDS_mod10=0;
  TMDS_shift_red=0;
  TMDS_shift_green=0;
  TMDS_shift_blue=0;
end

always @(posedge clk_TMDS)
begin
	TMDS_shift_red   <= (TMDS_mod10==4'd0) ? redSource   : TMDS_shift_red  [9:2];
	TMDS_shift_green <= (TMDS_mod10==4'd0) ? greenSource : TMDS_shift_green[9:2];
	TMDS_shift_blue  <= (TMDS_mod10==4'd0) ? blueSource  : TMDS_shift_blue [9:2];	
	TMDS_mod10 <= (TMDS_mod10==4'd8) ? 4'd0 : TMDS_mod10+4'd2;
end

assign TMDSp[2]=clk_TMDS?TMDS_shift_red[0]:TMDS_shift_red[1];
assign TMDSn[2]=~TMDSp[2];
assign TMDSp[1]=clk_TMDS?TMDS_shift_green[0]:TMDS_shift_green[1];
assign TMDSn[1]=!TMDSp[1];
assign TMDSp[0]=clk_TMDS?TMDS_shift_blue[0]:TMDS_shift_blue[1];
assign TMDSn[0]=!TMDSp[0];
assign TMDSp_clock=pixclk;
assign TMDSn_clock=!pixclk;

////////////////////////////////////////////////////////////////////////
// Scanline method selection button debouncer
////////////////////////////////////////////////////////////////////////

reg [15:0] buttonDebounce;

initial
begin
	buttonDebounce=0;
end

always @(posedge audioClk)
begin
	if (!button) begin
		if (buttonDebounce!=0)
			scanlineType<=scanlineType!=4?scanlineType+1:0;
		buttonDebounce<=0;
	end else if (buttonDebounce!='hffff) begin	// Audio clock is 6MHz so this is about 11ms
		buttonDebounce<=buttonDebounce+1;
	end
end

endmodule

////////////////////////////////////////////////////////////////////////
// TMDS encoder
// Used to encode HDMI/DVI video data
////////////////////////////////////////////////////////////////////////

module TMDS_encoder(
	input clk,
	input [7:0] VD,  // video data (red, green or blue)
	input [1:0] CD,  // control data
	input VDE,  // video data enable, to choose between CD (when VDE=0) and VD (when VDE=1)
	output reg [9:0] TMDS
);

wire [3:0] Nb1s = VD[0] + VD[1] + VD[2] + VD[3] + VD[4] + VD[5] + VD[6] + VD[7];
wire XNOR = (Nb1s>4'd4) || (Nb1s==4'd4 && VD[0]==1'b0);
wire [8:0] q_m = {~XNOR, q_m[6:0] ^ VD[7:1] ^ {7{XNOR}}, VD[0]};

reg [3:0] balance_acc;

initial begin
	balance_acc=0;
end

wire [3:0] balance = q_m[0] + q_m[1] + q_m[2] + q_m[3] + q_m[4] + q_m[5] + q_m[6] + q_m[7] - 4'd4;
wire balance_sign_eq = (balance[3] == balance_acc[3]);
wire invert_q_m = (balance==0 || balance_acc==0) ? ~q_m[8] : balance_sign_eq;
wire [3:0] balance_acc_inc = balance - ({q_m[8] ^ ~balance_sign_eq} & ~(balance==0 || balance_acc==0));
wire [3:0] balance_acc_new = invert_q_m ? balance_acc-balance_acc_inc : balance_acc+balance_acc_inc;
wire [9:0] TMDS_data = {invert_q_m, q_m[8], q_m[7:0] ^ {8{invert_q_m}}};
wire [9:0] TMDS_code = CD[1] ? (CD[0] ? 10'b1010101011 : 10'b0101010100) : (CD[0] ? 10'b0010101011 : 10'b1101010100);

always @(posedge clk) TMDS <= VDE ? TMDS_data : TMDS_code;
always @(posedge clk) balance_acc <= VDE ? balance_acc_new : 4'h0;
endmodule

////////////////////////////////////////////////////////////////////////
// TERC4 Encoder
// Used to encode the HDMI data packets such as audio
////////////////////////////////////////////////////////////////////////

module TERC4_encoder(
	input clk,
	input [3:0] data,
	output reg [9:0] TERC
);

always @(posedge clk)
begin
	case (data)
		4'b0000: TERC <= 10'b1010011100;
		4'b0001: TERC <= 10'b1001100011;
		4'b0010: TERC <= 10'b1011100100;
		4'b0011: TERC <= 10'b1011100010;
		4'b0100: TERC <= 10'b0101110001;
		4'b0101: TERC <= 10'b0100011110;
		4'b0110: TERC <= 10'b0110001110;
		4'b0111: TERC <= 10'b0100111100;
		4'b1000: TERC <= 10'b1011001100;
		4'b1001: TERC <= 10'b0100111001;
		4'b1010: TERC <= 10'b0110011100;
		4'b1011: TERC <= 10'b1011000110;
		4'b1100: TERC <= 10'b1010001110;
		4'b1101: TERC <= 10'b1001110001;
		4'b1110: TERC <= 10'b0101100011;
		4'b1111: TERC <= 10'b1011000011;
	endcase
end

endmodule

////////////////////////////////////////////////////////////////////////
