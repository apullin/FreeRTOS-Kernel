/*
 * FreeRTOS port for Intel 8085
 *
 * The 8085 is an 8-bit CPU with a 16-bit address space.
 * Registers: A (accumulator), B, C, D, E, H, L (8-bit), SP (16-bit).
 * Register pairs: BC, DE, HL (16-bit).
 * Flags register (F): S, Z, AC, P, CY.
 *
 * Interrupts: DI/EI instructions disable/enable all maskable interrupts.
 * RST 5.5, RST 6.5, RST 7.5 are maskable via the SIM instruction.
 * TRAP is non-maskable.
 *
 * Stack grows downward (PUSH decrements SP by 2).
 * PUSH PSW pushes A at SP-1, flags at SP-2.
 * PUSH rp pushes high byte at SP-1, low byte at SP-2.
 */

#ifndef PORTMACRO_H
#define PORTMACRO_H

#ifdef __cplusplus
    extern "C" {
#endif

/*-----------------------------------------------------------
 * Port specific definitions.
 *-----------------------------------------------------------*/

/* Type definitions. */
#define portCHAR          char
#define portFLOAT         float
#define portDOUBLE        double
#define portLONG          long
#define portSHORT         int
#define portSTACK_TYPE    unsigned char
#define portBASE_TYPE     int
#define portPOINTER_SIZE_TYPE unsigned int

typedef unsigned char    StackType_t;
typedef int              BaseType_t;
typedef unsigned int     UBaseType_t;

#if ( configTICK_TYPE_WIDTH_IN_BITS == TICK_TYPE_WIDTH_16_BITS )
    typedef unsigned int     TickType_t;
    #define portMAX_DELAY    ( TickType_t ) 0xFFFF
#elif ( configTICK_TYPE_WIDTH_IN_BITS == TICK_TYPE_WIDTH_32_BITS )
    typedef unsigned long    TickType_t;
    #define portMAX_DELAY    ( TickType_t ) ( 0xFFFFFFFFUL )
#else
    #error configTICK_TYPE_WIDTH_IN_BITS set to unsupported tick type width.
#endif

/*-----------------------------------------------------------
 * Interrupt control macros.
 *
 * 8085 DI disables all maskable interrupts.
 * 8085 EI enables all maskable interrupts.
 *-----------------------------------------------------------*/
#define portDISABLE_INTERRUPTS()    __asm__ volatile ( "di" )
#define portENABLE_INTERRUPTS()     __asm__ volatile ( "ei" )

/*-----------------------------------------------------------
 * Critical section control.
 *
 * Uses a nesting counter with DI/EI.
 *-----------------------------------------------------------*/
extern void vPortEnterCritical( void );
extern void vPortExitCritical( void );

#define portENTER_CRITICAL()    vPortEnterCritical()
#define portEXIT_CRITICAL()     vPortExitCritical()

/*-----------------------------------------------------------
 * Task utilities.
 *-----------------------------------------------------------*/
extern void vPortYield( void );
#define portYIELD()    vPortYield()
#define portNOP()      __asm__ volatile ( "nop" )

/*-----------------------------------------------------------
 * Hardware specifics.
 *-----------------------------------------------------------*/
#define portBYTE_ALIGNMENT    1
#define portSTACK_GROWTH      ( -1 )
#define portTICK_PERIOD_MS    ( ( TickType_t ) 1000 / configTICK_RATE_HZ )

/*-----------------------------------------------------------
 * Task function macros.
 *-----------------------------------------------------------*/
#define portTASK_FUNCTION_PROTO( vFunction, pvParameters )    void vFunction( void * pvParameters )
#define portTASK_FUNCTION( vFunction, pvParameters )          void vFunction( void * pvParameters )

#ifdef __cplusplus
    }
#endif

#endif /* PORTMACRO_H */
