.set noreorder

// a compact, fast memcpy for PS1

.set dst, $a0
.set src, $a1
.set size, $a2
.set target, $v0
.set aligned_target, $v1
.set alignment, $t0
.set tmp, $t1
.set val0, $t2
.set val1, $t3
.set val2, $t4
.set val3, $t5

.section .text.memcpy, "ax", @progbits
.type memcpy, @function
.global memcpy
memcpy:
	// if less than 16 bytes, just copy in bytes
	bltu size, 16, .Lmemcpy_byte
	addu target, dst, size // branch delay slot

	// if src or dst not aligned to words, just copy in bytes
	or alignment, dst, src
	andi alignment, 3
	bnez alignment, .Lmemcpy_byte_loop // skip the size check because it is already known to be over 4 bytes here

	// copy word-aligned chunks of 16 bytes
	srl tmp, size, 4 // branch delay slot
	sll tmp, 4
	addu aligned_target, dst, tmp
.Lmemcpy_chunked_loop:
	lw val0, (src)
	lw val1, 4(src)
	lw val2, 8(src)
	lw val3, 12(src)
	addiu src, 16
	addiu dst, 16
	sw val0, -16(dst)
	sw val1, -12(dst)
	sw val2, -8(dst)
	bne dst, aligned_target, .Lmemcpy_chunked_loop
	sw val3, -4(dst) // branch delay slot

	// copy any remaining bytes
.Lmemcpy_byte:
	beq dst, target, .Lmemcpy_done
	nop // branch delay slot
.Lmemcpy_byte_loop:
	lb val0, (src)
	addiu src, 1
	addiu dst, 1
	bne dst, target, .Lmemcpy_byte_loop
	sb val0, -1(dst) // branch delay slot

.Lmemcpy_done:
	jr $ra
	move $v0, dst // branch delay slot
