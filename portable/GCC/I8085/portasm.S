; ---------------------------------------------------------------------------
; FreeRTOS Intel 8085 port - context switch assembly
;
; Saved registers (10 bytes), followed by the 2-byte return PC:
;   [xx] [IntMask] [L] [H] [E] [D] [C] [B] [Flags] [A] [PC_lo] [PC_hi]
;   ^--- pxTopOfStack (SP) points here
;
; The bottom 2 bytes are the 8085-specific interrupt mask, saved via
; RIM and restored via SIM. This allows each task to have its own
; RST 5.5/6.5/7.5 mask state, preserved across context switches.
;
; The SIM byte format stored is: [0 0 0 0 MSE=1 M7.5 M6.5 M5.5]
; On restore, POP PSW loads A = SIM byte, then SIM applies it.
;
; The order is: PUSH PSW (regs), PUSH B, PUSH D, PUSH H, RIM+PUSH PSW (mask).
; Restore is: POP PSW (mask)+SIM, POP H, POP D, POP B, POP PSW (regs), RET.
;
; pxCurrentTCB->pxTopOfStack is the first field of the TCB, a 16-bit
; pointer stored little-endian (low byte at lower address).
; ---------------------------------------------------------------------------

    .text

; External symbols from FreeRTOS kernel
    .extern pxCurrentTCB
    .extern xTaskIncrementTick
    .extern vTaskSwitchContext
    .extern uxCriticalNesting

; ---------------------------------------------------------------------------
; vPortStartFirstTask
;
; Called from xPortStartScheduler(). Loads the first task's saved SP
; from pxCurrentTCB and restores its context.
; Never returns.
; ---------------------------------------------------------------------------
    .globl vPortStartFirstTask
vPortStartFirstTask:
    ; HL = address of pxCurrentTCB (pointer to current TCB)
    LHLD pxCurrentTCB       ; HL = pxCurrentTCB (TCB address)
    ; First field of TCB is pxTopOfStack (16-bit pointer, little-endian)
    MOV E, M                ; E = low byte of saved SP
    INX H
    MOV D, M                ; D = high byte of saved SP
    XCHG                    ; HL = saved SP
    SPHL                    ; SP = task's saved stack pointer

    ; Restore 8085 interrupt mask (per-task SIM state)
    POP PSW                 ; A = prepared SIM byte
    SIM                     ; Apply per-task interrupt mask

    ; Restore registers from the task's stack frame
    POP H                   ; Restore HL
    POP D                   ; Restore DE
    POP B                   ; Restore BC
    POP PSW                 ; Restore A + flags

    EI                      ; Enable interrupts
    RET                     ; Jump to task entry point (PC on stack)

; ---------------------------------------------------------------------------
; vPortYield
;
; Voluntary context switch, called from task code via CALL.
; The return address is already on the stack from the CALL instruction.
;
; We save all registers, store the SP into the current TCB, call
; vTaskSwitchContext to select the next task, then restore the new
; task's context.
; ---------------------------------------------------------------------------
    .globl vPortYield
vPortYield:
    DI                      ; Protect task context before changing SP or TCB
    ; Return address already on stack from CALL
    ; Save all registers
    PUSH PSW                ; Save A + flags
    PUSH B                  ; Save BC
    PUSH D                  ; Save DE
    PUSH H                  ; Save HL

    ; Save 8085 interrupt mask (per-task state)
    ; RIM returns: [SID I7.5p I6.5p I5.5p IE M7.5 M6.5 M5.5]
    ; We prepare a SIM byte: [0 0 0 0 MSE=1 M7.5 M6.5 M5.5]
    RIM                     ; Read current interrupt mask
    ANI 0x07                ; Keep only mask bits (M7.5, M6.5, M5.5)
    ORI 0x08                ; Set MSE=1 (mask set enable for SIM)
    PUSH PSW                ; Save prepared SIM byte

    ; --- Save SP to current TCB ---
    ; HL = current SP
    LXI H, 0
    DAD SP                  ; HL = SP (no direct read of SP)
    XCHG                    ; DE = SP value

    ; Store SP into pxCurrentTCB->pxTopOfStack
    LHLD pxCurrentTCB       ; HL = TCB address
    MOV M, E                ; Store SP low byte
    INX H
    MOV M, D                ; Store SP high byte

    ; Switch to ISR stack for scheduler call
    LXI SP, _isr_stack_top

    ; Disable interrupts during scheduler operation
    DI

    ; Select next task
    CALL vTaskSwitchContext

    ; --- Restore new task's context ---
    LHLD pxCurrentTCB       ; HL = new TCB address
    MOV E, M                ; E = low byte of saved SP
    INX H
    MOV D, M                ; D = high byte of saved SP
    XCHG                    ; HL = saved SP
    SPHL                    ; SP = new task's stack pointer

    ; Restore 8085 interrupt mask (per-task SIM state)
    POP PSW                 ; A = prepared SIM byte
    SIM                     ; Apply per-task interrupt mask

    POP H                   ; Restore HL
    POP D                   ; Restore DE
    POP B                   ; Restore BC
    POP PSW                 ; Restore A + flags

    EI                      ; Re-enable interrupts
    RET                     ; Resume new task

; ---------------------------------------------------------------------------
; vPortTickISR
;
; Timer interrupt handler (RST 6.5 at vector 0x0034).
;
; The 8085 hardware saves the PC on the stack when servicing an interrupt
; (via the RST mechanism) and automatically disables interrupts (clears
; the interrupt enable flip-flop).
;
; We save all registers, call xTaskIncrementTick(), and if a context
; switch is needed, call vTaskSwitchContext() and restore the new task.
; ---------------------------------------------------------------------------
    .globl vPortTickISR
vPortTickISR:
    ; PC already saved by the RST/interrupt hardware
    PUSH PSW                ; Save A + flags
    PUSH B                  ; Save BC
    PUSH D                  ; Save DE
    PUSH H                  ; Save HL

    ; Save 8085 interrupt mask (per-task state)
    RIM                     ; Read current interrupt mask
    ANI 0x07                ; Keep only mask bits
    ORI 0x08                ; Set MSE=1 for SIM format
    PUSH PSW                ; Save prepared SIM byte

    ; --- Save SP to current TCB ---
    LXI H, 0
    DAD SP                  ; HL = current SP
    XCHG                    ; DE = SP

    LHLD pxCurrentTCB       ; HL = current TCB address
    MOV M, E                ; Store SP low byte
    INX H
    MOV M, D                ; Store SP high byte

    ; Switch to ISR stack
    LXI SP, _isr_stack_top

    ; Call xTaskIncrementTick()
    ; Returns BaseType_t (int16_t) in BC per i8085 calling convention
    CALL xTaskIncrementTick

    ; Check if context switch needed (BC != 0)
    MOV A, C
    ORA B
    JZ .Ltick_no_switch

    CALL vTaskSwitchContext

.Ltick_no_switch:
    ; --- Restore (possibly new) task's context ---
    LHLD pxCurrentTCB       ; HL = (possibly new) TCB address
    MOV E, M                ; E = low byte of saved SP
    INX H
    MOV D, M                ; D = high byte of saved SP
    XCHG                    ; HL = saved SP
    SPHL                    ; SP = task's stack pointer

    ; Restore 8085 interrupt mask (per-task SIM state)
    POP PSW                 ; A = prepared SIM byte
    SIM                     ; Apply per-task interrupt mask

    POP H                   ; Restore HL
    POP D                   ; Restore DE
    POP B                   ; Restore BC
    POP PSW                 ; Restore A + flags

    EI                      ; Re-enable interrupts
    RET                     ; Return to (possibly new) task
