# Translate shared Linux-shaped calls to libSystem. Linux syscalls preserve
# their argument registers and return negative errno; this bridge does too.
.intel_syntax noprefix
.text
mac_syscall:
 push rbx
 mov rbx,rsp
 and rsp,-16
 sub rsp,64
 mov [rsp],rdi
 mov [rsp+8],rsi
 mov [rsp+16],rdx
 mov [rsp+24],r8
 mov [rsp+32],r9
 mov [rsp+40],r10
 cmp eax,9
 je .map
 cmp eax,11
 je .unmap
 cmp eax,0
 je .read
 cmp eax,1
 je .write
 cmp eax,2
 je .open
 cmp eax,3
 je .close
 cmp eax,8
 je .seek
 cmp eax,16
 je .ioctl
 cmp eax,258
 je .mkdir
 cmp eax,57
 je .fork
 cmp eax,59
 je .execve
 cmp eax,61
 je .waitpid
 cmp eax,60
 je .exit
 mov eax,-38
 jmp .restore
.map:
 mov ecx,0x1002          # Darwin MAP_PRIVATE | MAP_ANON
 call mac_mmap
 jmp .result
.unmap:
 call mac_munmap
 jmp .result
.read:
 call mac_read
 jmp .result
.write:
 call mac_write
 jmp .result
.open:
 test esi,esi
 jz .open_call
 mov esi,0x601           # Darwin O_WRONLY | O_CREAT | O_TRUNC
.open_call:
 call mac_open
 jmp .result
.close:
 call mac_close
 jmp .result
.seek:
 call mac_lseek
 jmp .result
.ioctl:
 mov esi,0x40087468      # Darwin TIOCGWINSZ
 call mac_ioctl
 jmp .result
.mkdir:
 mov rdi,rsi             # mkdirat(AT_FDCWD,path,mode) -> mkdir(path,mode)
 mov rsi,rdx
 call mac_mkdir
 jmp .result
.fork:
 call mac_fork
 jmp .result
.execve:
 call mac_execve
 jmp .result
.waitpid:
 call mac_waitpid
 jmp .result
.exit:
 call mac_exit
 ud2
.result:
 cmp rax,-1
 jne .restore
 call mac_errno
 movsxd rax,dword ptr [rax]
 neg rax
.restore:
 mov rdi,[rsp]
 mov rsi,[rsp+8]
 mov rdx,[rsp+16]
 mov r8,[rsp+24]
 mov r9,[rsp+32]
 mov r10,[rsp+40]
 mov rsp,rbx
 pop rbx
 ret

# LC_MAIN enters with argc/argv/envp in registers, saved by rt_init.
rt_args:
 push rbx
 push r12
 push r13
 mov rdi,[r15+4304]
 dec rdi
 jns .args_count
 xor edi,edi
.args_count:
 call rt_array
 mov rbx,rax
 xor r12d,r12d
.args_loop:
 cmp r12,[rbx]
 jae .args_done
 mov r13,[r15+4312]
 mov r13,[r13+r12*8+8]
 xor esi,esi
.arg_length:
 cmp byte ptr [r13+rsi],0
 je .arg_copy
 inc rsi
 jmp .arg_length
.arg_copy:
 mov rdi,r13
 call rt_string
 mov [rbx+r12*8+8],rax
 inc r12
 jmp .args_loop
.args_done:
 mov rax,rbx
 pop r13
 pop r12
 pop rbx
 ret

rt_exit:
 mov eax,60
 call mac_syscall
 ud2

# The Mach-O writer patches each RIP-relative thunk to its dyld-bound GOT slot.
.macro import name
mac_\name:
 jmp qword ptr [rip+0]
.endm
import mmap
import munmap
import read
import write
import open
import close
import lseek
import ioctl
import mkdir
import fork
import execve
import waitpid
import exit
import errno
