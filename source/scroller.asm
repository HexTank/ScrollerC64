//----------------------------------------------------------
//
// Initial attempt at an 8-way scroller
//
// Code by Paul Tankard (HexTank)
//
// If any of this code is used in your own production,
// a thanks would be appreciated.
//
// Twitter : @HexTank
// Github  : https://github.com/HexTank/ScrollerC64
//
//----------------------------------------------------------
.filenamespace hextank_scroller
:BasicUpstart2(mainStartup)

//----------------------------------------------------------
//				Variables
//----------------------------------------------------------	
// copy of pointer to map which is clobered.
.var temp_map_ptr = $2
.var temp_map_ptr_h = $3

// signed values for movement along axis
.var x_dir = $10
.var y_dir = $11
.var x_map_min = $12
.var y_map_min = $13
.var x_map_max = $14
.var y_map_max = $15

// pointer to start of map
.var map_ptr = $20
.var map_ptr_h = $21

// 24bit values for map positions, 16 sub pixels.
.var camera_pos_x_s = $22
.var camera_pos_y_s = $23
.var camera_pos_x = $24
.var camera_pos_y = $25
.var camera_pos_x_h = $26
.var camera_pos_y_h = $27

.var map_x_adjust = $2c
// hacky table with pointer offsets for each row, will be store with map data itself.
.var map_y_table = $2d

// general temp area, we don't use the stack
.var ztmp1 = $40
.var ztmp2 = $41
.var ztmp3 = $42

.var last = $43

// map assets
.var mapfile = LoadBinary("scroller.map")
.var chrfile = LoadBinary("scroller.chr")

//----------------------------------------------------------

//----------------------------------------------------------
//				Main Startup Code
//----------------------------------------------------------

mainStartup:
		* = mainStartup "Main Startup"

		sei

		// clear vars
		lda #0
		ldx #last
		sta $0,x
		dex
		cpx #1
		bne * - 5

		// initialise some vars
		lda #$20
		sta x_dir
		lda #0
		sta x_map_min
		lda #20
		sta x_map_max

		lda #$07
		sta y_dir
		lda #1
		sta y_map_min
		lda #8
		sta y_map_max

		lda #1
		sta camera_pos_x
		sta camera_pos_y

		// initialise map pointer and lookup table for map row offsets
		lda #<mapdata
		sta map_ptr
		lda #>mapdata
		sta map_ptr_h

		lda #0
		sta ztmp1
		sta ztmp2
		ldy #0
		sta map_y_table, y
		iny
		sta map_y_table, y
		iny
		ldx #60
!moff:	clc
		lda ztmp1
		adc #40					// hard coded
		sta ztmp1
		sta map_y_table, y
		iny
		lda ztmp2
		adc #0
		sta ztmp2
		sta map_y_table, y
		iny		
		dex
		bne !moff-



		lda #$18
		sta $d018
		jmp	main


		* = $4000
main:
		lda #GREEN
        sta $d020
		
		// Wait for status panel start
		lda $d011
		ldx #(20*8)+44	// rows * pixels + start offset
		cpx $d012
		bcs * - 3
		cmp #$15
		beq !blank+
!nobadline:
		ora #$07
		sta $d011
		nop
		ldx #5
		dex
		bpl * - 1
!blank:		
		// reset scroll registers
		lda #$17
		sta $d011
		lda #$07
		sta $d016
		lda #$f8
		sta $d018


		// move the camera variables
		ldy #0
		jsr move_camera_axis
		ldy #1
		jsr move_camera_axis


		// calculate offset in to map
		clc
		lda #<mapdata
		adc camera_pos_x
		sta map_ptr
		lda #>mapdata
		adc camera_pos_x_h
		sta map_ptr_h

		ldy #0		
		lda camera_pos_y
		asl 
		tay
		clc
		lda map_ptr
		adc map_y_table, y
		sta map_ptr
		iny
		lda map_ptr_h
		adc map_y_table, y
		sta map_ptr_h

		// work out which display list we should use, left or right
		clc
		lda camera_pos_x_s
		and #$80
		rol
		rol
		rol
		tay
		lda chrOpChain+3, y
		sta chrOpChain+1
		lda chrOpChain+4, y
		sta chrOpChain+2
		tya 
		lsr
		sta map_x_adjust	// 0 or 40

		// now self mod the display chain 'adc #2' -> 'lda ($2),y'
        lda #LDA_IZPY
        ldx #INY
		jsr chrOpChain

        lda #WHITE
        sta $d020

        // the main bulk of the map transfer
        ldx #0
        lda camera_pos_y_s
        bpl !skip+
        ldx #40	
!skip:
		lda map_ptr
		sta temp_map_ptr
		lda map_ptr_h
		sta temp_map_ptr_h
		clc		
		ldy #0
		lda (temp_map_ptr), y
		ldy map_x_adjust
		adc #2
		jsr chrCopyChain

		// setup the smooth scroll registers
		clc
		lda camera_pos_x_s
		lsr
		lsr
		lsr
		lsr		
		and #7		
		eor #7
		sta scrx+1
		lda $d016
		and #$f8
		clc
scrx:	adc #0
		sta $d016

		lda camera_pos_y_s
		lsr
		lsr
		lsr
		lsr
		and #7	
		eor #7
		sta scry+1
		lda $d011
		and #$f8
		clc
scry:	adc #0
		sta $d011

		lda #$18
		sta $d018


		// restore the previously set 'lda ($2),y' back to 'adc #2'
 		lda #ADC_IMM
 		ldx #NOP
 		jsr chrOpChain

		jmp main

//----------------------------------------------------------
//
// Functions
//
//----------------------------------------------------------

move_camera_axis:
		clc
		ldx #0
		lda x_dir,y
		bpl * + 3
		dex
		adc camera_pos_x_s,y
		sta camera_pos_x_s,y
		txa
		adc camera_pos_x,y
		sta camera_pos_x,y
		txa
		adc camera_pos_x_h,y
		sta camera_pos_x_h,y

		lda camera_pos_x,y
		cmp x_map_max,y
		bpl !flip+
		cmp x_map_min,y
		bpl !ok+
!flip:	lda #$ff
		eor x_dir,y
		clc
		adc #1
		sta x_dir,y
!ok:	rts


//----------------------------------------------------------
//
// Code generators
//
//----------------------------------------------------------

// Character memory
chrOpChain:
		* = chrOpChain "chrOpChain"
		jmp	chrOpChain
		.word chrOpChain_1
		.word chrOpChain_2

chrOpChain_1:	SelfModOPChain(chrCopyChain, 20, 10, 0,  0, YELLOW)
chrOpChain_2:	SelfModOPChain(chrCopyChain, 19, 10, 7, 10, BLACK)
chrCopyChain:	GenerateBlitCode($0400, ADC_IMM, temp_map_ptr, temp_map_ptr)

/*
// Colour memory
colOpChain:
		* = colOpChain "colOpChain"
		jmp	colOpChain
		.word colOpChain_1
		.word colOpChain_2

colOpChain_1:	SelfModOPChain(colCopyChain, 20, 10,  0, $f, YELLOW)
colOpChain_2:	SelfModOPChain(colCopyChain, 19, 10, 10, $f, BLACK)
colCopyChain:	GenerateBlitCode($db00, AND_IMM, $f)
*/

//----------------------------------------------------------
//
// Macros
//
//----------------------------------------------------------

.macro SelfModOPChain(addr, blks_wide, blks_high, offset1, offset2, dbug_col) {
	ldy #dbug_col
	sty $d020

	// slice 1
	.for(var cx=0; cx<blks_wide; cx++ ) {
		sta addr + 8 + (cx*15) + offset1
	}

	// slice 2
	.for(var cy=0; cy<blks_high; cy++ ) {
		.for(var cx=0; cx<blks_wide; cx++ ) {
			sta addr + 8 + (292+21) + (cy*(409+21)) + (cx*21) + offset2
		}
	}

	rts
}

.macro GenerateBlitCode(addr, op, byte, edgebyte) {
	cpx #0										//	   [2](2)
	clc 										//	   [2](1)
	bne !do_y_fudge+							//	   [3](2)
	jmp !no_y_fudge+							//	   [3](3)
// 7
!do_y_fudge:
	GenerateRowBlitCode(addr, 0, op, edgebyte, 1)
	GenerateNextMapRowCode()
// 7 + 214 + 15	
!no_y_fudge: 
	.for(var cy=0; cy<20; cy+=2 ) {
		GenerateRowBlitCode(addr, cy, op, byte, 2)
		.if(cy!=18) {
			GenerateNextMapRowCode()
		}
	}
	rts
}

// code bytes = 21
.macro GenerateNextMapRowCode() {
	clc										// **** REMOVE WHEN WE HAVE PROPER MAPS ****
	lda temp_map_ptr						//	   [3](2)
	adc #$28								//	   [2](2) - self mod map width low byte
	sta temp_map_ptr						//	   [3](2)
	lda temp_map_ptr_h						//	   [3](2)
	adc #$00								// 	   [2](2) - self mod map width high byte
	sta temp_map_ptr_h						//	   [3](2)
	ldy #0									//	   [2](2)
	lda (temp_map_ptr), y					//	   [5](2)
	adc #2									//	   [2](2)
	ldy map_x_adjust						//	   [2](2)
}

// slice 1 -> code bytes =  292   ((15 * 20) -  8 )
// slice 2 -> code bytes =  409   ((21 * 20) - 11 )
.macro GenerateRowBlitCode(addr, row, op, byte, slice) {
	.for(var cx=0; cx<40; cx+=2 ) {
		.if(slice==1) {
			.byte op, byte						// 0   [5](2) - [5] is to take in to account lda (map_ptr), y which can be in any adc #2 slot.			
			.byte op, byte						// 2   [2](2)
			sta addr+cx							// 4   [5](3)
			.if(cx!=38) {
				.byte op, byte					// 7   [2](2)
				.byte op, byte					// 9   [2](2)
				sta addr+cx+1					// 11  [5](3)
				iny								// 14  [2](1)				
			}
		}
		.if(slice==2) {
			.byte op, byte						// 0   [5](2) - [5] is to take in to account lda (map_ptr), y which can be in any adc #2 slot.
			sta addr+(row*40)+cx,x				// 2   [5](3)
			.byte op, byte						// 5   [2](2)
			sta addr+((row+1)*40)+cx,x			// 7   [5](3)
			.if(cx!=38) {
				.byte op, byte					// 10  [2](2)
				sta addr+(row*40)+cx+1,x		// 12  [5](3)
				.byte op, byte					// 15  [2](2)
				sta addr+((row+1)*40)+cx+1,x	// 17  [5](3)
				iny								// 20  [2](1)
			}
		}
	}
}

//----------------------------------------------------------

			.align $100
mapdata:	* = mapdata "mapData"
			.fill mapfile.getSize(), mapfile.get(i)
			* = $2000
chrdata:	* = chrdata "chrData"
			.fill chrfile.getSize(), chrfile.get(i)