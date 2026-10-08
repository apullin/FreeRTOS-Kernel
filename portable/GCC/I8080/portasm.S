; ---------------------------------------------------------------------------
; FreeRTOS Intel 8080 port - context switch assembly
;
; Saved registers (8 bytes), followed by the 2-byte return PC:
;   [L] [H] [E] [D] [C] [B] [Flags] [A] [PC_lo] [PC_hi] ...
;   ^--- pxTopOfStack (SP) points here
;
; Save order: PUSH PSW, PUSH B, PUSH D, PUSH H (high byte first).
; Restore order: POP H, POP D, POP B, POP PSW, then RET.
;
; pxCurrentTCB->pxTopOfStack is the first field of the TCB, a 16-bit
; pointer stored little-endian (low byte at lower address).
;
; This file uses only 8080-compatible instructions (no RIM, SIM, or
; 8085-specific interrupt features).
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

    POP H                   ; Restore HL
    POP D                   ; Restore DE
    POP B                   ; Restore BC
    POP PSW                 ; Restore A + flags

    EI                      ; Re-enable interrupts
    RET                     ; Resume new task

; ---------------------------------------------------------------------------
; vPortTickISR
;
; Timer interrupt handler.  On the 8080, the external interrupt
; controller (e.g. 8259 PIC + 8253 timer) places an RST instruction
; on the data bus during the INTA cycle.  We use RST 7 (vector 0x0038).
;
; The 8080 hardware saves the PC on the stack when servicing an
; interrupt and automatically disables interrupts (clears INTE).
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

    POP H                   ; Restore HL
    POP D                   ; Restore DE
    POP B                   ; Restore BC
    POP PSW                 ; Restore A + flags

    EI                      ; Re-enable interrupts
    RET                     ; Return to (possibly new) task
