/*
 * This code is mostly mine - some of it was adapted from here: 
  * https://github.com/deanjerkovich/avr-glitch-101
 * 
 * But the concept now is different - we want controllable glitches, 
 * that we can drive through, say, and python script using PySerial. 
 * This means that we take a value, and then use that (multiplied by 
 * 512) as our glitch time value 
 * 
 * So, yeah - most of this is written/hacked together by me on a Sunday
 * afternoon... 
 * 
 * Released under MIT License: 
 * 
 * Permission is hereby granted, free of charge, to any person obtaining 
 * a copy of this software and associated documentation files (the 
 * "Software"), to deal in the Software without restriction, including 
 * without limitation the rights to use, copy, modify, merge, publish, 
 * distribute, sublicense, and/or sell copies of the Software, and to 
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be 
 * included in all copies or substantial portions of the Software.
 *
 */

`include "cores/osdvu/uart.v"
`include "pll-72.v"


// These I set and then didn't really use... 
// I've left them here as example artefacts in case someone wants
// to use them in some re-implementation... just reference them 
// including a preceeding backtick... e.g.
// if (counter == `WAIT_TIME) begin...
// as a quick example line. :-P
`define GLITCH_DURATION 26000
`define GLITCH_MULTIPLIER 100
`define WAIT_TIME       72000000
`define RST_TIME        36000000

module top(
	input iCE_CLK,
	input RS232_Rx_TTL,
	output RS232_Tx_TTL,
	output LED0,
	output LED1,
	output LED2,
	output LED3,
	output LED4,
    output J1_1
	);
    
    assign LED0 = outreg;
    assign LED1 = ~outreg;
    assign J1_1 = outreg;
    
    reg outreg;
    reg [31:0] counter;

	wire pll_clk;
	wire pll_lck;

	// PLL stuff
	pll pLL (
		.clock_in(iCE_CLK),
		.clock_out(pll_clk),
		.locked(pll_lck)
	);

	// UART stuff

	wire reset = 0;
	reg transmit;
	reg [7:0] tx_byte;
	wire received;
	wire [7:0] rx_byte;
	wire is_receiving;
	wire is_transmitting;
	wire recv_error;

	assign LED4 = recv_error;
	assign {LED3, LED2} = rx_byte[7:6];

	uart #(
		.baud_rate(115200),                 // The baud rate in kilobits/s
		.sys_clk_freq(12000000)           // The master clock frequency
	)
	uart0(
		.clk(iCE_CLK),                    // The master clock for this module
		.rst(reset),                      // Synchronous reset
		.rx(RS232_Rx_TTL),                // Incoming serial line
		.tx(RS232_Tx_TTL),                // Outgoing serial line
		.transmit(transmit),              // Signal to transmit
		.tx_byte(tx_byte),                // Byte to transmit
		.received(received),              // Indicated that a byte has been received
		.rx_byte(rx_byte),                // Byte received
		.is_receiving(is_receiving),      // Low when receive line is idle
		.is_transmitting(is_transmitting),// Low when transmit line is idle
		.recv_error(recv_error)           // Indicates error in receiving packet.
	);
    
    // glitch values from UART
    
    reg [7:0] uart_var1;
    reg [7:0] uart_var2;
    reg [31:0] var1;
    reg [31:0] var2;
    reg glitch;
    wire glitch_signal; // as you can't drive a reg from different always
    
    initial begin
        counter <= 0;
        outreg <= 1;
        glitch <= 0;
    end
	always @(posedge iCE_CLK) begin
        // dirty reset of glitch signal if it is set - saves on
        // waiting for UART to change mode 
        // NB - our other clock is a lot faster, so will certainly 
        // see this signal most of the time #DirtyHax
        if (glitch_signal) begin
            glitch_signal <= 0;
        end
		if (received) begin
            // send byte back to the serial port so we can check
            tx_byte <= rx_byte;
			transmit <= 1;
            // send the byte to the interface register
            uart_var1 <= rx_byte;
            // set glitch signal
            glitch_signal <= 1;
            // send value of byte
        end else begin
		    transmit <= 0;
        end
	end

	always @(posedge pll_clk) begin
        // increment clock...
        counter <= counter +1;
        // check if glitch_signal is on, and if yes,
        // reset counter and set glitch flag
        if (glitch_signal && !glitch) begin
            // turns out we don't know the interface register 
            // uart_var1... take rx_byte and multiply it by 512 - this 
            // gives us roughly +7 microsecond increase in glitch time 
            // for every +1 increase in UART byte value... ish...
            var1 <= rx_byte << 8;
            glitch <= 1;
            counter <= 0;
        end else if (glitch) begin
        // if we are in glitch, set outreg to 0
            outreg <= 0;
        end
        // if we are in a glitch (outreg is 0) and we reach the desired
        // duration, then unset glitch and put outreg to 1
        if (counter == var1 && !outreg) begin
            outreg <= 1;
            glitch <= 0;
        end
    // end always
	end
endmodule
