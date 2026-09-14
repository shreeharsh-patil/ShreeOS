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

__attribute__((noreturn))
void _start(void)
{
    const char msg[] = "ShreeOS kernel boot OK\n";

    /* write(1, msg, sizeof(msg) - 1) via x86_64 syscall */
    __asm__ __volatile__(
        "mov $1, %%rax\n\t"
        "mov $1, %%rdi\n\t"
        "lea %[buf], %%rsi\n\t"
        "mov %[len], %%rdx\n\t"
        "syscall"
        :
        : [buf] "m"(*msg), [len] "r"((unsigned long)(sizeof(msg) - 1))
        : "rax", "rdi", "rsi", "rdx", "memory"
    );

    /* Halt the CPU indefinitely */
    for (;;) {
        __asm__ __volatile__("hlt");
    }
}
