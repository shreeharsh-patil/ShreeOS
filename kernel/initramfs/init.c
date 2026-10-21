/*
 * kernel/initramfs/init.c — Minimal init for QEMU boot testing
 *
 * A tiny, static, no-libc binary that prints a marker string
 * and halts. The kernel boot test looks for this marker in
 * the QEMU serial output.
 *
 * Compile with host gcc (it runs on the same arch under QEMU):
 *   gcc -static -nostdlib -Os -ffreestanding -o init init.c
 *
 * Then package into initramfs:
 *   echo init | cpio -o -H newc | gzip > initramfs.cpio.gz
 */

/* Linux x86_64 errno value used to detect an interrupted boot marker write. */
#define EINTR_LIBC 4

__attribute__((noreturn))
void _start(void)
{
    const char msg[] = "ShreeOS kernel boot OK\n";
    const char *cursor = msg;
    unsigned long remaining = sizeof(msg) - 1;

    /* write(1, msg, len) via x86_64 syscall. The kernel boot test looks for
     * the complete marker, so short writes and EINTR must be retried. The
     * length is passed through memory with an explicit movq: a "r" operand
     * holding a small constant makes the compiler emit a mixed 32/64-bit
     * register move that the assembler rejects.
     *
     * The syscall entry clobbers rcx and r11, and the block above overwrites
     * rax, rdi, rsi and rdx itself, so every one of them is listed as
     * clobbered. The output is early-clobbered because rax is written before
     * the buffer operand is read; without it the compiler is free to hold the
     * cursor in rax and lose it at the first "mov $1, %%rax". */
    while (remaining > 0) {
        long written;
        __asm__ __volatile__(
            "mov $1, %%rax\n\t"
            "mov $1, %%rdi\n\t"
            "mov %[buf], %%rsi\n\t"
            "movq %[len], %%rdx\n\t"
            "syscall"
            : "=&a"(written)
            : [buf] "r"(cursor), [len] "m"(remaining)
            : "rcx", "r11", "rdi", "rsi", "rdx", "cc", "memory"
        );
        if (written > 0) {
            cursor += written;
            remaining -= (unsigned long)written;
            continue;
        }
        if (written == -EINTR_LIBC) continue;
        break;
    }

    /* Halt the CPU indefinitely */
    for (;;) {
        __asm__ __volatile__("hlt");
    }
}
