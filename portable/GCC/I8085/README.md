# LLVM Intel 8085 Port

This port uses the LLVM I8085 stack-argument ABI: arguments begin at SP+2,
16-bit results are in BC, and TCB field zero is the saved task SP. Register
context is ten bytes (PSW, BC, DE, HL, and a prepared SIM byte plus padding),
followed by the two-byte return PC. Each task retains its RST 5.5/6.5/7.5 masks.
New tasks start with SIM value 0x0D, matching the demo's RST 6.5 tick source.

Voluntary yield disables interrupts before saving context or touching SP/TCB;
otherwise an interrupt after switching to the ISR stack can corrupt the task
context. DI/EI macros also provide compiler memory barriers. Interrupt entry
disables maskable interrupts in hardware, and the restore's EI/RET pair resumes
the selected task before another maskable interrupt is accepted.

The application supplies `_isr_stack_top`, `_task_exit_trap`, startup vectors,
and a tick source that calls `vPortTickISR`. The demo reserves a separate
256-byte ISR stack and uses a simulated RST 6.5 timer. A physical board still
needs its own timer/peripheral initialization; this port does not program one.
Change the initial SIM value and board startup together if using other masks.

Do not yield/block inside critical sections or enable nested interrupts in the
tick ISR. Critical nesting is global, not part of the task frame. TRAP is not
masked by DI and must not use the scheduler or shared ISR stack unsafely.

In the parent LLVM SDK, build `FreeRTOS/demos` with `PORT=I8085`. The tracked
`tooling/tests/run-freertos-contract.py` checks repeated scheduler progress and
the context demo verifies non-null task arguments and distinct per-task masks.
Simulation establishes these bounded contracts, not hardware timing or every
possible scheduler interleaving.
