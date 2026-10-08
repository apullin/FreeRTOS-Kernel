/*
 * FreeRTOS port for Intel 8085
 *
 * Context switch design:
 *
 * The 8085 has a flat register set (A, flags, B, C, D, E, H, L) plus SP.
 * On context switch, all registers are pushed onto the task's stack.
 *
 * Stack frame layout (built by PUSH instructions, high address at top):
 *
 *   [pvParameters high] [pvParameters low]   ; Task argument (at SP+2 after RET)
 *   [dummy ret high]    [dummy ret low]      ; Dummy return address
 *   [PC high]           [PC low]             ; Task entry / resume point
 *   [A]                 [Flags]              ; PSW (pushed by PUSH PSW)
 *   [B]                 [C]                  ; BC pair (pushed by PUSH B)
 *   [D]                 [E]                  ; DE pair (pushed by PUSH D)
 *   [H]                 [L]                  ; HL pair (pushed by PUSH H)
 *   [IntMask]           [xx]                 ; 8085 interrupt mask (via RIM/SIM)
 *                         ^--- pxTopOfStack points here
 *
 * The IntMask byte is a prepared SIM value: [0 0 0 0 MSE M7.5 M6.5 M5.5].
 * On context restore, POP PSW loads it into A, then SIM applies it.
 * This gives each task its own RST 5.5/6.5/7.5 mask state.
 *
 * 8085 PUSH pushes high byte first (at SP-1), then low byte (at SP-2).
 * After a PUSH, SP points to the low byte.
 *
 * When building the initial stack frame in C, we decrement the pointer
 * and write bytes from high address to low address, matching the order
 * they would appear after the corresponding PUSH instructions.
 *
 * The calling convention passes arguments on the stack at [SP+2] (after
 * the return address pushed by CALL). When a task starts via RET from
 * the context restore, the stack has: PC already popped, so SP points
 * to the dummy return address, with pvParameters at [SP+2].
 */

#include "FreeRTOS.h"
#include "task.h"

/*-----------------------------------------------------------
 * External references.
 *-----------------------------------------------------------*/

typedef void TCB_t;
extern volatile TCB_t * volatile pxCurrentTCB;

/* Assembly functions in portasm.S */
extern void vPortStartFirstTask( void );

/*-----------------------------------------------------------
 * Critical section nesting counter.
 *
 * Starts non-zero so early code runs with interrupts disabled.
 * xPortStartScheduler sets it to 0 before starting the first task.
 *-----------------------------------------------------------*/
volatile unsigned int uxCriticalNesting = 10;

/*-----------------------------------------------------------
 * Address of an infinite loop for the dummy return address.
 * If a task function returns, it will jump here and halt.
 * This is defined in startup.S as _task_exit_trap.
 *-----------------------------------------------------------*/
extern void _task_exit_trap( void );

/*-----------------------------------------------------------
 * pxPortInitialiseStack
 *
 * Build the initial stack frame for a new task.
 *
 * The i8085 calling convention: arguments passed on stack at
 * [SP+2]. When the context is restored and RET executes, SP
 * advances past PC, leaving the dummy return address at [SP]
 * and pvParameters at [SP+2] -- exactly where the task function
 * expects its argument.
 *-----------------------------------------------------------*/
StackType_t * pxPortInitialiseStack( StackType_t * pxTopOfStack,
                                     TaskFunction_t pxCode,
                                     void * pvParameters )
{
    /* Stack is byte-addressable, grows downward.
     * pxTopOfStack points to the highest usable byte.
     *
     * We build the frame from high to low addresses. */

    /* pvParameters (task argument) - high byte then low byte */
    *pxTopOfStack-- = ( StackType_t ) ( ( ( unsigned int ) pvParameters >> 8 ) & 0xFF );
    *pxTopOfStack-- = ( StackType_t ) ( ( unsigned int ) pvParameters & 0xFF );

    /* Dummy return address (if task returns, go to trap loop) */
    *pxTopOfStack-- = ( StackType_t ) ( ( ( unsigned int ) _task_exit_trap >> 8 ) & 0xFF );
    *pxTopOfStack-- = ( StackType_t ) ( ( unsigned int ) _task_exit_trap & 0xFF );

    /* PC = task entry point (popped by RET during context restore) */
    /* 8085 RET pops low byte first (into PCL), then high byte (into PCH) */
    *pxTopOfStack-- = ( StackType_t ) ( ( ( unsigned int ) pxCode >> 8 ) & 0xFF );
    *pxTopOfStack-- = ( StackType_t ) ( ( unsigned int ) pxCode & 0xFF );

    /* PSW: A register = 0, Flags = 0x02 (bit 1 is always 1 on 8085) */
    /* PUSH PSW pushes A at SP-1, Flags at SP-2 */
    *pxTopOfStack-- = ( StackType_t ) 0x00;   /* A */
    *pxTopOfStack-- = ( StackType_t ) 0x02;   /* Flags (bit 1 = 1) */

    /* BC pair: PUSH B pushes B at SP-1, C at SP-2 */
    *pxTopOfStack-- = ( StackType_t ) 0x00;   /* B */
    *pxTopOfStack-- = ( StackType_t ) 0x00;   /* C */

    /* DE pair: PUSH D pushes D at SP-1, E at SP-2 */
    *pxTopOfStack-- = ( StackType_t ) 0x00;   /* D */
    *pxTopOfStack-- = ( StackType_t ) 0x00;   /* E */

    /* HL pair: PUSH H pushes H at SP-1, L at SP-2 */
    *pxTopOfStack-- = ( StackType_t ) 0x00;   /* H */
    *pxTopOfStack-- = ( StackType_t ) 0x00;   /* L */

    /* 8085 interrupt mask (saved via PUSH PSW after RIM processing).
     * Format: [0 0 0 0 MSE=1 M7.5 M6.5 M5.5]
     * Initial value 0x0D = MSE=1, M7.5=masked, M6.5=unmasked (tick), M5.5=masked.
     * Matches the startup.S SIM configuration. */
    *pxTopOfStack-- = ( StackType_t ) 0x0D;   /* A = SIM byte (interrupt mask) */
    *pxTopOfStack   = ( StackType_t ) 0x00;   /* Flags (don't care, pad for PUSH PSW) */

    return pxTopOfStack;
}

/*-----------------------------------------------------------
 * xPortStartScheduler
 *-----------------------------------------------------------*/
BaseType_t xPortStartScheduler( void )
{
    /* Reset critical nesting for the first task */
    uxCriticalNesting = 0;

    /* Start the first task - never returns */
    vPortStartFirstTask();

    /* Should not reach here */
    return pdTRUE;
}

/*-----------------------------------------------------------
 * vPortEndScheduler
 *-----------------------------------------------------------*/
void vPortEndScheduler( void )
{
    /* Disable interrupts and halt */
    portDISABLE_INTERRUPTS();
    __asm__ volatile ( "hlt" );
}

/*-----------------------------------------------------------
 * vPortEnterCritical / vPortExitCritical
 *
 * Nesting-safe critical sections using DI/EI.
 *-----------------------------------------------------------*/
void vPortEnterCritical( void )
{
    portDISABLE_INTERRUPTS();
    uxCriticalNesting++;
}

void vPortExitCritical( void )
{
    if( uxCriticalNesting > 0 )
    {
        uxCriticalNesting--;

        if( uxCriticalNesting == 0 )
        {
            portENABLE_INTERRUPTS();
        }
    }
}
