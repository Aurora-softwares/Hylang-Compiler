# Windows platform layer for the SysV-like Hydrogen runtime ABI. The shared
# runtime calls win_syscall with Linux-shaped arguments; this layer maps only
# the calls it uses to documented Win32 APIs. Imported thunks are patched by
# WindowsImageBuilder to the PE import address table.
.intel_syntax noprefix
.text
win_syscall:
 mov r11,rsp
 and rsp,-16
 sub rsp,176
 mov [rsp+160],r11
 mov [rsp+64],rbx
 mov [rsp+72],rdi
 mov [rsp+80],rsi
 mov [rsp+88],rdx
 mov [rsp+96],r8
 mov [rsp+104],r9
 mov [rsp+112],r10
 mov ebx,eax
 cmp ebx,9
 je .map
 cmp ebx,11
 je .unmap
 cmp ebx,1
 je .write
 test ebx,ebx
 jz .read
 cmp ebx,2
 je .open
 cmp ebx,3
 je .close
 cmp ebx,8
 je .seek
 cmp ebx,16
 je .isatty
 cmp ebx,258
 je .mkdir
 cmp ebx,60
 je .exit
 mov rax,-38
 jmp .done
.map:
 xor ecx,ecx
 mov rdx,[rsp+80]
 mov r8d,0x3000
 mov r9d,4
 call win_VirtualAlloc
 test rax,rax
 jnz .done
 mov rax,-12
 jmp .done
.unmap:
 mov rcx,[rsp+72]
 xor edx,edx
 mov r8d,0x8000
 call win_VirtualFree
 test eax,eax
 mov eax,0
 jnz .done
 mov rax,-5
 jmp .done
.write:
 mov rcx,[rsp+72]
 cmp rcx,1
 je .stdout
 cmp rcx,2
 je .stderr
 jmp .write_handle
.stdout:
 mov ecx,-11
 call win_GetStdHandle
 mov rcx,rax
 jmp .write_handle
.stderr:
 mov ecx,-12
 call win_GetStdHandle
 mov rcx,rax
.write_handle:
 mov rdx,[rsp+80]
 mov r8,[rsp+88]
 cmp r8,0x7fffffff
 ja .bad_io
 lea r9,[rsp+120]
 mov qword ptr [rsp+32],0
 call win_WriteFile
 test eax,eax
 jz .bad_io
 mov eax,[rsp+120]
 jmp .done
.read:
 mov rcx,[rsp+72]
 test rcx,rcx
 jne .read_handle
 mov ecx,-10
 call win_GetStdHandle
 mov rcx,rax
.read_handle:
 mov rdx,[rsp+80]
 mov r8,[rsp+88]
 cmp r8,0x7fffffff
 ja .bad_io
 lea r9,[rsp+120]
 mov qword ptr [rsp+32],0
 call win_ReadFile
 test eax,eax
 jz .bad_io
 mov eax,[rsp+120]
 jmp .done
.open:
 mov rdi,[rsp+72]
 call win_utf8_to_wide
 test rax,rax
 jz .bad_io
 mov [rsp+128],rax
 mov rcx,rax
 cmp qword ptr [rsp+80],0
 jne .open_write
 mov edx,0x80000000
 mov qword ptr [rsp+32],3
 jmp .open_call
.open_write:
 mov edx,0x40000000
 mov qword ptr [rsp+32],2
.open_call:
 mov r8d,3
 xor r9d,r9d
 mov qword ptr [rsp+40],0x80
 mov qword ptr [rsp+48],0
 call win_CreateFileW
 mov [rsp+136],rax
 mov rcx,[rsp+128]
 xor edx,edx
 mov r8d,0x8000
 call win_VirtualFree
 mov rax,[rsp+136]
 cmp rax,-1
 jne .done
 mov rax,-2
 jmp .done
.close:
 mov rcx,[rsp+72]
 call win_CloseHandle
 test eax,eax
 mov eax,0
 jnz .done
 mov rax,-5
 jmp .done
.seek:
 mov rcx,[rsp+72]
 mov rdx,[rsp+80]
 lea r8,[rsp+120]
 mov r9,[rsp+88]
 call win_SetFilePointerEx
 test eax,eax
 jz .bad_io
 mov rax,[rsp+120]
 jmp .done
.isatty:
 mov ecx,-11
 call win_GetStdHandle
 mov [rsp+152],rax
 mov rcx,rax
 lea rdx,[rsp+120]
 call win_GetConsoleMode
 test eax,eax
 jz .not_console
 mov rdx,[rsp+88]
 mov word ptr [rdx+2],0
 mov rcx,[rsp+152]
 lea rdx,[rsp+120]
 call win_GetConsoleScreenBufferInfo
 test eax,eax
 jz .console_ok
 movsx eax,word ptr [rsp+134]
 movsx edx,word ptr [rsp+130]
 sub eax,edx
 inc eax
 test eax,eax
 jle .console_ok
 mov rdx,[rsp+88]
 mov [rdx+2],ax
.console_ok:
 xor eax,eax
 jmp .done
.not_console:
 mov rax,-25
 jmp .done
.mkdir:
 mov rdi,[rsp+80]
 call win_utf8_to_wide
 test rax,rax
 jz .bad_io
 mov [rsp+128],rax
 mov rcx,rax
 xor edx,edx
 call win_CreateDirectoryW
 mov [rsp+136],rax
 test eax,eax
 jnz .mkdir_free
 call win_GetLastError
 mov [rsp+144],rax
.mkdir_free:
 mov rcx,[rsp+128]
 xor edx,edx
 mov r8d,0x8000
 call win_VirtualFree
 mov rax,[rsp+136]
 test eax,eax
 mov eax,0
 jnz .done
 mov rax,[rsp+144]
 cmp eax,183
 je .already_exists
 jmp .bad_io
.already_exists:
 mov rax,-17
 jmp .done
.exit:
 mov rcx,[rsp+72]
 call win_ExitProcess
 ud2
.bad_io:
 mov rax,-5
.done:
 mov rbx,[rsp+64]
 mov rdi,[rsp+72]
 mov rsi,[rsp+80]
 mov rdx,[rsp+88]
 mov r8,[rsp+96]
 mov r9,[rsp+104]
 mov r10,[rsp+112]
 mov rsp,[rsp+160]
 ret

# Convert a NUL-terminated Hydrogen UTF-8 path to a temporary UTF-16 buffer.
# Invalid UTF-8 and allocation failure return zero. Caller releases with
# VirtualFree(ptr, 0, MEM_RELEASE).
win_utf8_to_wide:
 push rbx
 push r12
 push r13
 sub rsp,48
 mov r12,rdi
 mov ecx,65001
 mov edx,8
 mov r8,r12
 mov r9d,-1
 mov qword ptr [rsp+32],0
 mov qword ptr [rsp+40],0
 call win_MultiByteToWideChar
 test eax,eax
 jle .path_fail
 cmp eax,32767
 ja .path_fail
 mov ebx,eax
 xor ecx,ecx
 lea edx,[rbx*2]
 mov r8d,0x3000
 mov r9d,4
 call win_VirtualAlloc
 test rax,rax
 jz .path_fail
 mov r13,rax
 mov ecx,65001
 mov edx,8
 mov r8,r12
 mov r9d,-1
 mov [rsp+32],r13
 mov [rsp+40],rbx
 call win_MultiByteToWideChar
 test eax,eax
 jg .path_done
 mov rcx,r13
 xor edx,edx
 mov r8d,0x8000
 call win_VirtualFree
.path_fail:
 xor eax,eax
 jmp .path_return
.path_done:
 mov rax,r13
.path_return:
 add rsp,48
 pop r13
 pop r12
 pop rbx
 ret

# The compiler sets r14 to the entry stack for conservative GC. Build the
# managed string[] directly from the Windows Unicode command line, excluding
# argv[0], using the platform's quoting rules and UTF-8 conversion.
rt_args:
 push rbx
 push r12
 push r13
 push rbp
 sub rsp,40
 call win_GetCommandLineW
 mov rcx,rax
 lea rdx,[rsp+32]
 call win_CommandLineToArgvW
 test rax,rax
 jz rt_oom
 mov r12,rax
 mov ebp,[rsp+32]
 lea rdi,[rbp-1]
 call rt_array
 mov rbx,rax
 mov r13,1
.args_next:
 cmp r13,rbp
 jae .args_done
 mov rcx,65001
 xor edx,edx
 mov r8,[r12+r13*8]
 mov r9d,-1
 sub rsp,64
 mov qword ptr [rsp+32],0
 mov qword ptr [rsp+40],0
 mov qword ptr [rsp+48],0
 mov qword ptr [rsp+56],0
 call win_WideCharToMultiByte
 add rsp,64
 test eax,eax
 jle rt_convert_error
 mov ebp,eax
 lea rdi,[rbp+8]
 call rt_alloc
 mov [rsp+16],rax
 lea rdx,[rbp-1]
 mov [rax],rdx
 mov rcx,65001
 xor edx,edx
 mov r8,[r12+r13*8]
 mov r9d,-1
 sub rsp,64
 mov rax,[rsp+80]
 lea rax,[rax+8]
 mov [rsp+32],rax
 mov [rsp+40],rbp
 mov qword ptr [rsp+48],0
 mov qword ptr [rsp+56],0
 call win_WideCharToMultiByte
 add rsp,64
 test eax,eax
 jle rt_convert_error
 mov rax,[rsp+16]
 mov [rbx+r13*8],rax
 # Recover argc, saved at [rsp] by CommandLineToArgvW.
 mov ebp,[rsp+32]
 inc r13
 jmp .args_next
.args_done:
 mov rcx,r12
 call win_LocalFree
 mov rax,rbx
 add rsp,40
 pop rbp
 pop r13
 pop r12
 pop rbx
 ret

# Each thunk is a RIP-relative indirect jump. The PE writer patches its disp32
# to the corresponding IAT slot, so the image needs no absolute relocations.
.macro import name
win_\name:
 .byte 0xff,0x25
 .long 0
.endm
import VirtualAlloc
import VirtualFree
import GetStdHandle
import WriteFile
import ReadFile
import CreateFileW
import CloseHandle
import SetFilePointerEx
import GetConsoleMode
import GetConsoleScreenBufferInfo
import CreateDirectoryW
import GetLastError
import ExitProcess
import GetCommandLineW
import CommandLineToArgvW
import WideCharToMultiByte
import LocalFree
import MultiByteToWideChar
