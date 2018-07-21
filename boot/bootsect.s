	.code16
# rewrite with AT&T syntax by falcon <wuzhangjin@gmail.com> at 081012
#
;// SYSSIZE是要加载的节数（16字节为1节）。3000h共为30000h字节＝192kB
;// 对当前的版本空间已足够了。


	.equ SYSSIZE, 0x3000		;// 指编译连接后system模块的大小。这里给出了一个最大默认值。
#
#	bootsect.s		(C) 1991 Linus Torvalds
#
# bootsect.s is loaded at 0x7c00 by the bios-startup routines, and moves
# iself out of the way to address 0x90000, and jumps there.
#
# It then loads 'setup' directly after itself (0x90200), and the system
# at 0x10000, using BIOS interrupts. 
#
# NOTE! currently system is at most 8*65536 bytes long. This should be no
# problem, even in the future. I want to keep it simple. This 512 kB
# kernel size should be enough, especially as this doesn't contain the
# buffer cache as in minix
#
# The loader has been made as simple as possible, and continuos
# read errors will result in a unbreakable loop. Reboot by hand. It
# loads pretty fast by getting whole sectors at a time whenever possible.
;/* ************************************************************************
;	boot被bios－启动子程序加载至7c00h（31k）处，并将自己移动到了
;	地址90000h（576k）处，并跳转至那里。
;	它然后使用BIOS中断将'setup'直接加载到自己的后面（90200h）（576.5k），
;	并将system加载到地址10000h处。
;
;	注意：目前的内核系统最大长度限制为（8*65536）（512kB）字节，即使是在
;	将来这也应该没有问题的。我想让它保持简单明了。这样512k的最大内核长度应该
;	足够了，尤其是这里没有象minix中一样包含缓冲区高速缓冲。
;
;	加载程序已经做的够简单了，所以持续的读出错将导致死循环。只能手工重启。
;	只要可能，通过一次取取所有的扇区，加载过程可以做的很快的。
;************************************************************************ */

	.global _start, begtext, begdata, begbss, endtext, enddata, endbss
	.text
	begtext:
	.data
	begdata:
	.bss
	begbss:
	.text

	.equ SETUPLEN, 4		# setup程序的扇区数（setup－sectors）值
	.equ BOOTSEG, 0x07c0		# bootsect的原始地址（是段地址，以下同）
	.equ INITSEG, 0x9000		# 将bootsect移到这里
	.equ SETUPSEG, 0x9020		# setup程序从这里开始
	.equ SYSSEG, 0x1000		# system模块加载到10000(64kB)处.
	.equ ENDSEG, SYSSEG + SYSSIZE	# 停止加载的段地址

# ROOT_DEV:	0x000 - 根文件系统设备使用与引导时同样的软驱设备.
#		0x301 - 根文件系统设备在第一个硬盘的第一个分区上，等等
	.equ ROOT_DEV, 0x301		;//指定根文件系统设备是第1个硬盘的第1个分区。这是Linux老式的硬盘命名
					;//方式，具体值的含义如下：
					;//设备号 ＝ 主设备号*256 ＋ 次设备号 
					;//          (也即 dev_no = (major<<8 + minor)
					;//(主设备号：1－内存，2－磁盘，3－硬盘，4－ttyx，5－tty，6－并行口，7－非命名管道)
					;//300 - /dev/hd0 － 代表整个第1个硬盘
					;//301 - /dev/hd1 － 第1个盘的第1个分区
					;//... ...
					;//304 - /dev/hd4 － 第1个盘的第4个分区
					;//305 - /dev/hd5 － 代表整个第2个硬盘
					;//306 - /dev/hd6 － 第2个盘的第1个分区
					;//... ...
					;//309 - /dev/hd9 － 第1个盘的第4个分区 
	ljmp    $BOOTSEG, $_start
_start:				;// 以下10行作用是将自身(bootsect)从目前段位置07c0h(31k)
					;// 移动到9000h(576k)处，共256字(512字节)，然后跳转到
					;// 移动后代码的 go 标号处，也即本程序的下一语句处
	mov	$BOOTSEG, %ax		;// 将ds段寄存器置为7C0h
	mov	%ax, %ds
	mov	$INITSEG, %ax		;// 将es段寄存器置为9000h
	mov	%ax, %es
	mov	$256, %cx		;// 移动计数值 ＝ 256字 = 512 字节
	sub	%si, %si		;// 源地址   ds:si = 07C0h:0000h
	sub	%di, %di		;// 目的地址 es:di = 9000h:0000h
	rep				;// 重复执行，直到cx = 0;移动1个字
	movsw
	ljmp	$INITSEG, $go		;// 间接跳转。这里INITSEG指出跳转到的段地址。
go:	mov	%cs, %ax		;// 将ds、es和ss都置成移动后代码所在的段处（9000h）。
	mov	%ax, %ds		;// 由于程序中有堆栈操作（push，pop，call），因此必须设置堆栈。
	mov	%ax, %es
# put stack at 0x9ff00.		将堆栈指针sp指向9ff00h（即9000h:0ff00h）处
	mov	%ax, %ss
	mov	$0xFF00, %sp		;/* 由于代码段移动过了，所以要重新设置堆栈段的位置。
						;   sp只要指向远大于512偏移（即地址90200h）处
						;   都可以。因为从90200h地址开始处还要放置setup程序，
						;   而此时setup程序大约为4个扇区，因此sp要指向大
						;   于（200h + 200h*4 + 堆栈大小）处。 */

;// 在bootsect程序块后紧跟着加载setup模块的代码数据。
;// 注意es已经设置好了。（在移动代码时es已经指向目的段地址处9000h）。

load_setup:
	;// 以下10行的用途是利用BIOS中断INT 13h将setup模块从磁盘第2个扇区
	;// 开始读到90200h开始处，共读4个扇区。如果读出错，则复位驱动器，并
	;// 重试，没有退路。
	;// INT 13h 的使用方法如下：
	;// ah = 02h - 读磁盘扇区到内存；al = 需要读出的扇区数量；
	;// ch = 磁道（柱面）号的低8位；  cl = 开始扇区（0－5位），磁道号高2位（6－7）；
	;// dh = 磁头号；				  dl = 驱动器号（如果是硬盘则要置为7）；
	;// es:bx ->指向数据缓冲区；  如果出错则CF标志置位。 
	mov	$0x0000, %dx		# drive 0, head 0
	mov	$0x0002, %cx		# sector 2, track 0
	mov	$0x0200, %bx		# address = 512, in INITSEG
	.equ    AX, 0x0200+SETUPLEN
	mov     $AX, %ax		# service 2, nr of sectors
	int	$0x13			# read it
	jnc	ok_load_setup		# ok - continue
	mov	$0x0000, %dx
	mov	$0x0000, %ax		# reset the diskette
	int	$0x13
	jmp	load_setup

ok_load_setup:
;/* 取磁盘驱动器的参数，特别是每道的扇区数量。
;   取磁盘驱动器参数INT 13h调用格式和返回信息如下：
;   ah = 08h	dl = 驱动器号（如果是硬盘则要置位7为1）。
;   返回信息：
;   如果出错则CF置位，并且ah = 状态码。
;   ah = 0, al = 0,         bl = 驱动器类型（AT/PS2）
;   ch = 最大磁道号的低8位，cl = 每磁道最大扇区数（位0-5），最大磁道号高2位（位6-7）
;   dh = 最大磁头数，       电力＝ 驱动器数量，
;   es:di -> 软驱磁盘参数表。 */
	mov	$0x00, %dl
	mov	$0x0800, %ax		;// AH=8 is get drive parameters
	int	$0x13
	mov	$0x00, %ch
	#seg cs			;// 表示下一条语句的操作数在cs段寄存器所指的段中。
	mov	%cx, %cs:sectors+0	;// 保存每磁道扇区数。
	mov	$INITSEG, %ax
	mov	%ax, %es		;// 因为上面取磁盘参数中断改掉了es的值，这里重新改回。

# Print some inane message	在显示一些信息（'Loading system ... '回车换行，共24个字符）。

	mov	$0x03, %ah		# read cursor pos
	xor	%bh, %bh		;// 读光标位置。
	int	$0x10
	
	mov	$24, %cx		;// 共24个字符。
	mov	$0x0007, %bx		# page 0, attribute 7 (normal)
	#lea	msg1, %bp		;// 指向要显示的字符串。
	mov     $msg1, %bp
	mov	$0x1301, %ax		# write string, move cursor
	int	$0x10			;// 写字符串并移动光标。

# ok, we've written the message, now
# we want to load the system (at 0x10000)	现在开始将system 模块加载到10000h(64k)处。

	mov	$SYSSEG, %ax
	mov	%ax, %es		;// segment of 010000h  es = 存放system的段地址。
	call	read_it		;// 读磁盘上system模块，es为输入参数。
	call	kill_motor		;// 关闭驱动器马达，这样就可以知道驱动器的状态了。

;// 此后，我们检查要使用哪个根文件系统设备（简称根设备）。如果已经指定了设备（!=0）
;// 就直接使用给定的设备。否则就需要根据BIOS报告的每磁道扇区数来
;// 确定到底使用/dev/PS0(2,28)还是/dev/at0(2,8)。
;//		上面一行中两个设备文件的含义：
;//		在Linux中软驱的主设备号是2（参加第43行注释），次设备号 = type*4 + nr, 其中
;//		nr为0－3分别对应软驱A、B、C或D；type是软驱的类型（2->1.2M或7->1.44M等）。
;//		因为7*4 + 0 = 28，所以/dev/PS0(2,28)指的是1.44M A驱动器，其设备号是021c
;//		同理 /dev/at0(2,8)指的是1.2M A驱动器，其设备号是0208。

	#seg cs
	mov	%cs:root_dev+0, %ax
	cmp	$0, %ax
	jne	root_defined		;// 如果 ax != 0, 转到root_defined
	#seg cs
	mov	%cs:sectors+0, %bx	;// 取上面保存的每磁道扇区数。如果sectors=15
					;// 则说明是1.2Mb的驱动器；如果sectors=18，则说明是
					;// 1.44Mb软驱。因为是可引导的驱动器，所以肯定是A驱。
	mov	$0x0208, %ax		# /dev/ps0 - 1.2Mb
	cmp	$15, %bx		;// 判断每磁道扇区数是否=15
	je	root_defined		;// 如果等于，则ax中就是引导驱动器的设备号。
	mov	$0x021c, %ax		# /dev/PS0 - 1.44Mb
	cmp	$18, %bx
	je	root_defined
undef_root:				;// 如果都不一样，则死循环（死机）。
	jmp undef_root
root_defined:
	#seg cs
	mov	%ax, %cs:root_dev+0	;// 将检查过的设备号保存起来。

;// 到此，所有程序都加载完毕，我们就跳转到被
;// 加载在bootsect后面的setup程序去。


	ljmp	$SETUPSEG, $0		;// 跳转到9020:0000（setup程序的开始处）。

;//－－－－－－－－－－－－ 本程序到此就结束了。－－－－－－－－－－－－－
;// ******下面是两个子程序。*******

;// 该子程序将系统模块加载到内存地址10000h处，并确定没有跨越64kB的内存边界。
;// 我们试图尽快地进行加载，只要可能，就每次加载整条磁道的数据
;// 
;// 输入：es － 开始内存地址段值（通常是1000h）
;//

sread:	.word 1+ SETUPLEN		;// 当前磁道中已读的扇区数。开始时已经读进1扇区的引导扇区
head:	.word 0			;// 当前磁头号
track:	.word 0			;// 当前磁道号

read_it:				;// 测试输入的段值。必须位于内存地址64KB边界处，否则进入死循环。
	mov	%es, %ax		;// 清bx寄存器，用于表示当前段内存放数据的开始位置。
	test	$0x0fff, %ax
die:	jne 	die			;// es值必须位于64KB地址边界！
	xor 	%bx, %bx		;// bx为段内偏移位置。
rp_read:
;// 判断是否已经读入全部数据。比较当前所读段是否就是系统数据末端所处的段（#ENDSEG），如果
;// 不是就跳转至下面ok1_read标号处继续读数据。否则退出子程序返回。
	mov 	%es, %ax
 	cmp 	$ENDSEG, %ax		# 是否已经加载了全部数据？
	jb	ok1_read
	ret
ok1_read:
;// 计算和验证当前磁道需要读取的扇区数，放在ax寄存器中。
;// 根据当前磁道还未读取的扇区数以及段内数据字节开始偏移位置，计算如果全部读取这些
;// 未读扇区，所读总字节数是否会超过64KB段长度的限制。若会超过，则根据此次最多能读
;// 入的字节数（64KB - 段内偏移位置），反算出此次需要读取的扇区数。
	#seg cs
	mov	%cs:sectors+0, %ax		;// 取每磁道扇区数。
	sub	sread, %ax			;// 减去当前磁道已读扇区数。
	mov	%ax, %cx			;// ax = 当前磁道未读扇区数。
	shl	$9, %cx			;// dx = ax * 512 字节。
	add	%bx, %cx			;// cx = cx + 段内当前偏移值（bx）
						;//    = 此次读操作后，段内共读入的字节数。
	jnc 	ok2_read			;// 若没有超过64KB字节，则跳转至ok2_read处执行。
	je 	ok2_read
	xor 	%ax, %ax			;// 若加上此次将读磁道上所有未读扇区时会超过64KB，则计算
	sub 	%bx, %ax			;// 此时最多能读入的字节数（64KB － 段内读偏移位置），再转换
	shr 	$9, %ax			;// 成需要读取的扇区数。
ok2_read:
	call 	read_track
	mov 	%ax, %cx			;// dx = 该此操作已读取的扇区数。
	add 	sread, %ax			;// 当前磁道上已经读取的扇区数。
	#seg cs
	cmp 	%cs:sectors+0, %ax		;// 如果当前磁道上的还有扇区未读，则跳转到ok3_read处。
	jne 	ok3_read
;// 读该磁道的下一磁头面（1号磁头）上的数据。如果已经完成，则去读下一磁道。
	mov 	$1, %ax
	sub 	head, %ax			;// 判断当前磁头号。
	jne 	ok4_read			;// 如果是0磁头，则再去读1磁头面上的扇区数据
	incw    track 				;// 否则去读下一磁道。
ok4_read:
	mov	%ax, head			;// 保存当前磁头号。
	xor	%ax, %ax			;// 清当前磁道已读扇区数。
ok3_read:
	mov	%ax, sread			;// 保存当前磁道已读扇区数。
	shl	$9, %cx			;// 上次已读扇区数*512字节。
	add	%cx, %bx			;// 调整当前段内数据开始位置。
	jnc	rp_read			;// 若小于64KB边界值，则跳转到rp_read处，继续读数据。
						;// 否则调整当前段，为读下一段数据作准备。
	mov	%es, %ax
	add	$0x1000, %ax			;// 将段基址调整为指向下一个64KB段内存。
	mov	%ax, %es
	xor	%bx, %bx
	jmp	rp_read

;// 读当前磁道上指定开始扇区和需读扇区数的数据到es:bx开始处。
;// al － 需读扇区数； es:bx － 缓冲区开始位置。
read_track:
	push	%ax
	push	%bx
	push	%cx
	push	%dx
	mov	track, %dx			;// 取当前磁道号。
	mov	sread, %cx			;// 取当前磁道上已读扇区数。
	inc	%cx				;// cl = 开始读扇区。
	mov	%dl, %ch			;// ch = 当前磁道号。
	mov	head, %dx			;// 取当前磁头号。
	mov	%dl, %dh			;// dh = 磁头号。
	mov	$0, %dl			;// dl = 驱动器号（为0表示当前驱动器）。
	and	$0x0100, %dx			;// 磁头号不大于1
	mov	$2, %ah			;// ah = 2, 读磁盘扇区功能号。
	int	$0x13
	jc	bad_rt				;// 若出错，则跳转至bad_rt。
	pop	%dx
	pop	%cx
	pop	%bx
	pop	%ax
	ret
;// 执行驱动器复位操作（磁盘中断功能号0），再跳转到read_track处重试。
bad_rt:	mov	$0, %ax
	mov	$0, %dx
	int	$0x13
	pop	%dx
	pop	%cx
	pop	%bx
	pop	%ax
	jmp	read_track

;///*
;//* 这个子程序用于关闭软驱的马达，这样我们进入内核
;//* 后它处于已知状态，以后也就无须担心它了。
;//*/

kill_motor:
	push	%dx
	mov	$0x3f2, %dx		;// 软驱控制卡的驱动端口，只写。
	mov	$0, %al		;// A驱动器，关闭FDC，禁止DMA和中断请求，关闭马达。
	outsb				;// 将al中的内容输出到dx指定的端口去。
	pop	%dx
	ret

sectors:
	.word 0			;// 存放当前启动软盘每磁道的扇区数。

msg1:
	.byte 13,10			;// 回车、换行的ASCII码。
	.ascii "Loading system ..."	;// 我加了my，共有27个字符了
	.byte 13,10,13,10		;// 共24个ASCII码字符。

	.org 508			;// 表示下面语句从地址508(1FC)开始，所以root_dev
					;// 在启动扇区的第508开始的2个字节中。
root_dev:
	.word ROOT_DEV			;// 这里存放根文件系统所在的设备号（init/main.c中会用）。
boot_flag:
	.word 0xAA55			;// 硬盘有效标识。
	
	.text
	endtext:
	.data
	enddata:
	.bss
	endbss:
