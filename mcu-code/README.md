# WE KNOW WHAT THE F*CK WAS WRONG!!

__NB__ - _This repo was originally called 'what the f*ck is wrong with me?' as I couldn't work out what was wrong... now I have, it is time to share the knowledge :-D_

Going to go through and add the phrase 'Magic pixie dust' to the places where you needed to do stuff... that way a `grep -R -A 4 'Magic\ pixie\ dust'` will locate the important stuff to get UART working with IRQ's. 

__PS__ - NVIC needs to be better defined to stop manufacturer HAL's b0rking this stuff... it should **not** be this hard!!

## So what is really the issue?

The issue is in the way STM have implemented the configuration of interrupt-based UART on their microcontrollers. Normally there is some `UART_Receive()` function, and a `UART_Transmit()` counterpart function to Rx/Tx data over the UART as desired. These tend to have a timeout lock - you specify as the last parameter how long the function should send/wait for data - say, 100ms. 

What we aim to do here is instead use the interrupt-based UART, where incoming data triggers an IRQ (Interrupt ReQuest) - canonically, these halt the CPU which then starts the Interrupt Handler for the IRQ it receives, which is basically 'code to run when this thing happens'. 

To achieve this, there are similar `UART_Transmit_IT()` and `UART_Receive_IT` versions of these functions that act according to the IRQ state. These are what we want to use, as that way, we aren't locking the UART unnecessarily whilst we wait for data, and don't lock the UART for too long when sending data (meaning we might miss some input). As such, IRQ driven UART is a very useful thing to have around.

## Overview from an ARM perspective

The interrupts we are interested in on our ARM Cortex-M3 take the form of Nested Vectored Interrupt Controller, or NVIC for short. This system lets you set up to 240 interrupts at any of 256 priority levels (see [here](http://infocenter.arm.com/help/index.jsp?topic=/com.arm.doc.dai0179b/ar01s01s01.html) for how it is a little different on the Cortex-M3's than other ARM chipsets).

Now the HAL (Hardware Abstraction Layer) that the manufacturer provides should implement these things faithfully to the documentation...

## How it should be done

It should be as simple as the following two lines of code being added to the `uart_init()` function for your UART handler, to turn on the interrupts:

```
NVIC_SetPriority(UART0_IRQn, 0, 0); // set the appropriate priority
NVIC_EnableIRQ(UART0_IRQn); // turn the interrupt on...
```

We then use the `UART_Receive_IT()` and `UART_Transmit_IT()` functions to send and receive data over IRQ driven UART, and use a `UART_IRQHandler()` function to process the data as the IRQ is triggered. 

## So what is the issue?

Well, it's to do with the implementation on STMicroelectronics chipsets. The designers of the STM32 HAL drivers have not done a fantastic job being faithful to the ARM documentation, so there are various caveats, omissions, and a few 'unusual' labels that can be found when writing IRQ driven UART. So, with the stage set, this is what I'll do a quick write up for now...

## STM32 and UART IRQ's

The process is actually not that difficult nor 'off the beaten track' - rather, it's just realising the decisions that have been made with respect to the Hardware Abstraction Layer itself. This is the crux of the issue - things that you would expect to be set, aren't, and things that you would expect to be named a certain way, aren't. The order in which you do things is still logical and sensible, but it's a bit nonstandard. 

### Enable UART IRQ's

This seems obvious, and there is a well hidden checkbox in STMCubeMX that lets you do this, but in short - you add the following lines to the bottom of `HAL_UART_MspInit()`:
```
    HAL_NVIC_SetPriority(USART1_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(USART1_IRQn);
```

This sets the first USART (which is the first UART when you disable hardware control... yeah, I know...) as being IRQ enabled and having priority zero (i.e. highest). Now we can go on and...


### Enable IRQ Flags

Yes, the flags don't come enabled. No, this doesn't make sense. Yes, this is annoying. To fix this, add these just after the HAL/GPIO/UART init calls in your `main()`:
```
   __HAL_UART_ENABLE_IT(&huart1, UART_IT_RXNE); // flag receive
   __HAL_UART_ENABLE_IT(&huart1, UART_IT_TC); // flat Tx_IT
```

The first in the RXNE (received buffer not empty) flag that is set when some data is received. The second is the TC (transmit complete) flag that is set when the IRQ-based transmit functions are done. 

As you can see, if these aren't enabled, we can't really get our IRQ's to behave correctly.

### Set UART IRQ Handler

This is the bit you see in most blog posts/stack exchange questions on this topic. It's just setting `USART1_IRQHandler()` to have some code in the `stm32f1xx_it.c` file (though I moved mine to `main.c` for convenience of not having to set `extern` variables).

## How I manage it

So, what I have setup in this example code is the following:

1. UART IRQ listens for input, and when it gets something it does two things:
  1. copies a char to a buffer `commBuff` that will hold the whole input up until enter is pressed
  1. outputs the char to the screen so the user can see what's going down
1. IF our char is `\r` or `\n`, i.e. the user pressed enter, it sets the UartReady flag to `SET`, copies the counter to `sent_index` (for use in the main loop) and resets the buffer counter for the next line
1. the `main()` loop is checking whether UartReady is `SET`, and if it is, it puts it to `RESET` and does processing on whatever is in `commBuff`

It's not rocket science, it just feels like it when NONE OF THE EXAMPLE CODE WORKED!!

Well, I hope this is useful to someone with an STM32F103! (or any other STM32...)

# WTFIWWM
What the f*ck is/**WAS** wrong with me?

This is an example STM32F103C8T6 (AKA 'blue pill') project that should setup a UART that gets triggered over the IRQ to do something.

# IT DOESN'T

So, in the spirit of sharing the rage, here's the code. I don't know why it doesn't work. I would love to know why it doens't work.

Halp.
