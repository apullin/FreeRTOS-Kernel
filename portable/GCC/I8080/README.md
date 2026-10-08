# LLVM Intel 8080 Port

This port uses the LLVM I8085 stack-argument ABI and only base 8080 instructions.
It saves eight register bytes (PSW, BC, DE, HL), followed by a two-byte return PC.
There is no SIM/RIM mask state. Voluntary yield disables interrupts before
changing task context or switching to the ISR stack. DI/EI macros also provide
compiler memory barriers.

The application supplies `_isr_stack_top`, `_task_exit_trap`, startup vectors,
and an external tick source. The shared SDK demo uses RST 7 at address 0x0038.
An actual board needs interrupt-controller/timer setup and any device-specific
acknowledgement; the generic port does not program an 8259 or 8253.

Do not yield/block inside critical sections or enable nested interrupts in the
tick ISR. Critical nesting is global, not part of the task frame.

In the parent LLVM SDK, build `FreeRTOS/demos` with `PORT=I8080`; the default
output is `build-8080`, separate from the 8085 build. The tracked contract runner
uses the simulator's base RST interrupt path, checks executable opcodes for
8085-only instructions, and exercises scheduler progress and task arguments.
The simulator remains an 8085 timing model, not a cycle-accurate 8080 board.
