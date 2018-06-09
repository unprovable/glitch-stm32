/*
 * Copyright 2015 Forest Crossman
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

`include "cores/osdvu/uart.v"
`include "pll-72.v"

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
    //assign LED1 = ~outreg;
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
		.baud_rate(9600),                 // The baud rate in kilobits/s
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
        // waiting for UART to change mode NB - our other clock is a lot
        // faster, so will certainly see this signal
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
            // turns out we don't know the interface register uart_var1...
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
