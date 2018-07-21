/*
 *  linux/kernel/system_call.s
 *
 *  (C) 1991  Linus Torvalds
 */

/*
 *  system_call.s  contains the system-call low-level handling routines.
 * This also contains the timer-interrupt handler, as some of the code is
 * the same. The hd- and flopppy-interrupts are also here.
 *
 * NOTE: This code handles signal-recognition, which happens every time
 * after a timer-interrupt and after each system call. Ordinary interrupts
 * don't handle signal-recognition, as that would clutter them up totally
 * unnecessarily.
 *
 * Stack layout in 'ret_from_system_call':
 *
 *	 0(%esp) - %eax
 *	 4(%esp) - %ebx
 *	 8(%esp) - %ecx
 *	 C(%esp) - %edx
 *	10(%esp) - %fs
 *	14(%esp) - %es
 *	18(%esp) - %ds
 *	1C(%esp) - %eip
 *	20(%esp) - %cs
 *	24(%esp) - %eflags
 *	28(%esp) - %oldesp
 *	2C(%esp) - %oldss
 */
;/*
;* system_call.s 文件包含系统调用(system-call)底层处理子程序。由于有些代码比较类似，所以
;* 同时也包括时钟中断处理(timer-interrupt)句柄。硬盘和软盘的中断处理程序也在这里。
;*
;* 注意：这段代码处理信号(signal)识别，在每次时钟中断和系统调用之后都会进行识别。一般
;* 中断信号并不处理信号识别，因为会给系统造成混乱。
;*
;* 从系统调用返回（'ret_from_system_call'）时堆栈的内容见上面19-30 行。
;*/

SIG_CHLD	= 17	;// 定义SIG_CHLD 信号（子进程停止或结束）。

EAX		= 0x00	;// 堆栈中各个寄存器的偏移位置。
EBX		= 0x04
ECX		= 0x08
EDX		= 0x0C
FS		= 0x10
ES		= 0x14
DS		= 0x18
EIP		= 0x1C
CS		= 0x20
EFLAGS		= 0x24
OLDESP		= 0x28	;// 当有特权级变化时。
OLDSS		= 0x2C

;// 以下这些是任务结构(task_struct)中变量的偏移值，参见include/linux/sched.h，77 行开始。
state	= 0		# these are offsets into the task-struct. ;// 进程状态码
counter	= 4	;// 任务运行时间计数(递减)（滴答数），运行时间片。
priority = 8	;// 运行优先数。任务开始运行时counter=priority，越大则运行时间越长。
signal	= 12	;// 是信号位图，每个比特位代表一种信号，信号值=位偏移值+1。
sigaction = 16		# MUST be 16 (=len of sigaction)	// sigaction 结构长度必须是16 字节。
;// 信号执行属性结构数组的偏移值，对应信号将要执行的操作和标志信息。
blocked = (33*16)	;// 受阻塞信号位图的偏移量。

;// 以下定义在sigaction 结构中的偏移量，参见include/signal.h，第48 行开始。
# offsets within sigaction
sa_handler = 0	;// 信号处理过程的句柄（描述符）。
sa_mask = 4	;// 信号量屏蔽码
sa_flags = 8	;// 信号集。
sa_restorer = 12	;// 返回恢复执行的地址位置。

nr_system_calls = 72	 ;// Linux 0.11 版内核中的系统调用总数。

/*
 * Ok, I get parallel printer interrupts while using the floppy for some
 * strange reason. Urgel. Now I just ignore them.
 */
;/*
;* 好了，在使用软驱时我收到了并行打印机中断，很奇怪。呵，现在不管它。
;*/
;// 定义入口点。
.globl system_call,sys_fork,timer_interrupt,sys_execve
.globl hd_interrupt,floppy_interrupt,parallel_interrupt
.globl device_not_available, coprocessor_error

.align 2
;// 错误的系统调用号。
bad_sys_call:
	movl $-1,%eax	;// eax 中置-1，退出中断。
	iret
;// 重新执行调度程序入口。调度程序schedule 在(kernel/sched.c,104)。
.align 2
reschedule:
	pushl $ret_from_sys_call	;// 将ret_from_sys_call 的地址入栈（101 行）。
	jmp schedule
;//// int 0x80 --linux 系统调用入口点(调用中断int 0x80，eax 中是调用号)。
.align 2
system_call:
	cmpl $nr_system_calls-1,%eax	;// 调用号如果超出范围的话就在eax 中置-1 并退出。
	ja bad_sys_call
	push %ds	;// 保存原段寄存器值。
	push %es
	push %fs
	pushl %edx	;// ebx,ecx,edx 中放着系统调用相应的C 语言函数的调用参数。
	pushl %ecx		# push %ebx,%ecx,%edx as parameters
	pushl %ebx		# to the system call
	movl $0x10,%edx		# set up ds,es to kernel space
	mov %dx,%ds	;// ds,es 指向内核数据段(全局描述符表中数据段描述符)。
	mov %dx,%es
	movl $0x17,%edx		# fs points to local data space
	mov %dx,%fs	;// fs 指向局部数据段(局部描述符表中数据段描述符)。
;// 下面这句操作数的含义是：调用地址 = _sys_call_table + %eax * 4。参见列表后的说明。
;// 对应的C 程序中的sys_call_table 在include/linux/sys.h 中，其中定义了一个包括72 个
;// 系统调用C 处理函数的地址数组表。
	call *sys_call_table(,%eax,4)
	pushl %eax	;// 把系统调用号入栈。
	movl current,%eax	;// 取当前任务（进程）数据结构地址??eax。
;// 下面97-100 行查看当前任务的运行状态。如果不在就绪状态(state 不等于0)就去执行调度程序。
;// 如果该任务在就绪状态但counter[??]值等于0，则也去执行调度程序。
	cmpl $0,state(%eax)		# state
	jne reschedule
	cmpl $0,counter(%eax)		# counter
	je reschedule
;// 以下这段代码执行从系统调用C 函数返回后，对信号量进行识别处理。
ret_from_sys_call:
;// 首先判别当前任务是否是初始任务task0，如果是则不必对其进行信号量方面的处理，直接返回。
;// 103 行上的_task 对应C 程序中的task[]数组，直接引用task 相当于引用task[0]。
	movl current,%eax		# task[0] cannot have signals
	cmpl task,%eax
	je 3f		;// 向前(forward)跳转到标号3f。
;// 通过对原调用程序代码选择符的检查来判断调用程序是否是超级用户。如果是超级用户就直接
;// 退出中断，否则需进行信号量的处理。这里比较选择符是否为普通用户代码段的选择符0x000f
;// (RPL=3，局部表，第1 个段(代码段))，如果不是则跳转退出中断程序。
	cmpw $0x0f,CS(%esp)		# was old code segment supervisor ?
	jne 3f
;// 如果原堆栈段选择符不为0x17（也即原堆栈不在用户数据段中），则也退出。
	cmpw $0x17,OLDSS(%esp)		# was stack segment = 0x17 ?
	jne 3f
;// 下面这段代码（109-120）的用途是首先取当前任务结构中的信号位图(32 位，每位代表1 种信号)，
;// 然后用任务结构中的信号阻塞（屏蔽）码，阻塞不允许的信号位，取得数值最小的信号值，再把
;// 原信号位图中该信号对应的位复位（置0），最后将该信号值作为参数之一调用do_signal()。
;// do_signal()在（kernel/signal.c,82）中，其参数包括13 个入栈的信息。
	movl signal(%eax),%ebx		;// 取信号位图??ebx，每1 位代表1 种信号，共32 个信号。
	movl blocked(%eax),%ecx	 ;// 取阻塞（屏蔽）信号位图??ecx。
	notl %ecx			;// 每位取反。
	andl %ebx,%ecx		;// 获得许可的信号位图。
	bsfl %ecx,%ecx		;// 从低位（位0）开始扫描位图，看是否有1 的位，
;// 若有，则ecx 保留该位的偏移值（即第几位0-31）。
	je 3f		;// 如果没有信号则向前跳转退出。
	btrl %ecx,%ebx	;// 复位该信号（ebx 含有原signal 位图）。
	movl %ebx,signal(%eax)	;// 重新保存signal 位图信息??current->signal。
	incl %ecx	;// 将信号调整为从1 开始的数(1-32)。
	pushl %ecx	;// 信号值入栈作为调用do_signal 的参数之一。
	call do_signal	;// 调用C 函数信号处理程序(kernel/signal.c,82)
	popl %eax	;// 弹出信号值。
3:	popl %eax
	popl %ebx
	popl %ecx
	popl %edx
	pop %fs
	pop %es
	pop %ds
	iret

;//// int16 -- 下面这段代码处理协处理器发出的出错信号。跳转执行C 函数math_error()
;// (kernel/math/math_emulate.c,82)，返回后将跳转到ret_from_sys_call 处继续执行。
.align 2
coprocessor_error:
	push %ds
	push %es
	push %fs
	pushl %edx
	pushl %ecx
	pushl %ebx
	pushl %eax
	movl $0x10,%eax	;// ds,es 置为指向内核数据段。
	mov %ax,%ds
	mov %ax,%es
	movl $0x17,%eax	;// fs 置为指向局部数据段（出错程序的数据段）。
	mov %ax,%fs
	pushl $ret_from_sys_call	;// 把下面调用返回的地址入栈。
	jmp math_error	;// 执行C 函数math_error()(kernel/math/math_emulate.c,37)

;//// int7 -- 设备不存在或协处理器不存在(Coprocessor not available)。
;// 如果控制寄存器CR0 的EM 标志置位，则当CPU 执行一个R_ESC 转义指令时就会引发该中断，这样就
;// 可以有机会让这个中断处理程序模拟R_ESC 转义指令（169 行）。
;// CR0 的TS 标志是在CPU 执行任务转换时设置的。TS 可以用来确定什么时候协处理器中的内容（上下文）
;// 与CPU 正在执行的任务不匹配了。当CPU 在运行一个转义指令时发现TS 置位了，就会引发该中断。
;// 此时就应该恢复新任务的协处理器执行状态（165 行）。参见(kernel/sched.c,77)中的说明。
;// 该中断最后将转移到标号ret_from_sys_call 处执行下去（检测并处理信号）。
.align 2
device_not_available:
	push %ds
	push %es
	push %fs
	pushl %edx
	pushl %ecx
	pushl %ebx
	pushl %eax
	movl $0x10,%eax	;// ds,es 置为指向内核数据段。
	mov %ax,%ds
	mov %ax,%es
	movl $0x17,%eax	;// fs 置为指向局部数据段（出错程序的数据段）。
	mov %ax,%fs
	pushl $ret_from_sys_call	;// 把下面跳转或调用的返回地址入栈。
	clts				# clear TS so that we can use math
	movl %cr0,%eax
	testl $0x4,%eax			# EM (math emulation bit)
	;// 如果不是EM 引起的中断，则恢复新任务协处理器状态，
	je math_state_restore	;// 执行C 函数math_state_restore()(kernel/sched.c,77)。
	pushl %ebp
	pushl %esi
	pushl %edi
	call math_emulate	;// 调用C 函数math_emulate(kernel/math/math_emulate.c,18)。
	popl %edi
	popl %esi
	popl %ebp
	ret	;// 这里的ret 将跳转到ret_from_sys_call(101 行)。

;//// int32 -- (int 0x20) 时钟中断处理程序。中断频率被设置为100Hz(include/linux/sched.h,5)，
;// 定时芯片8253/8254 是在(kernel/sched.c,406)处初始化的。因此这里jiffies 每10 毫秒加1。
;// 这段代码将jiffies 增1，发送结束中断指令给8259 控制器，然后用当前特权级作为参数调用
;// C 函数do_timer(long CPL)。当调用返回时转去检测并处理信号。
.align 2
timer_interrupt:
	push %ds		# save ds,es and put kernel data space
	push %es		# into them. %fs is used by _system_call
	push %fs
	pushl %edx		# we save %eax,%ecx,%edx as gcc doesn't
	pushl %ecx		# save those across function calls. %ebx
	pushl %ebx		# is saved as we use that in ret_sys_call
	pushl %eax
	movl $0x10,%eax	;// ds,es 置为指向内核数据段。
	mov %ax,%ds
	mov %ax,%es
	movl $0x17,%eax	;// fs 置为指向局部数据段（出错程序的数据段）。
	mov %ax,%fs
	incl jiffies
;// 由于初始化中断控制芯片时没有采用自动EOI，所以这里需要发指令结束该硬件中断。
	movb $0x20,%al		# EOI to interrupt controller #1
	outb %al,$0x20	;// 操作命令字OCW2 送0x20 端口。
;// 下面3 句从选择符中取出当前特权级别(0 或3)并压入堆栈，作为do_timer 的参数。
	movl CS(%esp),%eax
	andl $3,%eax		# %eax is CPL (0 or 3, 0=supervisor)
	pushl %eax
;// do_timer(CPL)执行任务切换、计时等工作，在kernel/shched.c,305 行实现。
	call do_timer		# 'do_timer(long CPL)' does everything from
	addl $4,%esp		# task switching to accounting ...
	jmp ret_from_sys_call

;//// 这是sys_execve()系统调用。取中断调用程序的代码指针作为参数调用C 函数do_execve()。
;// do_execve()在(fs/exec.c,182)。
.align 2
sys_execve:
	lea EIP(%esp),%eax
	pushl %eax
	call do_execve
	addl $4,%esp	 ;// 丢弃调用时压入栈的R_EIP 值。
	ret

;//// sys_fork()调用，用于创建子进程，是system_call 功能2。原形在include/linux/sys.h 中。
;// 首先调用C 函数find_empty_process()，取得一个进程号pid。若返回负数则说明目前任务数组
;// 已满。然后调用copy_process()复制进程。
.align 2
sys_fork:
	call find_empty_process	;// 调用find_empty_process()(kernel/fork.c,135)。
	testl %eax,%eax
	js 1f
	push %gs
	pushl %esi
	pushl %edi
	pushl %ebp
	pushl %eax
	call copy_process	;// 调用C 函数copy_process()(kernel/fork.c,68)。
	addl $20,%esp	;// 丢弃这里所有压栈内容。
1:	ret

;//// int 46 -- (int 0x2E) 硬盘中断处理程序，响应硬件中断请求IRQ14。
;// 当硬盘操作完成或出错就会发出此中断信号。(参见kernel/blk_drv/hd.c)。
;// 首先向8259A 中断控制从芯片发送结束硬件中断指令(EOI)，然后取变量do_hd 中的函数指针放入edx
;// 寄存器中，并置do_hd 为NULL，接着判断edx 函数指针是否为空。如果为空，则给edx 赋值指向
;// unexpected_hd_interrupt()，用于显示出错信息。随后向8259A 主芯片送EOI 指令，并调用edx 中
;// 指针指向的函数: read_intr()、write_intr()或unexpected_hd_interrupt()。
hd_interrupt:
	pushl %eax
	pushl %ecx
	pushl %edx
	push %ds
	push %es
	push %fs
	movl $0x10,%eax	 ;// ds,es 置为内核数据段。
	mov %ax,%ds
	mov %ax,%es	
	movl $0x17,%eax	;// fs 置为调用程序的局部数据段。
	mov %ax,%fs
;// 由于初始化中断控制芯片时没有采用自动EOI，所以这里需要发指令结束该硬件中断。
	movb $0x20,%al
	outb %al,$0xA0		# EOI to interrupt controller #1	;// 送从8259A。
	jmp 1f			# give port chance to breathe
1:	jmp 1f	;// 延时作用。
1:	xorl %edx,%edx
	xchgl do_hd,%edx	;// do_hd 定义为一个函数指针，将被赋值read_intr()或
;// write_intr()函数地址。(kernel/blk_drv/hd.c)
;// 放到edx 寄存器后就将do_hd 指针变量置为NULL。
	testl %edx,%edx	 ;// 测试函数指针是否为Null。
	jne 1f		;// 若空，则使指针指向C 函数unexpected_hd_interrupt()。
	movl $unexpected_hd_interrupt,%edx	;// (kernel/blk_drv/hdc,237)。
1:	outb %al,$0x20	;// 送主8259A 中断控制器EOI 指令（结束硬件中断）。
	call *%edx		# "interesting" way of handling intr.
	pop %fs	;// 上句调用do_hd 指向的C 函数。
	pop %es
	pop %ds
	popl %edx
	popl %ecx
	popl %eax
	iret

;//// int38 -- (int 0x26) 软盘驱动器中断处理程序，响应硬件中断请求IRQ6。
;// 其处理过程与上面对硬盘的处理基本一样。(kernel/blk_drv/floppy.c)。
;// 首先向8259A 中断控制器主芯片发送EOI 指令，然后取变量do_floppy 中的函数指针放入eax
;// 寄存器中，并置do_floppy 为NULL，接着判断eax 函数指针是否为空。如为空，则给eax 赋值指向
;// unexpected_floppy_interrupt ()，用于显示出错信息。随后调用eax 指向的函数: rw_interrupt,
;// seek_interrupt,recal_interrupt,reset_interrupt 或unexpected_floppy_interrupt。
floppy_interrupt:
	pushl %eax
	pushl %ecx
	pushl %edx
	push %ds
	push %es
	push %fs
	movl $0x10,%eax	;// ds,es 置为内核数据段。
	mov %ax,%ds
	mov %ax,%es
	movl $0x17,%eax	;// fs 置为调用程序的局部数据段。
	mov %ax,%fs
	movb $0x20,%al	;// 送主8259A 中断控制器EOI 指令（结束硬件中断）。
	outb %al,$0x20		# EOI to interrupt controller #1
	xorl %eax,%eax
	xchgl do_floppy,%eax	;// do_floppy 为一函数指针，将被赋值实际处理C 函数程序，
;// 放到eax 寄存器后就将do_floppy 指针变量置空。
	testl %eax,%eax	 ;// 测试函数指针是否=NULL?
	jne 1f		;// 若空，则使指针指向C 函数unexpected_floppy_interrupt()。
	movl $unexpected_floppy_interrupt,%eax
1:	call *%eax		# "interesting" way of handling intr.
	pop %fs	;// 上句调用do_floppy 指向的函数。
	pop %es
	pop %ds
	popl %edx
	popl %ecx
	popl %eax
	iret

;//// int 39 -- (int 0x27) 并行口中断处理程序，对应硬件中断请求信号IRQ7。
;// 本版本内核还未实现。这里只是发送EOI 指令。
parallel_interrupt:
	pushl %eax
	movb $0x20,%al
	outb %al,$0x20
	popl %eax
	iret
