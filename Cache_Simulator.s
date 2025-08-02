.align 4

.data
cache_tags:       .space 32       @ 4 sets × 2 ways × 4 bytes
cache_valid:      .space 32
cache_counter:    .space 32
cache_fifo_ptr:   .space 16       @ 4 sets × 4 bytes
cache_lru_state:  .space 16   @ 4 sets * 4 bytes = 16 bytes
cache_mru_state:  .space 16
cache_lfu_count: .space 8 * 8     @ 8 sets × 2 ways × 4 bytes = 64 bytes
cache_mfu_count: .space 8 * 8     @ 8 sets × 2 ways × 4 bytes = 64 bytes
rand_seed: .word 0xA3C59AC7 

replacement_type: .word 4         @ 0 = FIFO, 1 = LRU, 2 = MRU, 3 = LFU, 4 = MFU, 5 = random


input_addrs:      .word 5, 5, 1, 13, 5
input_length:     .word 5

hits:             .word 0
misses:           .word 0

.text
.global _start
_start:
    LDR r4, =input_addrs
    LDR r5, =input_length
    LDR r5, [r5]           @ r5 = length
    MOV r6, #0             @ i = 0

loop:
    CMP r6, r5
    BEQ end_simulation

    LSL r7, r6, #2         @ word offset = i * 4
    LDR r0, [r4, r7]       @ r0 = input_addrs[i]
    BL access_cache

    ADD r6, r6, #1
    B loop

end_simulation:
    @ r5 = number of total accesses (input_length)
    MOV r10, r5              @ r10 = total_accesses

    @ Load number of hits into r11
    LDR r2, =hits
    LDR r2, [r2]             @ r2 = hits
    MOV r11, r2              @ r11 = copy of hits

    @ Load number of misses into r12
    LDR r3, =misses
    LDR r3, [r3]             @ r3 = misses
    MOV r12, r3              @ r12 = copy of misses

    @ Calculate hit_rate_x10 = (1000 * hits) / total_accesses  → for one decimal point
    MOV r0, r11              @ r0 = hits
    MOV r1, #1000
    MUL r0, r0, r1           @ r0 = hits * 1000

    MOV r1, r10              @ r1 = total_accesses
    BL udiv_soft             @ call software division
    MOV r9, r0               @ r9 = hit_rate_x10 (e.g., 125 means 12.5%)

    @ Extract integer and fractional part
    MOV r0, r9               @ r0 = hit_rate_x10
    MOV r1, #10
    BL udiv_soft             @ r0 = integer part (e.g., 12), remainder in r9 % 10

    MOV r8, r0               @ r8 = integer part (before decimal)
    MUL r3, r8, r1           @ r3 = integer_part * 10
    SUB r7, r9, r3           @ r7 = fractional part (after decimal)

    @ Final values:
    @ r10 = total accesses
    @ r11 = hits
    @ r12 = misses
    @ r8  = hit_rate integer part
    @ r7  = hit_rate fractional part

    @ (You can use r8 and r7 to print "Hit rate = 12.5%" as "r8.r7%")

    @ Infinite loop to end simulation
end_loop:
    B end_loop


@ unsigned divide: r0 / r1 -> result in r0
@ r0 = numerator, r1 = denominator
udiv_soft:
    MOV r2, #0          @ r2 = result
    CMP r1, #0
    BEQ div_by_zero     @ handle divide by zero if needed

div_loop:
    CMP r0, r1
    BLT div_done
    SUB r0, r0, r1
    ADD r2, r2, #1
    B div_loop

div_done:
    MOV r0, r2          @ result in r0
    BX lr

div_by_zero:
    MOV r0, #0
    BX lr

@ ----------------------------------------------
access_cache:
    PUSH {r1-r9, lr}

    MOV r1, r0
    AND r2, r1, #3         @ set_index = address % 4
    MOV r3, r1             @ tag = here assumed address

    MOV r4, r2
    LSL r4, r4, #3         @ offset = set_index * 8 (2 ways * 4 bytes)

    LDR r7, =cache_tags
    LDR r8, =cache_valid
    ADD r7, r7, r4
    ADD r8, r8, r4

    LDR r5, [r7]           @ tag in way 0
    LDR r6, [r8]           @ valid bit in way 0
    CMP r6, #1
    BEQ check_tag0

check_way1:
    LDR r5, [r7, #4]
    LDR r6, [r8, #4]
    CMP r6, #1
    BEQ check_tag1
    B is_miss

check_tag0:
    CMP r5, r3
    BEQ is_hit
    B check_way1

check_tag1:
    CMP r5, r3
    BEQ is_hit
    B is_miss

is_miss:
    BL handle_replacement
    LDR r1, =misses
    LDR r2, [r1]
    ADD r2, r2, #1
    STR r2, [r1]
    POP {r1-r9, pc}

@ =============================
@ Handle cache hit
@ =============================
is_hit:
    LDR r1, =hits           
    LDR r2, [r1]
    ADD r2, r2, #1
    STR r2, [r1]             

    LDR r0, =replacement_type
    LDR r0, [r0]

    CMP r0, #1                @ LRU
    BEQ update_lru_policy

    CMP r0, #2                @ MRU
    BEQ update_mru_policy

    CMP r0, #3                @ LFU
    BEQ update_lfu_policy

    CMP r0, #4                @ MFU
    BEQ update_mfu_policy

    B skip_policy_update      
@ -----------------------------
update_lru_policy:
    BL update_lru_state
    B skip_policy_update

update_mru_policy:
    BL update_mru_state
    B skip_policy_update

update_lfu_policy:
    BL update_lfu_state
    B skip_policy_update

update_mfu_policy:
    BL update_mfu_state
    B skip_policy_update

@ -----------------------------
skip_policy_update:
    POP {r1-r9, pc}


@ ----------------------------------------------
handle_replacement:
    PUSH {r0-r6, lr}

    LDR r1, =cache_valid
    ADD r1, r1, r4

    LDR r2, [r1]           @ valid[way0]
    CMP r2, #0
    BEQ use_way0

    LDR r2, [r1, #4]       @ valid[way1]
    CMP r2, #0
    BEQ use_way1

    LDR r0, =replacement_type
    LDR r0, [r0]
	
    CMP r0, #0
    BEQ do_fifo

	CMP r0, #1
	BEQ do_lru
	
	CMP r0, #2
	BEQ do_mru
	
	CMP r0, #3
	BEQ do_lfu

	CMP r0, #4
	BEQ do_mfu
	
	CMP r0, #5
	BEQ do_random
	
    B do_fifo              @ fallback

@ --------------------------------------------
do_fifo:
    BL replace_fifo
    B end_replacement

@ --------------------------------------------
do_lru:
    BL replace_lru
    B end_replacement
	
@ --------------------------------------------
do_mru:
    BL replace_mru
    B end_replacement

@ --------------------------------------------
do_lfu:
    BL replace_lfu
    B end_replacement
@ --------------------------------------------
do_mfu:
    BL replace_mfu
    B end_replacement
	
@ --------------------------------------------
do_random:
    BL replace_random
    B end_replacement	
	
use_way0:

    LDR r5, =cache_tags
    ADD r5, r5, r4
    STR r3, [r5]

    LDR r6, =cache_valid
    ADD r6, r6, r4
    MOV r0, #1
    STR r0, [r6]

    LDR r7, =replacement_type
    LDR r7, [r7]
    CMP r7, #0
    BEQ update_fifo_way0
    CMP r7, #1
    BEQ update_lru_way0
    CMP r7, #2
    BEQ update_mru_way0
    CMP r7, #3
    BEQ update_lfu_way0
	CMP r7, #4
    BEQ update_mfu_way0    

    B end_replacement

update_fifo_way0:
    LDR r7, =cache_fifo_ptr
    LSR r8, r4, #3
    LSL r8, r8, #2
    ADD r7, r7, r8
    LDR r9, [r7]
    EOR r9, r9, #1
    STR r9, [r7]
    B end_replacement

update_lru_way0:
    LDR r7, =cache_lru_state
    LSR r8, r4, #3
    LSL r8, r8, #2
    ADD r7, r7, r8
    MOV r9, #0
    STR r9, [r7]
    B end_replacement

update_mru_way0:
    LDR r7, =cache_mru_state
    LSR r8, r4, #3
    LSL r8, r8, #2
    ADD r7, r7, r8
    MOV r9, #0
    STR r9, [r7]
    B end_replacement

update_lfu_way0:
    LDR r7, =cache_lfu_count
    LSR r8, r4, #3
    LSL r8, r8, #3          @ offset = set_index * 8 (2 words per set)
    ADD r7, r7, r8
    MOV r9, #1              @ initialize count0
    STR r9, [r7]
    B end_replacement

update_mfu_way0:
    LDR r7, =cache_mfu_count
    LSR r8, r4, #3
    LSL r8, r8, #3           @ offset = set_index * 8
    ADD r7, r7, r8
    MOV r9, #1                @ initialize count0
    STR r9, [r7]
    B end_replacement

@ --------------------------------------------

use_way1:

    LDR r5, =cache_tags
    ADD r5, r5, r4
    STR r3, [r5, #4]

    LDR r6, =cache_valid
    ADD r6, r6, r4
    MOV r0, #1
    STR r0, [r6, #4]

    LDR r7, =replacement_type
    LDR r7, [r7]
    CMP r7, #0
    BEQ update_fifo_way1
    CMP r7, #1
    BEQ update_lru_way1
    CMP r7, #2
    BEQ update_mru_way1
    CMP r7, #3
    BEQ update_lfu_way1
	CMP r7, #4
    BEQ update_mfu_way1    
    B end_replacement

update_fifo_way1:
    LDR r7, =cache_fifo_ptr
    LSR r8, r4, #3
    LSL r8, r8, #2
    ADD r7, r7, r8
    LDR r9, [r7]
    EOR r9, r9, #1
    STR r9, [r7]
    B end_replacement

update_lru_way1:
    LDR r7, =cache_lru_state
    LSR r8, r4, #3
    LSL r8, r8, #2
    ADD r7, r7, r8
    MOV r9, #1
    STR r9, [r7]
    B end_replacement

update_mru_way1:
    LDR r7, =cache_mru_state
    LSR r8, r4, #3
    LSL r8, r8, #2
    ADD r7, r7, r8
    MOV r9, #1
    STR r9, [r7]
    B end_replacement

update_lfu_way1:
    LDR r7, =cache_lfu_count
    LSR r8, r4, #3
    LSL r8, r8, #3
    ADD r7, r7, r8
    MOV r9, #1             @ initialize count0
    STR r9, [r7, #4]
    B end_replacement

update_mfu_way1:
    LDR r7, =cache_mfu_count
    LSR r8, r4, #3
    LSL r8, r8, #3
    ADD r7, r7, r8
    MOV r9, #1               @ initialize count0
    STR r9, [r7, #4]
    B end_replacement

end_replacement:
    POP {r0-r6, pc}


@ =============================
@ FIFO replacement algorithm
@ =============================
replace_fifo:
    LSR r8, r4, #3
    LSL r8, r8, #2
    LDR r7, =cache_fifo_ptr
    ADD r7, r7, r8
    LDR r6, [r7]

    LDR r0, =cache_tags
    ADD r0, r0, r4
    LDR r1, =cache_valid
    ADD r1, r1, r4

    CMP r6, #0
    BEQ fifo_replace_way0

fifo_replace_way1:
    STR r3, [r0, #4]
    MOV r2, #1
    STR r2, [r1, #4]
    B toggle_fifo_ptr

fifo_replace_way0:
    STR r3, [r0]
    MOV r2, #1
    STR r2, [r1]

toggle_fifo_ptr:
    EOR r6, r6, #1
    STR r6, [r7]
    BX lr

@ =============================
@ LRU replacement algorithm
@ =============================
replace_lru:
    LSR r8, r4, #3  @ set_index
    LSL r8, r8, #2
    LDR r7, =cache_lru_state
    ADD r7, r7, r8
    LDR r6, [r7]

    LDR r0, =cache_tags
    ADD r0, r0, r4
    LDR r1, =cache_valid
    ADD r1, r1, r4

    CMP r6, #0
    BEQ lru_replace_way1

lru_replace_way0:
    STR r3, [r0]
    MOV r2, #1
    STR r2, [r1]
    MOV r6, #0
	B store_lru_state
	
lru_replace_way1:
    STR r3, [r0, #4]
    MOV r2, #1
    STR r2, [r1, #4]
    MOV r6, #1

store_lru_state:
    STR r6, [r7]
    BX lr
@ ----------------------------------------------
update_lru_state:
    LSR r8, r4, #3
    LSL r8, r8, #2
    LDR r7, =cache_tags
    ADD r7, r7, r4

    LDR r6, [r7]
    CMP r6, r3
    MOVEQ r9, #0
    BNE check_way1_lru
    B write_lru
	
check_way1_lru:
    LDR r6, [r7, #4]
    CMP r6, r3
    MOVEQ r9, #1

write_lru:
    LDR r7, =cache_lru_state
    ADD r7, r7, r8
    STR r9, [r7]
    BX lr

@ =============================
@ MRU replacement algorithm
@ =============================
replace_mru:
    LSR r8, r4, #3          @ r8 = set_index
    LSL r8, r8, #2          @ offset = set_index * 4
    LDR r7, =cache_mru_state
    ADD r7, r7, r8          @ r7 = &cache_mru_state[set_index]
    LDR r6, [r7]            @ r6 = mru_state (0 or 1)

    LDR r0, =cache_tags
    ADD r0, r0, r4
    LDR r1, =cache_valid
    ADD r1, r1, r4

    CMP r6, #1
    BEQ mru_replace_way1

mru_replace_way0:
    STR r3, [r0]
    MOV r2, #1
    STR r2, [r1]
    MOV r6, #0              @ recently used = way0
    B store_mru_state

mru_replace_way1:
    STR r3, [r0, #4]
    MOV r2, #1
    STR r2, [r1, #4]
    MOV r6, #1              @ recently used = way1

store_mru_state:
    STR r6, [r7]            @ update mru state
    BX lr

@ ----------------------------------------------
update_mru_state:
    LSR r8, r4, #3
    LSL r8, r8, #2
    LDR r7, =cache_tags
    ADD r7, r7, r4

    LDR r6, [r7]
    CMP r6, r3
    MOVEQ r9, #0
    BNE check_way1_mru
    B write_mru

check_way1_mru:
    LDR r6, [r7, #4]
    CMP r6, r3
    MOVEQ r9, #1

write_mru:
    LDR r7, =cache_mru_state
    ADD r7, r7, r8
    STR r9, [r7]
    BX lr

@ =============================
@ LFU replacement algorithm
@ =============================
replace_lfu:
    LSR r8, r4, #3          @ r8 = set_index
    LSL r8, r8, #3          @ offset = set_index * 8 (2 words per set)
    LDR r7, =cache_lfu_count
    ADD r7, r7, r8          @ r7 = &cache_lfu_count[set_index * 2]

    LDR r10, [r7]           @ count0
    LDR r11, [r7, #4]       @ count1

    LDR r0, =cache_tags
    ADD r0, r0, r4
    LDR r1, =cache_valid
    ADD r1, r1, r4

    CMP r10, r11
    BLE lfu_replace_way0

lfu_replace_way1:
    STR r3, [r0, #4]
    MOV r2, #1
    STR r2, [r1, #4]
    MOV r2, #1
    STR r2, [r7, #4]        @ reset count1 to 1
    B store_lfu_done

lfu_replace_way0:
    STR r3, [r0]
    MOV r2, #1
    STR r2, [r1]
    MOV r2, #1
    STR r2, [r7]            @ reset count0 to 1

store_lfu_done:
    BX lr

@ ----------------------------------------------
update_lfu_state:
    LSR r8, r4, #3
    LSL r8, r8, #3          @ offset = index * 8
    LDR r7, =cache_tags
    ADD r7, r7, r4

    LDR r6, [r7]
    CMP r6, r3
    MOVEQ r9, #0
    BNE check_way1_lfu
    B inc_lfu_count

check_way1_lfu:
    LDR r6, [r7, #4]
    CMP r6, r3
    MOVEQ r9, #1

inc_lfu_count:
    LDR r7, =cache_lfu_count
    ADD r7, r7, r8

    CMP r9, #0
    LDREQ r10, [r7]
    ADDEQ r10, r10, #1
    STREQ r10, [r7]

    CMP r9, #1
    LDREQ r10, [r7, #4]
    ADDEQ r10, r10, #1
    STREQ r10, [r7, #4]

    BX lr

@ =============================
@ MFU replacement algorithm
@ =============================
replace_mfu:
    LSR r8, r4, #3            @ set_index = address / 8
    LSL r8, r8, #3            @ offset = set_index * 8 

    LDR r7, =cache_mfu_count 
    ADD r7, r7, r8            @ r7 = &cache_freq[set_index]

    LDR r9, [r7]              @ freq0
    LDR r10, [r7, #4]         @ freq1

    LDR r0, =cache_tags
    ADD r0, r0, r4
    LDR r1, =cache_valid
    ADD r1, r1, r4

    CMP r9, r10
    BGT mfu_replace_way0
    BLT mfu_replace_way1

mfu_replace_way0:
    STR r3, [r0]              
    MOV r2, #1
    STR r2, [r1]              
    MOV r9, #0
    B store_mfu_state

mfu_replace_way1:
    STR r3, [r0, #4]         
    MOV r2, #1
    STR r2, [r1, #4]         
    MOV r9, #1

store_mfu_state:
    LDR r7, =cache_mfu_count
    ADD r7, r7, r8
    MOV r6, #1
    STR r6, [r7, r9, LSL #2]  @ freq[way] = 1

    BX lr
@ =============================
@ Update MFU state on hit
@ =============================
update_mfu_state:
    LSR r8, r4, #3
    LSL r8, r8, #3            @ offset = set_index * 8

    LDR r7, =cache_tags
    ADD r7, r7, r4
    LDR r6, [r7]
    CMP r6, r3
    MOVEQ r9, #0
    BNE check_way1_mfu
    B inc_mfu_freq

check_way1_mfu:
    LDR r6, [r7, #4]
    CMP r6, r3
    MOVEQ r9, #1

inc_mfu_freq:
    LDR r7, =cache_mfu_count
    ADD r7, r7, r8
    LDR r10, [r7, r9, LSL #2]
    ADD r10, r10, #1
    STR r10, [r7, r9, LSL #2]
    BX lr

@ =============================
@ Random Replacement Algorithm
@ =============================
replace_random:
    @ Generate a simple pseudo-random number between 0 and 1
    LDR r6, =rand_seed        @ Load the random seed address
    LDR r7, [r6]              @ Load the current seed value
    ADD r7, r7, r4            @ Mix with address to introduce variation
    EOR r7, r7, r3            @ Further mix using XOR
    AND r7, r7, #1            @ Keep only the least significant bit (0 or 1)
    STR r7, [r6]              @ Update the seed

    MOV r9, r7                @ r9 = random_way = 0 or 1

    LDR r0, =cache_tags
    ADD r0, r0, r4
    LDR r1, =cache_valid
    ADD r1, r1, r4

    CMP r9, #0
    BEQ replace_rand_way0

replace_rand_way1:
    STR r3, [r0, #4]          
    MOV r2, #1
    STR r2, [r1, #4]          
    BX lr

replace_rand_way0:
    STR r3, [r0]              
    MOV r2, #1
    STR r2, [r1]              
    BX lr
@---------------
update_policy:
    BX lr
