#ifndef _STRING_H_
#define _STRING_H_
/*
  其实vc编译器本身包含了这些函数定义，我们完全可以把string.h内的函数定义
  都注释掉，然后为每个.c文件编译时加上/Ox编译选项即可。
*/

#ifndef NULL
#define NULL ((void *) 0)
#endif

#ifndef _SIZE_T
#define _SIZE_T
typedef unsigned int size_t;
#endif

extern char * strerror(int errno);

/*
 * This string-include defines all string functions as inline
 * functions. Use gcc. It also assumes ds=es=data space, this should be
 * normal. Most of the string-functions are rather heavily hand-optimized,
 * see especially strtok,strstr,str[c]spn. They should work, but are not
 * very easy to understand. Everything is done entirely within the register
 * set, making the functions fast and clean. String instructions have been
 * used through-out, making for "slightly" unclear code :-)
 *
 *		(C) 1991 Linus Torvalds
 */
 
/*
* 这个字符串头文件以内嵌函数的形式定义了所有字符串操作函数。使用gcc 时，同时
* 假定了ds=es=数据空间，这应该是常规的。绝大多数字符串函数都是经手工进行大量
* 优化的，尤其是函数strtok、strstr、str[c]spn。它们应该能正常工作，但却不是那
* 么容易理解。所有的操作基本上都是使用寄存器集来完成的，这使得函数即快有整洁。
* 所有地方都使用了字符串指令，这又使得代码“稍微”难以理解?
*
* (C) 1991 Linus Torvalds
*/

//// 将一个字符串(src)拷贝到另一个字符串(dest)，直到遇到NULL 字符后停止。
// 参数：dest - 目的字符串指针，src - 源字符串指针。
// %0 - esi(src)，%1 - edi(dest)。
extern inline char * strcpy(char * dest,const char *src)
{
__asm__("cld\n"	// 清方向位。
	"1:\tlodsb\n\t"	// 加载DS:[esi]处1 字节->al，并更新esi。
	"stosb\n\t"		// 存储字节al->ES:[edi]，并更新edi。
	"testb %%al,%%al\n\t"	// 刚存储的字节是0？
	"jne 1b"				// 不是则跳转到标号l1 处，否则结束。
	::"S" (src),"D" (dest));
return dest;		// 返回目的字符串指针。
}

//// 拷贝源字符串count 个字节到目的字符串。
// 如果源串长度小于count 个字节，就附加空字符(NULL)到目的字符串。
// 参数：dest - 目的字符串指针，src - 源字符串指针，count - 拷贝字节数。
// %0 - esi(src)，%1 - edi(dest)，%2 - ecx(count)。
static inline char * strncpy(char * dest,const char *src,int count)
{
__asm__("cld\n"		// 清方向位。
	"1:\tdecl %2\n\t"		// 寄存器ecx--（count--）。
	"js 2f\n\t"			// 如果count<0 则向前跳转到标号l2，结束。
	"lodsb\n\t"			// 取ds:[esi]处1 字节->al，并且esi++。
	"stosb\n\t"			// 存储该字节->es:[edi]，并且edi++。
	"testb %%al,%%al\n\t"	// 该字节是0？
	"jne 1b\n\t"			// 不是，则向前跳转到标号l1 处继续拷贝。
	"rep\n\t"				// 否则，在目的串中存放剩余个数的空字符。
	"stosb\n"
	"2:"
	::"S" (src),"D" (dest),"c" (count));
return dest;		// 返回目的字符串指针。
}

//// 将源字符串拷贝到目的字符串的末尾处。
// 参数：dest - 目的字符串指针，src - 源字符串指针。
// %0 - esi(src)，%1 - edi(dest)，%2 - eax(0)，%3 - ecx(-1)。
extern inline char * strcat(char * dest,const char * src)
{
__asm__("cld\n\t"				// 清方向位。
	"repne\n\t"
	"scasb\n\t"			// 比较al 与es:[edi]字节，并更新edi++，
							// 直到找到目的串中是0 的字节，此时edi 已经指向后1 字节。
	"decl %1\n"			// 让es:[edi]指向0 值字节。
	"1:\tlodsb\n\t"		// 取源字符串字节ds:[esi]->al，并esi++。
	"stosb\n\t"			// 将该字节存到es:[edi]，并edi++。
	"testb %%al,%%al\n\t"	// 该字节是0？
	"jne 1b"				// 不是，则向后跳转到标号1 处继续拷贝，否则结束。
	::"S" (src),"D" (dest),"a" (0),"c" (0xffffffff));
return dest;				// 返回目的字符串指针。
}

//// 将源字符串的count 个字节复制到目的字符串的末尾处，最后添一空字符。
// 参数：dest - 目的字符串，src - 源字符串，count - 欲复制的字节数。
// %0 - esi(src)，%1 - edi(dest)，%2 - eax(0)，%3 - ecx(-1)，%4 - (count)。
static inline char * strncat(char * dest,const char * src,int count)
{
__asm__("cld\n\t"
	"repne\n\t"
	"scasb\n\t"
	"decl %1\n\t"
	"movl %4,%3\n"
	"1:\tdecl %3\n\t"
	"js 2f\n\t"
	"lodsb\n\t"
	"stosb\n\t"
	"testb %%al,%%al\n\t"
	"jne 1b\n"
	"2:\txorl %2,%2\n\t"
	"stosb"
	::"S" (src),"D" (dest),"a" (0),"c" (0xffffffff),"g" (count)
	);
return dest;
}

extern inline int strcmp(const char * cs,const char * ct)
{
register int __res ;
__asm__("cld\n"
	"1:\tlodsb\n\t"
	"scasb\n\t"
	"jne 2f\n\t"
	"testb %%al,%%al\n\t"
	"jne 1b\n\t"
	"xorl %%eax,%%eax\n\t"
	"jmp 3f\n"
	"2:\tmovl $1,%%eax\n\t"
	"jl 3f\n\t"
	"negl %%eax\n"
	"3:"
	:"=a" (__res):"D" (cs),"S" (ct));
return __res;
}

static inline int strncmp(const char * cs,const char * ct,int count)
{
register int __res ;
__asm__("cld\n"
	"1:\tdecl %3\n\t"
	"js 2f\n\t"
	"lodsb\n\t"
	"scasb\n\t"
	"jne 3f\n\t"
	"testb %%al,%%al\n\t"
	"jne 1b\n"
	"2:\txorl %%eax,%%eax\n\t"
	"jmp 4f\n"
	"3:\tmovl $1,%%eax\n\t"
	"jl 4f\n\t"
	"negl %%eax\n"
	"4:"
	:"=a" (__res):"D" (cs),"S" (ct),"c" (count));
return __res;
}

static inline char * strchr(const char * s,char c)
{
register char * __res ;
__asm__("cld\n\t"
	"movb %%al,%%ah\n"
	"1:\tlodsb\n\t"
	"cmpb %%ah,%%al\n\t"
	"je 2f\n\t"
	"testb %%al,%%al\n\t"
	"jne 1b\n\t"
	"movl $1,%1\n"
	"2:\tmovl %1,%0\n\t"
	"decl %0"
	:"=a" (__res):"S" (s),"0" (c));
return __res;
}

static inline char * strrchr(const char * s,char c)
{
register char * __res; 
__asm__("cld\n\t"
	"movb %%al,%%ah\n"
	"1:\tlodsb\n\t"
	"cmpb %%ah,%%al\n\t"
	"jne 2f\n\t"
	"movl %%esi,%0\n\t"
	"decl %0\n"
	"2:\ttestb %%al,%%al\n\t"
	"jne 1b"
	:"=d" (__res):"0" (0),"S" (s),"a" (c));
return __res;
}

extern inline int strspn(const char * cs, const char * ct)
{
register char * __res;
__asm__("cld\n\t"
	"movl %4,%%edi\n\t"
	"repne\n\t"
	"scasb\n\t"
	"notl %%ecx\n\t"
	"decl %%ecx\n\t"
	"movl %%ecx,%%edx\n"
	"1:\tlodsb\n\t"
	"testb %%al,%%al\n\t"
	"je 2f\n\t"
	"movl %4,%%edi\n\t"
	"movl %%edx,%%ecx\n\t"
	"repne\n\t"
	"scasb\n\t"
	"je 1b\n"
	"2:\tdecl %0"
	:"=S" (__res):"a" (0),"c" (0xffffffff),"0" (cs),"g" (ct)
	);
return __res-cs;
}

extern inline int strcspn(const char * cs, const char * ct)
{
register char * __res;
__asm__("cld\n\t"
	"movl %4,%%edi\n\t"
	"repne\n\t"
	"scasb\n\t"
	"notl %%ecx\n\t"
	"decl %%ecx\n\t"
	"movl %%ecx,%%edx\n"
	"1:\tlodsb\n\t"
	"testb %%al,%%al\n\t"
	"je 2f\n\t"
	"movl %4,%%edi\n\t"
	"movl %%edx,%%ecx\n\t"
	"repne\n\t"
	"scasb\n\t"
	"jne 1b\n"
	"2:\tdecl %0"
	:"=S" (__res):"a" (0),"c" (0xffffffff),"0" (cs),"g" (ct)
	);
return __res-cs;
}

extern inline char * strpbrk(const char * cs,const char * ct)
{
register char * __res ;
__asm__("cld\n\t"
	"movl %4,%%edi\n\t"
	"repne\n\t"
	"scasb\n\t"
	"notl %%ecx\n\t"
	"decl %%ecx\n\t"
	"movl %%ecx,%%edx\n"
	"1:\tlodsb\n\t"
	"testb %%al,%%al\n\t"
	"je 2f\n\t"
	"movl %4,%%edi\n\t"
	"movl %%edx,%%ecx\n\t"
	"repne\n\t"
	"scasb\n\t"
	"jne 1b\n\t"
	"decl %0\n\t"
	"jmp 3f\n"
	"2:\txorl %0,%0\n"
	"3:"
	:"=S" (__res):"a" (0),"c" (0xffffffff),"0" (cs),"g" (ct)
	);
return __res;
}

extern inline char * strstr(const char * cs,const char * ct)
{
register char * __res ;
__asm__("cld\n\t" \
	"movl %4,%%edi\n\t"
	"repne\n\t"
	"scasb\n\t"
	"notl %%ecx\n\t"
	"decl %%ecx\n\t"	/* NOTE! This also sets Z if searchstring='' */
	"movl %%ecx,%%edx\n"
	"1:\tmovl %4,%%edi\n\t"
	"movl %%esi,%%eax\n\t"
	"movl %%edx,%%ecx\n\t"
	"repe\n\t"
	"cmpsb\n\t"
	"je 2f\n\t"		/* also works for empty string, see above */
	"xchgl %%eax,%%esi\n\t"
	"incl %%esi\n\t"
	"cmpb $0,-1(%%eax)\n\t"
	"jne 1b\n\t"
	"xorl %%eax,%%eax\n\t"
	"2:"
	:"=a" (__res):"0" (0),"c" (0xffffffff),"S" (cs),"g" (ct)
	);
return __res;
}

extern inline int strlen(const char * s)
{
register int __res ;
__asm__("cld\n\t"
	"repne\n\t"
	"scasb\n\t"
	"notl %0\n\t"
	"decl %0"
	:"=c" (__res):"D" (s),"a" (0),"0" (0xffffffff));
return __res;
}

extern char * ___strtok;

extern inline char * strtok(char * s,const char * ct)
{
register char * __res ;
__asm__("testl %1,%1\n\t"
	"jne 1f\n\t"
	"testl %0,%0\n\t"
	"je 8f\n\t"
	"movl %0,%1\n"
	"1:\txorl %0,%0\n\t"
	"movl $-1,%%ecx\n\t"
	"xorl %%eax,%%eax\n\t"
	"cld\n\t"
	"movl %4,%%edi\n\t"
	"repne\n\t"
	"scasb\n\t"
	"notl %%ecx\n\t"
	"decl %%ecx\n\t"
	"je 7f\n\t"			/* empty delimeter-string */
	"movl %%ecx,%%edx\n"
	"2:\tlodsb\n\t"
	"testb %%al,%%al\n\t"
	"je 7f\n\t"
	"movl %4,%%edi\n\t"
	"movl %%edx,%%ecx\n\t"
	"repne\n\t"
	"scasb\n\t"
	"je 2b\n\t"
	"decl %1\n\t"
	"cmpb $0,(%1)\n\t"
	"je 7f\n\t"
	"movl %1,%0\n"
	"3:\tlodsb\n\t"
	"testb %%al,%%al\n\t"
	"je 5f\n\t"
	"movl %4,%%edi\n\t"
	"movl %%edx,%%ecx\n\t"
	"repne\n\t"
	"scasb\n\t"
	"jne 3b\n\t"
	"decl %1\n\t"
	"cmpb $0,(%1)\n\t"
	"je 5f\n\t"
	"movb $0,(%1)\n\t"
	"incl %1\n\t"
	"jmp 6f\n"
	"5:\txorl %1,%1\n"
	"6:\tcmpb $0,(%0)\n\t"
	"jne 7f\n\t"
	"xorl %0,%0\n"
	"7:\ttestl %0,%0\n\t"
	"jne 8f\n\t"
	"movl %0,%1\n"
	"8:"
	:"=b" (__res),"=S" (___strtok)
	:"0" (___strtok),"1" (s),"g" (ct)
	);
return __res;
}

/*
 * Changes by falcon<zhangjinw@gmail.com>, the original return value is static
 * inline ... it can not be called by other functions in another files.
 */

extern inline void * memcpy(void * dest,const void * src, int n)
{
__asm__ ("cld\n\t"
	"rep\n\t"
	"movsb"
	::"c" (n),"S" (src),"D" (dest)
	);
return dest;
}

extern inline void * memmove(void * dest,const void * src, int n)
{
if (dest<src)
__asm__("cld\n\t"
	"rep\n\t"
	"movsb"
	::"c" (n),"S" (src),"D" (dest)
	);
else
__asm__("std\n\t"
	"rep\n\t"
	"movsb"
	::"c" (n),"S" (src+n-1),"D" (dest+n-1)
	);
return dest;
}

static inline int memcmp(const void * cs,const void * ct,int count)
{
register int __res ;
__asm__("cld\n\t"
	"repe\n\t"
	"cmpsb\n\t"
	"je 1f\n\t"
	"movl $1,%%eax\n\t"
	"jl 1f\n\t"
	"negl %%eax\n"
	"1:"
	:"=a" (__res):"0" (0),"D" (cs),"S" (ct),"c" (count)
	);
return __res;
}

extern inline void * memchr(const void * cs,char c,int count)
{
register void * __res ;
if (!count)
	return NULL;
__asm__("cld\n\t"
	"repne\n\t"
	"scasb\n\t"
	"je 1f\n\t"
	"movl $1,%0\n"
	"1:\tdecl %0"
	:"=D" (__res):"a" (c),"D" (cs),"c" (count)
	);
return __res;
}

static inline void * memset(void * s,char c,int count)
{
__asm__("cld\n\t"
	"rep\n\t"
	"stosb"
	::"a" (c),"D" (s),"c" (count)
	);
return s;
}

#endif
