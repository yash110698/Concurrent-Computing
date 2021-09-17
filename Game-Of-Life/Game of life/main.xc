// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)
#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 256                  //image height
#define  IMWD 256                  //image width
#define     W  8                  //no of workers
#define  MOD(p)  ((p+IMHT)%IMHT)  //modular value of pixel position
#define  MODWORK(p)  ((p+W)%W)    //modular value of workers
typedef unsigned char uchar;      //using uchar as shorthand

on tile[0]: port p_scl = XS1_PORT_1E;       //interface ports to orientation
on tile[0]: port p_sda = XS1_PORT_1F;
on tile[0]: in port buttons = XS1_PORT_4E;  //port to access xCore-200 buttons
on tile[0]: out port leds = XS1_PORT_4F;    //port to access xCore-200 LEDs
//1st bit...separate green LED   -processing (alternate every round)
//2nd bit...blue LED   -SW2      -exporting
//3rd bit...green LED  -SW1      -reading
//4th bit...red LED    -tilt     -paused

#define FXOS8700EQ_I2C_ADDR 0x1E            //register addresses for orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6
/////////////////////////////////////////////////////////////////////////////////////////
//DISPLAYS an LED pattern
//READ BUTTONS and send button pattern to Distributor
void buttonListener(in port b, chanend toDist) {
    int r, flag = 0;
    while (1) {
        b when pinseq(15)  :> r;    // check that no button is pressed
        b when pinsneq(15) :> r;    // check if some buttons are pressed

        if(flag)    toDist <: (r==13)?1:0 ;

        if (r==14 && flag==0){     // if either button is pressed
            toDist <: r;// send button pattern to userAnt
            flag = 1;
        }

    }
}
/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(char infname[], chanend c_out)
{
    int res;
    uchar line[ IMWD ];
    //printf( "DataInStream: Start...\n" );

    //Open PGM file
    res = _openinpgm( infname, IMWD, IMHT );
    if( res )
    {
        printf( "DataInStream: Error openening %s\n.", infname );
        return;
    }

    //Read image line-by-line and send byte by byte to channel c_out
    for( int y = 0; y < IMHT; y++ )
    {
        _readinline( line, IMWD );
        for( int x = 0; x < IMWD; x++ )
        {
            c_out <: line[ x ];
            printf( "-%4.1d ", line[ x ] ); //show image values
        }
        printf( "\n" );
    }

    //Close PGM image file
    _closeinpgm();
    //printf( "DataInStream: Done...\n" );
    return;
}
/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of worker
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_in, chanend c_out, chanend fromOrien, chanend c_worker[n], unsigned int n, chanend fromButtons, out port LEDs)
{

    int tilt, button, round = 1, alive = 0,cell = 0,waste=0;
    uchar pix,pix2;


    printf( "-------------GAME OF LIFE-------------\n Image size = %dx%d\n\n 1.Press SW1 Button to Start => \n", IMHT, IMWD );
    fromButtons :> button;
    printf( "\nReading Image...\n\n" );

    LEDs <: (1 << 0 | 1 << 2);
    for( int x = 0; x < IMHT; x++ )
    {                                                               //go through all lines
        for( int y = 0; y < IMWD; y++ )
        {                                                           //go through each pixel per line
            c_in :> pix;                                            //read the pixel value
            c_worker[x / (IMHT/W)] <: pix;                          //send pixel to workers
        }
    }

    printf( "\nOne processing round completed...\n2.Press SW2 Button to export Image as PGM file.\n\n" );
    LEDs <: (1 << 0);


    unsigned long long int startTime = 0,endTime=0 ,currentTime = 0;
    timer gametimer;
    gametimer :> startTime;

    while(1)
    {
        printf("\nRound : %d--------------------------------------------------------------\n",round);

        alive = 0;
        LEDs <: (round % 2)  ?  0  : (1 << 0) ;

        select{
            case fromButtons :> button : button += 0 ;              //printf("Mr Buttons : %d",buttons);
                break;
            default : button = 0;
                break;
        }

        /////////////////////////////////////////////////////////////////////////////////
        //Workers communicating synchronously to recieve modified neighbours
        for(int i=0;i<W;i++)
        c_worker[i] <: button;
        //1.sending flag to workers to start communication
        //2.also sends the signal whether to export image or not
        for( int i = 0; i < W; i+=2)
        {
            //PRE STAGE
            for( int j = 0; j < IMWD; j++)
            {
                c_worker[MODWORK(i-1)] :> pix;
                c_worker[i] :> pix2;
                c_worker[MODWORK(i-1)] <: pix2;
                c_worker[i] <: pix;
            }
        }
        for( int i = 0; i < W; i+=2)
        {
            //POST STAGE
            for( int j = 0; j < IMWD; j++)
            {
                c_worker[MODWORK(i+1)] :> pix;
                c_worker[i] :> pix2;
                c_worker[MODWORK(i+1)] <: pix2;
                c_worker[i] <: pix;
            }
        }
        for(int i=0;i<W;i++)
            c_worker[i] :> waste;


        /////////////////////////////////////////////////////////////////////////////////

        if(button){
            LEDs <: (round % 2) ? (1 << 1) : (1 << 0 | 1 << 1) ;
            c_out <: button;
            printf("\n----------------EXPORTING IMAGE----------------\n");
            for( int x = 0; x < IMHT; x++ )
            {
                for( int y = 0; y < IMWD; y++ )
                {
                    c_worker[x / (IMHT/W)] :> pix;                      //recieve pixel from workers
                    c_out <: pix;                                       //send to export the pixels as a PGM file
                    printf("=%4.1d ",pix);                              //printing pixels during exporting

                }printf("\n");
            }printf("\n");
        }
        LEDs <: (round % 2) ? 0 : (1 << 0) ;

        for(int i=0;i<W;i++)
        {
            c_worker[i] :> cell;                                        // recieving no.of alive cells from worker
            alive += cell;
        }
        /////////////////////////////////////////////////////////////////////////////////
        gametimer :> endTime;
        currentTime = endTime - startTime;
        currentTime /= 100000;
        if(round == 2 || round == 100)
        {
            printf("\n Time elapsed after round %d : %d\n",round,currentTime);
        }

        fromOrien :> tilt;                                              // recieving Tilting input
        if(tilt >= 30){
            printf("\nProcessing stopped due to tilting : %d\n",tilt);
            printf("Status Report :-\n1. No. of rounds elapsed : %d\n2.Current No. of Alive Cells : %d\n3.Processing Time Elapsed after Image read-in : %d",round,alive,currentTime);
            printf("\n");
            LEDs <: (round % 2) ? (1 << 3) : (1 << 0 | 1 << 3) ;
        }
        while(tilt >= 30){   fromOrien :> tilt;}
        LEDs <: (round % 2) ? 0 : (1 << 0) ;








        round++;button = 0;
    }


}
/////////////////////////////////////////////////////////////////////////////////////////
// Game of Life worker Function : checks the 4 conditions
void worker(chanend fromDist, int Wnum)
{

    int flag = 0, round = 0, pre, post, coeff; int alive = 0;

    pre = (Wnum % 2 == 0) ? 1 : (IMHT/W);
    post = (Wnum % 2 == 0) ? (IMHT/W) : 1;
    coeff = (Wnum % 2 == 0) ? 1 : -1 ;

    uchar pix, arr1[(IMHT/W)+2][IMWD], arr2[(IMHT/W)+2][IMWD];

    for( int x = 1; x <= (IMHT/W); x++ )
    for( int y = 0; y < IMWD; y++ )
        fromDist :> arr1[x][y];                                         //read the pixel value & store values in array

    while(1)
    {
        alive = 0;
        fromDist :> flag;                                               //recieve a signal from Distributor to start exchanging neighbour pixels

        //PRE STAGE
        for(int i = 0; i < IMWD; i++)
        {
            fromDist <: arr1[pre][i];                                   //send
            fromDist :> arr1[pre-coeff][i];                             //recieve

        }

        //POST STAGE
        for(int i = 0; i < IMWD; i++)
        {
            fromDist <: arr1[post][i];
            fromDist :> arr1[post+coeff][i];
        }

        fromDist <: flag;

        int count = 0;
        for( int x = 1; x <= (IMHT/W); x++ )
        {
            for( int y = 0; y < IMWD; y++ )
            {
                /////////////////////////////////////////////////////////////////////////////////
                count = 0;
                for(int j = x-1; j <= x+1 ; j++)
                {
                    for(int  k = y-1; k <=y+1; k++)
                    {

                        if(arr1[j][MOD(k)] == 255)
                        {
                            if(j == x && k == y){    continue;}
                            count++;
                        }

                    }
                }
                pix=arr1[x][y];
                if(count < 2)   pix = 0;
                if(count == 2  && arr1[x][y] == 255)  pix = 255;
                if(count == 3)  pix = 255;
                if(count > 3)   pix = 0;

                if(pix == 255)  alive++;
                arr2[x][y] = pix ;                                              //storing new pixels in array2

                if(flag)    fromDist <: pix;                                    //exporting pixels to Dist if flag is 1
                /////////////////////////////////////////////////////////////////////////////////
            }
        }

        fromDist <: alive;                                                      //send a signal to Distributor after the end of processing

        for( int x = 1; x <= (IMHT/W); x++ )
        for( int y = 0; y < IMWD; y++ ){
            arr1[x][y] = arr2[x][y] ;                                           //storing the new pixel image back in array1 after completing the processing
        }
        round++;
    }

}
/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in)
{
    int res, button;
    uchar line[ IMWD ];

    while(1){
        c_in :> button;
        //if(!button) continue;
        //Open PGM file
        //printf( "DataOutStream: Start...\n" );
        res = _openoutpgm( outfname, IMWD, IMHT );
        if( res ) {
            printf( "DataOutStream: Error opening %s\n.", outfname );
            return;
        }

        //Compile each line of the image and write the image line-by-line
        for( int y = 0; y < IMHT; y++ ) {
            for( int x = 0; x < IMWD; x++ ) {
              c_in :> line[ x ];
            }
            _writeoutline( line, IMWD );
            //printf( "\nDataOutStream: Line written...\n" );
        }

        //Close the PGM image
        _closeoutpgm();
        printf( "\nDataOutStream: Done...\n" );
        //return;
    }
}
/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read orientation, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void orientation( client interface i2c_master_if i2c, chanend toDist) {

    i2c_regop_res_t result;
    char status_data = 0;
    // Configure FXOS8700EQ
    result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
    if (result != I2C_REGOP_SUCCESS) {
        printf("I2C write reg failed\n");
    }
    // Enable FXOS8700EQ
    result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
    if (result != I2C_REGOP_SUCCESS) {
        printf("I2C write reg failed\n");
    }
    while (1) {//Probe the orientation x-axis forever

        do {//check until new orientation data is available
            status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
        } while (!status_data & 0x08);
        int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);//get new x-axis tilt value
        toDist <: x;//send signal to distributor after tilt
    }
}
/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
//
////////////////////////////////////////////////////////////////////////////////////////

char infname[] = "test.pgm";     //put your input image path here
char outfname[] = "testout.pgm"; //put your output image path here
int main(void) {

    i2c_master_if i2c[1];               //interface to orientation
    chan c_inIO, c_outIO, c_control, ButtonsToDist;    //extend your channel definitions here
    chan DistToWorker[W];

    par {
        on tile[0]: i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
        on tile[0]: buttonListener(buttons, ButtonsToDist);
        on tile[0]: orientation(i2c[0],c_control);        //client thread reading orientation data
        on tile[0]: DataInStream(infname, c_inIO);          //thread to read in a PGM image
        on tile[0]: DataOutStream(outfname, c_outIO);       //thread to write out a PGM image
        on tile[0]: distributor(c_inIO, c_outIO, c_control, DistToWorker , W, ButtonsToDist, leds);//thread to coordinate work on image
        par(int i = 0 ; i < W ; i++)
        on tile[1]: worker(DistToWorker[i],i);

    }
    return 0;
}
