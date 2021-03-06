/* Copyright (C) 2017 Daniel Page <csdsp@bristol.ac.uk>
 *
 * Use of this source code is restricted per the CC BY-NC-ND license, a copy of
 * which can be found via http://creativecommons.org (and should be included as
 * LICENSE.txt within the associated archive or repository).
 */

#include "hilevel.h"
extern void     main_P3();
extern void     main_P4();
extern void     main_P5();
extern void     main_console();
extern uint32_t tos_usr;
#define Pnum 50
//#define dage(pid_t pid) ( pcb[pid].age + pcb[pid].priority )


pcb_t  pcb[ Pnum ];
pcb_t* current = NULL;
pid_t nextPID= 0;

pcb_t* emptyPCB(){
  for(int i=0; i<Pnum; i++){
    if(pcb[i].status == STATUS_TERMINATED){  return &pcb[i];}
  }
  return NULL;
}
pid_t dage(pid_t pid){
  return (pcb[pid].age + pcb[pid].priority);
}

//Given a PID, return the PCB of it.
pcb_t* getMemoryByPID(pid_t pid){
  for(int i=0; i<Pnum; i++){
    if(pcb[i].pid == pid)
      return &pcb[i];
  }
  return NULL;
}

void print(char* x)
{
  for(int i=0;i<sizeof(x);i++){
    PL011_putc( UART0, *x++, true );
  }
}

//********************************************************************************************************

void dispatch( ctx_t* ctx, pcb_t* prev, pcb_t* next ) {
  char prev_pid = '?', next_pid = '?';

  if( NULL != prev ) {
    memcpy( &(prev->ctx), ctx, sizeof( ctx_t ) ); // preserve execution context of P_{prev}
    prev_pid = '0' + prev->pid;
  }
  if( NULL != next ) {
    memcpy( ctx, &(next->ctx), sizeof( ctx_t ) ); // restore  execution context of P_{next}
    next_pid = '0' + next->pid;
  }

  PL011_putc( UART0,  '\n',           true );
  if(next_pid == '0'){
    //PL011_putc( UART0,  '\n',           true );
    /*PL011_putc( UART0,  'c',           true );
    PL011_putc( UART0,  'o',           true );
    PL011_putc( UART0,  'n',           true );
    PL011_putc( UART0,  's',           true );
    PL011_putc( UART0,  'o',           true );
    PL011_putc( UART0,  'l',           true );
    PL011_putc( UART0,  'e',           true );
    PL011_putc( UART0,  ' ',           true );*/
  }

  current = next;                             // update   executing index   to P_{next}

  return;
}

//********************************************************************************************************
//Priority based scheduler
void schedule( ctx_t* ctx ) {

  int age_max= -1, pid_max= 0;
  for(int i=0; i<Pnum; i++){
    pcb[i].age = dage(i);

    if(pcb[i].age > age_max && pcb[i].status!=STATUS_TERMINATED){
      age_max = pcb[i].age;
      pid_max = i;
    }

  }

  for(int i=0; i<Pnum; i++){
    if(pcb[i].status == STATUS_CREATED)
      pcb[i].age++;
  }

  current->status = STATUS_CREATED;
  pcb[pid_max].status = STATUS_EXECUTING;
  pcb[pid_max].age = 0;
  dispatch( ctx, current, &pcb[pid_max]);

  //pcb[current->pid].pid != current->pid

  return;
}

//********************************************************************************************************

void hilevel_handler_rst( ctx_t* ctx ) {
  PL011_putc( UART0, 'r', true );
  TIMER0->Timer1Load  = 0x000B0000; // select period = 2^20 ticks ~= 1 sec
  TIMER0->Timer1Ctrl  = 0x00000002; // select 32-bit   timer
  TIMER0->Timer1Ctrl |= 0x00000040; // select periodic timer
  TIMER0->Timer1Ctrl |= 0x00000020; // enable          timer interrupt
  TIMER0->Timer1Ctrl |= 0x00000080; // enable          timer

  GICC0->PMR          = 0x000000F0; // unmask all            interrupts
  GICD0->ISENABLER1  |= 0x00000010; // enable timer          interrupt
  GICC0->CTLR         = 0x00000001; // enable GIC interface
  GICD0->CTLR         = 0x00000001; // enable GIC distributor

  int_enable_irq();


  memset( &pcb[ 0 ], 0, sizeof( pcb_t ) );     // initialise 0-th PCB = P_1
  pcb[ 0 ].pid      = 0;
  pcb[ 0 ].status   = STATUS_CREATED;
  pcb[ 0 ].ctx.cpsr = 0x50; //CPSR=0x50 means the processor is switched into USR mode (IRQ enabled)
  pcb[ 0 ].ctx.pc   = ( uint32_t )( &main_console );
  pcb[ 0 ].ctx.sp   = ( uint32_t )( &tos_usr );
  pcb[ 0 ].stack    = ( uint32_t )( &tos_usr );
  pcb[ 0 ].age = 0;
  pcb[ 0 ].priority = 0;

  for(int i=1; i<Pnum; i++){
    pcb[i].status = STATUS_TERMINATED;
  }
  /*for(int i=1; i< Pnum; i++){
    memset( &pcb[ i ], 0, sizeof( pcb_t ) );     // initialise 0-th PCB = P_1
    pcb[ i ].pid      = i;
    pcb[ i ].status   = STATUS_CREATED;
    pcb[ i ].ctx.cpsr = 0x50; //CPSR=0x50 means the processor is switched into USR mode (IRQ enabled)
    pcb[ i ].ctx.sp   = ( uint32_t )( &tos_usr -  (0x00001000 *i));
    pcb[ i ].age = 0;
    if(i==0)
      pcb[ i ].ctx.pc   = ( uint32_t )( &main_P3 );
    else if(i==1)
      pcb[ 1 ].ctx.pc   = ( uint32_t )( &main_P4 );
    else
      pcb[ 2 ].ctx.pc   = ( uint32_t )( &main_P5 );
  }
  pcb[0].priority = 3;
  pcb[1].priority = 5;
  pcb[2].priority = 1;
  for(int i=0; i< Pnum; i++){ pcb[i].age += pcb[i].priority;}*/

  schedule(ctx);

  return;
}

//********************************************************************************************************
void hilevel_handler_irq( ctx_t* ctx ) {
  // Step 2: read  the interrupt identifier so we know the source.

  uint32_t id = GICC0->IAR;

  // Step 4: handle the interrupt, then clear (or reset) the source.

  if( id == GIC_SOURCE_TIMER0 ) {
    schedule(ctx);
    TIMER0->Timer1IntClr = 0x01;
  }

  // Step 5: write the interrupt identifier to signal we're done.

  GICC0->EOIR = id;

  return;
}
//********************************************************************************************************
void hilevel_handler_svc( ctx_t* ctx, uint32_t id ) {

  switch( id ) {
    /*case 0x00 : {//yield()
      break;
    }*/

    case 0x01 : {//write( fd, x, n )
      int   fd = ( int   )( ctx->gpr[ 0 ] );  // fd is  [STDIN_FILENO] which is = ( 0 )
      char*  x = ( char* )( ctx->gpr[ 1 ] );  //x is "P1" or "P2"
      int    n = ( int   )( ctx->gpr[ 2 ] );  // n is the length of "P1" or "P2"

      for( int i = 0; i < n; i++ ) {
        PL011_putc( UART0, *x++, true );
      }

      ctx->gpr[0]=n;

      break;
    }
    /*case 0x02 : {//read( fd, x, n )
      break;
    }*/

    case 0x03 : { // 0x03 => fork( )
      pid_t Id = ++nextPID;
      uint32_t offset;
      pcb_t* child = emptyPCB();
      if(Id != -1 && child != NULL){
        memset( child, 0, sizeof( pcb_t ) );
        memcpy( child, current, sizeof(pcb_t));
        memcpy( &(child->ctx), ctx, sizeof( ctx_t ) ); //memcpy(destination,context,size)

        offset                 = ( current->stack ) - ( ctx->sp ) ;
        child->stack     = &tos_usr - ( Id * 0x00001000 ); //finds the new top of the stack for Id
        child->ctx.sp    = child->stack - offset;

        memcpy( (void*)(child->stack - 0x1000), (void*)(current->stack - 0x1000), 0x1000);

        child->pid       = Id;  //The pid of the new process will be the Id
        child->status = STATUS_CREATED;
        child->priority  = current->priority; //Same priority as the parent
        child->age       = 0;  //Set the child's age to 0;

        ctx->gpr[ 0 ] = Id; //Returns the child's id to the parent
        child->ctx.gpr[ 0 ] = 0;  //fork returns zero to child's gpr[0] (output).

    }
      else {
        print( "Fork failed \n");
        ctx->gpr[ 0 ] = -1;
      }

      break;
    }

    case 0x04 : { // 0x04 => exit( int x )
      int    x  =  ( int  )( ctx->gpr[ 0 ] );
      current->status = STATUS_TERMINATED;
      current->age       = 0;
      current->priority  = 0;
      schedule(ctx);
      break;
    }

    case 0x05 : { // 0x05 =>  exec( const void* x )
      void*  x   = ( void*    )( ctx->gpr[ 0 ] );
      ctx->pc    = ( uint32_t )( ctx->gpr[0] ); //The program counter must be updated to the address x.
      ctx->sp    = current->stack; //we don't want to use the stuff in the sp so we set the sp to the stack
      ctx->cpsr  = 0x50;

      break;
    }

    case 0x06 : { //0x06 => int kill( int pid, int x )
      int pid    = ( int )( ctx->gpr[ 0 ] );
      int x      = ( int )( ctx->gpr[ 1 ] );
      pcb_t* killed =getMemoryByPID(pid);
      killed->status = STATUS_TERMINATED;
      killed->age = 0;
      killed->priority = 0;
      killed->ctx.gpr[ 0 ] = x;
      //schedule( ctx ); //TODO: if i remove this will the timer change the process to the next one
      break;
    }

    case 0x07 : {//nice( pid, x)


      break;
    }

    default   : //unknown/unsupported
    {
      break;
    }
  }

  return;
}
