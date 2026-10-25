.intel_syntax noprefix
.text
# Internal runtime ABI: rdi/rsi/rdx inputs, rax result; r14 stack root limit,
# r15 heap state. Runtime helpers preserve rbx/r12/r13/r14/r15 and rbp.
# Allocation header: next, mapping bytes, payload bytes, marked, spare, mark link.
# Strings: byte length + UTF-8 bytes + NUL. Reference and other primitive
# arrays: length + 8-byte slots. Linux byte/int arrays: length + 1/4-byte slots.
# Heap state: head, mapped bytes, threshold, collection page index, index mask,
# index mapping bytes, mark worklist. The temporary index maps every allocation page to its
# header, making conservative membership checks independent of heap size.
# State+56 is a recycled-page list; +4160/+4168 are its bytes/limit (after
# the immutable byte-string table). +4200 holds four small-span class lists;
# +4232 holds their available-span heads. +4264/+4272 track the next and end
# of the current Linux small-span page batch.
# A span page has a 64-byte header: next, reserved, slot size, bump offset,
# free slot, live slots, next available. Small object headers keep mapping bytes zero; a tagged
# index entry points at their span. Cached pages are outside the active heap.
rt_init:
 mov eax,9
 xor edi,edi
 mov esi,8192
 mov edx,3
 mov r10d,0x22
 mov r8,-1
 xor r9d,r9d
 syscall
 cmp rax,-4095
 jae rt_oom
 mov r15,rax
 mov qword ptr [r15+16],1048576
 mov qword ptr [r15+4168],16777216
 # Stable, immutable one-byte strings for indexing. They are runtime constants,
 # outside the managed heap, just like literal strings in the executable.
 lea rdx,[r15+64]
 xor ecx,ecx
.init_char:
 mov qword ptr [rdx],1
 mov [rdx+8],cl
 add rdx,16
 inc ecx
 cmp ecx,256
 jb .init_char
 ret
rt_alloc:
 push rbx
 push r12
 push r13
 push rdi
 push rsi
 push rdx
 push rcx
 push r8
 push r9
 push r10
 push r11
 test rdi,rdi
 js rt_size_error
 cmp rdi,0x3fffffff
 ja rt_size_error
 mov rax,[r15+8]
 cmp rax,[r15+16]
 jb .alloc_choose
 mov rdi,rsp
 call rt_collect
.alloc_choose:
 mov r12,[rsp+56]
 add r12,48
 cmp r12,512
 ja .alloc_map
 lea rbx,[r15+4200]
 mov r12d,64
 cmp qword ptr [rsp+56],16
 jbe .small_find
 mov r12d,128
 add rbx,8
 cmp qword ptr [rsp+56],80
 jbe .small_find
 mov r12d,256
 add rbx,8
 cmp qword ptr [rsp+56],208
 jbe .small_find
 mov r12d,512
 add rbx,8
.small_find:
 mov r13,[rbx+32]
.small_span:
 test r13,r13
 jz .small_map
 mov rdx,[r13+32]
 test rdx,rdx
 jnz .small_reuse
 mov rcx,[r13+24]
 lea r8,[rcx+r12]
 cmp r8,4096
 ja .small_full
 lea rdx,[r13+rcx]
 mov [r13+24],r8
 jmp .small_slot
.small_reuse:
 mov rcx,[rdx]
 mov [r13+32],rcx
 jmp .small_slot
.small_full:
 mov rcx,[r13+48]
 mov [rbx+32],rcx
 mov qword ptr [r13+48],0
 jmp .small_find
.small_map:
 call rt_span_page
 mov r13,rax
 mov rcx,[rbx]
 mov [r13],rcx
 mov [rbx],r13
 mov [r13+16],r12
 mov qword ptr [r13+24],64
 mov rcx,[rbx+32]
 mov [r13+48],rcx
 mov [rbx+32],r13
 add qword ptr [r15+8],4096
 jmp .small_span
.small_slot:
 # Reused slots must be zeroed before array/object/string initialization.
 push rdx
 mov rdi,rdx
 mov rcx,r12
 shr rcx,3
 xor eax,eax
 rep stosq
 pop rdx
 mov rcx,[r15]
 mov [rdx],rcx
 mov [r15],rdx
 mov rcx,[rsp+56]
 mov [rdx+16],rcx
 inc qword ptr [r13+40]
 mov rcx,[r13+32]
 test rcx,rcx
 jnz .small_ready
 mov rcx,[r13+24]
 add rcx,r12
 cmp rcx,4096
 jbe .small_ready
 mov rcx,[r13+48]
 mov [rbx+32],rcx
 mov qword ptr [r13+48],0
.small_ready:
 lea rax,[rdx+48]
 jmp .alloc_return
.alloc_map:
 mov rsi,[rsp+56]
 add rsi,48+4095
 and rsi,-4096
 mov r12,rsi
 cmp rsi,4096
 jne .alloc_syscall
 mov rax,[r15+56]
 test rax,rax
 jz .alloc_syscall
 mov rcx,[rax]
 mov [r15+56],rcx
 sub qword ptr [r15+4160],4096
 mov r13,rax
 mov rdi,rax
 mov ecx,512
 xor eax,eax
 rep stosq
 mov rax,r13
 jmp .alloc_link
.alloc_syscall:
 mov eax,9
 xor edi,edi
 mov edx,3
 mov r10d,0x22
 mov r8,-1
 xor r9d,r9d
 syscall
 cmp rax,-4095
 jae rt_oom
.alloc_link:
 mov rcx,[r15]
 mov [rax],rcx
 mov [rax+8],r12
 mov rcx,[rsp+56]
 mov [rax+16],rcx
 mov [r15],rax
 add [r15+8],r12
 add rax,48
.alloc_return:
 pop r11
 pop r10
 pop r9
 pop r8
 pop rcx
 pop rdx
 pop rsi
 pop rdi
 pop r13
 pop r12
 pop rbx
 ret
rt_span_page:
 # Reserve sixteen contiguous span pages with one Linux mmap. Each page is
 # still indexed and reclaimed independently by the collector.
 mov rax,[r15+4264]
 cmp rax,[r15+4272]
 jb .span_ready
 mov eax,9
 xor edi,edi
 mov esi,65536
 mov edx,3
 mov r10d,0x22
 mov r8,-1
 xor r9d,r9d
 syscall
 cmp rax,-4095
 jae rt_oom
 lea rdx,[rax+65536]
 mov [r15+4272],rdx
.span_ready:
 lea rdx,[rax+4096]
 mov [r15+4264],rdx
 ret
# Mix page addresses before masking: adjacent mmap pages must not form long
# clusters that make scanning zero-filled arrays degenerate into linear searches.
rt_page_hash:
 shr rax,12
 mov rdx,rax
 shr rdx,30
 xor rax,rdx
 mov rcx,0xbf58476d1ce4e5b9
 imul rax,rcx
 mov rdx,rax
 shr rdx,27
 xor rax,rdx
 mov rcx,0x94d049bb133111eb
 imul rax,rcx
 mov rdx,rax
 shr rdx,31
 xor rax,rdx
 ret
# Mark managed and interior pointers conservatively (field/index lvalues are roots).
rt_mark:
 # Nulls, type tags and small scalar fields cannot be mapped managed roots.
 # Skip their hash probes while retaining arbitrary interior heap pointers.
 cmp rdi,4096
 jb .mark_done
 mov rsi,rdi
 and rsi,-4096
 mov rax,rsi
 call rt_page_hash
 mov rcx,rax
.mark_probe:
 and rcx,[r15+32]
 mov rdx,rcx
 shl rdx,4
 add rdx,[r15+24]
 mov rax,[rdx]
 test rax,rax
 jz .mark_done
 cmp rax,rsi
 je .mark_page
 inc rcx
 jmp .mark_probe
.mark_page:
 mov rax,[rdx+8]
 test al,1
 jnz .mark_span
 lea rdx,[rax+48]
 cmp rdi,rdx
 jb .mark_done
 add rdx,[rax+16]
 cmp rdi,rdx
 jae .mark_done
 jmp .mark_found
.mark_span:
 and rax,-2
 lea r8,[rax+64]
 cmp rdi,r8
 jb .mark_done
 mov rcx,rdi
 sub rcx,r8
 mov rdx,[rax+16]
 neg rdx
 and rcx,rdx
 lea rax,[r8+rcx]
 lea rdx,[rax+48]
 cmp rdi,rdx
 jb .mark_done
 add rdx,[rax+16]
 cmp rdi,rdx
 jae .mark_done
.mark_found:
 cmp qword ptr [rax+24],0
 jne .mark_done
 mov qword ptr [rax+24],1
 mov rdx,[r15+48]
 mov [rax+40],rdx
 mov [r15+48],rax
.mark_done:
 ret
rt_collect:
 push rbx
 push r12
 push r13
 mov r12,rdi
 # At most one entry per mapped page, with load factor no greater than 1/2.
 mov rdx,[r15+8]
 shr rdx,11
 mov esi,1
.index_size:
 cmp rsi,rdx
 jae .index_map
 shl rsi,1
 jmp .index_size
.index_map:
 lea rax,[rsi-1]
 mov [r15+32],rax
 shl rsi,4
 mov [r15+40],rsi
 mov eax,9
 xor edi,edi
 mov edx,3
 mov r10d,0x22
 mov r8,-1
 xor r9d,r9d
 syscall
 cmp rax,-4095
 jae rt_oom
 mov [r15+24],rax
 mov rbx,[r15]
.index_allocation:
 test rbx,rbx
 jz .index_spans
 cmp qword ptr [rbx+8],0
 je .index_next
 mov r13,rbx
 mov r8,[rbx+8]
 add r8,rbx
.index_page:
 mov rax,r13
 call rt_page_hash
 mov rcx,rax
.index_probe:
 and rcx,[r15+32]
 mov rdx,rcx
 shl rdx,4
 add rdx,[r15+24]
 cmp qword ptr [rdx],0
 je .index_insert
 inc rcx
 jmp .index_probe
.index_insert:
 mov [rdx],r13
 mov [rdx+8],rbx
 add r13,4096
 cmp r13,r8
 jb .index_page
.index_next:
 mov rbx,[rbx]
 jmp .index_allocation
.index_spans:
 xor r11d,r11d
.index_class:
 cmp r11,4
 jae .index_ready
 mov rbx,[r15+r11*8+4200]
.index_span:
 test rbx,rbx
 jz .index_next_class
 mov rax,rbx
 call rt_page_hash
 mov rcx,rax
.index_span_probe:
 and rcx,[r15+32]
 mov rdx,rcx
 shl rdx,4
 add rdx,[r15+24]
 cmp qword ptr [rdx],0
 je .index_span_insert
 inc rcx
 jmp .index_span_probe
.index_span_insert:
 mov [rdx],rbx
 mov rax,rbx
 or rax,1
 mov [rdx+8],rax
 mov rbx,[rbx]
 jmp .index_span
.index_next_class:
 inc r11
 jmp .index_class
.index_ready:
 mov qword ptr [r15+48],0
 mov rbx,[r15]
.clear_marks:
 test rbx,rbx
 jz .roots
 mov qword ptr [rbx+24],0
 mov qword ptr [rbx+40],0
 mov rbx,[rbx]
 jmp .clear_marks
.roots:
 cmp r12,r14
 jae .trace_start
 mov rdi,[r12]
 call rt_mark
 add r12,8
 jmp .roots
.trace_start:
 # Scan each marked allocation once. A linked worklist in allocation headers
 # avoids rescanning the entire heap once per level of a deep object graph.
 mov rbx,[r15+48]
 test rbx,rbx
 jz .sweep_start
 mov rax,[rbx+40]
 mov [r15+48],rax
 xor r12d,r12d
.scan:
 mov rcx,[rbx+16]
 and rcx,-8
 cmp r12,rcx
 jae .trace_start
 mov rdi,[rbx+r12+48]
 call rt_mark
 add r12,8
 jmp .scan
.sweep_start:
 lea r12,[r15]
 mov qword ptr [r15+8],0
.sweep:
 mov rbx,[r12]
 test rbx,rbx
 jz .collected
 cmp qword ptr [rbx+24],0
 je .free
 mov rax,[rbx+8]
 test rax,rax
 jz .live_small
 add [r15+8],rax
.live_small:
 mov r12,rbx
 jmp .sweep
.free:
 mov rax,[rbx]
 mov [r12],rax
 cmp qword ptr [rbx+8],0
 je .free_small
 cmp qword ptr [rbx+8],4096
 jne .free_mapping
 mov rax,[r15+4160]
 cmp rax,[r15+4168]
 jae .free_mapping
 mov rax,[r15+56]
 mov [rbx],rax
 mov [r15+56],rbx
 add qword ptr [r15+4160],4096
 jmp .sweep
.free_mapping:
 mov rdi,rbx
 mov rsi,[rbx+8]
 mov eax,11
 syscall
 jmp .sweep
.free_small:
 mov rdx,rbx
 and rdx,-4096
 mov rcx,[rdx+32]
 mov [rbx],rcx
 mov [rdx+32],rbx
 mov qword ptr [rbx+16],0
 dec qword ptr [rdx+40]
 jmp .sweep
.collected:
 xor r12d,r12d
.sweep_class:
 cmp r12,4
 jae .spans_collected
 mov qword ptr [r15+r12*8+4232],0
 lea r13,[r15+r12*8+4200]
.sweep_span:
 mov rbx,[r13]
 test rbx,rbx
 jz .sweep_next_class
 cmp qword ptr [rbx+40],0
 jne .keep_span
 mov rax,[rbx]
 mov [r13],rax
 mov rdi,rbx
 mov esi,4096
 mov eax,11
 syscall
 jmp .sweep_span
.keep_span:
 add qword ptr [r15+8],4096
 mov rcx,[rbx+32]
 test rcx,rcx
 jnz .available_span
 mov rcx,[rbx+24]
 add rcx,[rbx+16]
 cmp rcx,4096
 ja .full_span
.available_span:
 mov rcx,[r15+r12*8+4232]
 mov [rbx+48],rcx
 mov [r15+r12*8+4232],rbx
.full_span:
 mov r13,rbx
 jmp .sweep_span
.sweep_next_class:
 inc r12
 jmp .sweep_class
.spans_collected:
 mov rdi,[r15+24]
 mov rsi,[r15+40]
 mov eax,11
 syscall
 mov qword ptr [r15+24],0
 mov rax,[r15+8]
 cmp rax,67108864
 jb .small_heap_budget
 # Keep headroom for the temporary index and limit garbage retained between
 # collections in compiler-sized heaps; small programs retain doubling growth.
 mov rdx,rax
 shr rdx,2
 add rax,rdx
 jmp .budget_ready
.small_heap_budget:
 shl rax,1
.budget_ready:
 cmp rax,1048576
 jae .threshold
 mov eax,1048576
.threshold:
 mov [r15+16],rax
 pop r13
 pop r12
 pop rbx
 xor eax,eax
 ret
rt_heapbytes:
 mov rax,[r15+8]
 ret
rt_release_pool:
 push rbx
 mov rbx,[r15+56]
.pool_release:
 test rbx,rbx
 jz .pool_released
 mov rdi,rbx
 mov rbx,[rbx]
 mov esi,4096
 mov eax,11
 syscall
 jmp .pool_release
.pool_released:
 mov qword ptr [r15+56],0
 mov qword ptr [r15+4160],0
 pop rbx
 ret
rt_gc:
 # Capture volatile registers as roots as well as stack slots.
 push rdi
 push rsi
 push rdx
 push rcx
 push r8
 push r9
 push r10
 push r11
 push rbx
 push r12
 push r13
 call rt_release_pool
 mov qword ptr [r15+4168],0
 mov rdi,rsp
 call rt_collect
 mov qword ptr [r15+4168],16777216
 pop r13
 pop r12
 pop rbx
 pop r11
 pop r10
 pop r9
 pop r8
 pop rcx
 pop rdx
 pop rsi
 pop rdi
 xor eax,eax
 ret
rt_check:
 test rdi,rdi
 jz rt_null_error
 mov rax,rdi
 ret
rt_array:
 test rdi,rdi
 js rt_size_error
 cmp rdi,0x7ffffff
 ja rt_size_error
 push rdi
 lea rdi,[rdi*8+8]
 call rt_alloc
 pop rcx
 mov [rax],rcx
 ret
rt_byte_array:
 test rdi,rdi
 js rt_size_error
 cmp rdi,0x7ffffff
 ja rt_size_error
 push rdi
 lea rdi,[rdi+8]
 call rt_alloc
 pop rcx
 mov [rax],rcx
 ret
rt_int_array:
 test rdi,rdi
 js rt_size_error
 cmp rdi,0x7ffffff
 ja rt_size_error
 push rdi
 lea rdi,[rdi*4+8]
 call rt_alloc
 pop rcx
 mov [rax],rcx
 ret
rt_slice:
 # rdi=source, rsi=start, rdx=exclusive end, rcx=element width;
 # width zero means a byte string. Validate before subtracting or allocating.
 test rdi,rdi
 jz rt_null_error
 test rsi,rsi
 js rt_index_error
 cmp rdx,rsi
 jb rt_index_error
 cmp rdx,[rdi]
 ja rt_index_error
 push rbx
 push r12
 push r13
 push r14
 mov rbx,rdi
 mov r12,rsi
 mov r13,rdx
 sub r13,rsi
 cmp r13,0x7ffffff
 ja rt_size_error
 mov r14,rcx
 test r14,r14
 jnz .slice_array
 lea rdi,[rbx+r12+8]
 mov rsi,r13
 call rt_string
 jmp .slice_done
.slice_array:
 mov rdi,r13
 cmp r14,1
 je .slice_byte
 cmp r14,4
 je .slice_int
 call rt_array
 jmp .slice_copy
.slice_byte:
 call rt_byte_array
 jmp .slice_copy
.slice_int:
 call rt_int_array
.slice_copy:
 mov r8,rax
 lea rsi,[rbx+8]
 mov rcx,r12
 imul rcx,r14
 add rsi,rcx
 lea rdi,[r8+8]
 mov rcx,r13
 imul rcx,r14
 rep movsb
 mov rax,r8
.slice_done:
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
rt_index:
 test rdi,rdi
 jz rt_null_error
 # An unsigned compare rejects negative indexes too.
 cmp rsi,[rdi]
 jae rt_index_error
 lea rax,[rdi+rsi*8+8]
 ret
rt_byte_index:
 test rdi,rdi
 jz rt_null_error
 cmp rsi,[rdi]
 jae rt_index_error
 lea rax,[rdi+rsi+8]
 ret
rt_int_index:
 test rdi,rdi
 jz rt_null_error
 cmp rsi,[rdi]
 jae rt_index_error
 lea rax,[rdi+rsi*4+8]
 ret
rt_string:
 # Clone rsi bytes starting at rdi; allocation cannot collect raw input because
 # callers retain its owning managed pointer on their stack/register roots.
 push rbx
 push r12
 mov rbx,rdi
 mov r12,rsi
 lea rdi,[rsi+9]
 call rt_alloc
 mov [rax],r12
 lea rdi,[rax+8]
 mov rsi,rbx
 mov rcx,r12
 rep movsb
 mov byte ptr [rdi],0
 pop r12
 pop rbx
 ret
rt_string_from_bytes:
 # rdi=byte array, rsi=used byte count. Copy just the used prefix into an
 # immutable string; unsigned comparison also rejects a negative count.
 test rdi,rdi
 jz rt_null_error
 cmp rsi,[rdi]
 ja rt_index_error
 add rdi,8
 jmp rt_string
rt_concat:
 test rdi,rdi
 jz rt_null_error
 test rsi,rsi
 jz rt_null_error
 push rbx
 push r12
 push r13
 mov rbx,rdi
 mov r12,rsi
 mov r13,[rdi]
 add r13,[rsi]
 lea rdi,[r13+9]
 call rt_alloc
 mov [rax],r13
 lea rdi,[rax+8]
 lea rsi,[rbx+8]
 mov rcx,[rbx]
 rep movsb
 lea rsi,[r12+8]
 mov rcx,[r12]
 rep movsb
 mov byte ptr [rdi],0
 pop r13
 pop r12
 pop rbx
 ret
rt_equal:
 cmp rdi,rsi
 je .equal_true
 test rdi,rdi
 jz .equal_false
 test rsi,rsi
 jz .equal_false
 mov rcx,[rdi]
 cmp rcx,[rsi]
 jne .equal_false
 test rcx,rcx
 jz .equal_true
 add rdi,8
 add rsi,8
 repe cmpsb
 jne .equal_false
.equal_true:
 mov eax,1
 ret
.equal_false:
 xor eax,eax
 ret
rt_char:
 test rdi,rdi
 jz rt_null_error
 cmp rsi,[rdi]
 jae rt_index_error
 movzx eax,byte ptr [rdi+rsi+8]
 shl rax,4
 lea rax,[r15+rax+64]
 ret
rt_int_string:
 push rbx
 sub rsp,48
 mov rax,rdi
 xor ebx,ebx
 test rax,rax
 jns .digits
 neg rax
 mov ebx,1
.digits:
 lea rsi,[rsp+47]
 mov byte ptr [rsi],0
 mov r8d,10
 xor ecx,ecx
.digit:
 xor edx,edx
 div r8
 add dl,'0'
 dec rsi
 mov [rsi],dl
 inc rcx
 test rax,rax
 jnz .digit
 test rbx,rbx
 jz .digits_done
 dec rsi
 mov byte ptr [rsi],'-'
 inc rcx
.digits_done:
 mov rdi,rsi
 mov rsi,rcx
 call rt_string
 add rsp,48
 pop rbx
 ret
rt_uint_string:
 sub rsp,48
 mov rax,rdi
 lea rsi,[rsp+47]
 mov byte ptr [rsi],0
 mov r8d,10
 xor ecx,ecx
.uint_digit:
 xor edx,edx
 div r8
 add dl,'0'
 dec rsi
 mov [rsi],dl
 inc rcx
 test rax,rax
 jnz .uint_digit
 mov rdi,rsi
 mov rsi,rcx
 call rt_string
 add rsp,48
 ret
rt_bool_string:
 test rdi,rdi
 jz .false_string
 lea rdi,[rip+.true_bytes]
 mov esi,4
 jmp rt_string
.false_string:
 lea rdi,[rip+.false_bytes]
 mov esi,5
 jmp rt_string
rt_to_int:
 test rdi,rdi
 jz rt_null_error
 mov rcx,[rdi]
 add rdi,8
 xor eax,eax
 mov r8d,1
 test rcx,rcx
 jz rt_convert_error
 cmp byte ptr [rdi],'-'
 jne .parse_digit
 mov r8,-1
 inc rdi
 dec rcx
 jz rt_convert_error
.parse_digit:
 movzx edx,byte ptr [rdi]
 sub edx,'0'
 cmp edx,9
 ja rt_convert_error
 imul rax,rax,10
 add rax,rdx
 mov r9d,2147483648
 cmp rax,r9
 ja rt_convert_error
 inc rdi
 dec rcx
 jnz .parse_digit
 cmp r8,1
 jne .parse_done
 cmp rax,2147483647
 ja rt_convert_error
.parse_done:
 imul rax,r8
 ret
rt_print:
 test rdi,rdi
 jz rt_null_error
 push rbx
 mov rbx,rsi
 mov rdx,[rdi]
 lea rsi,[rdi+8]
 mov edi,1
 call rt_write_all
 test rbx,rbx
 jz .printed
 mov edi,1
 lea rsi,[rip+.newline]
 mov edx,1
 call rt_write_all
.printed:
 pop rbx
 xor eax,eax
 ret
rt_console_bytes:
 test rdi,rdi
 jz rt_null_error
 mov rdx,[rdi]
 lea rsi,[rdi+8]
 mov edi,1
 call rt_write_all
 xor eax,eax
 ret
rt_isatty:
 sub rsp,16
 mov eax,16
 mov edi,1
 mov esi,0x5413
 mov rdx,rsp
 syscall
 add rsp,16
 test rax,rax
 sete al
 movzx eax,al
 ret
rt_terminal_width:
 sub rsp,16
 mov eax,16
 mov edi,1
 mov esi,0x5413
 mov rdx,rsp
 syscall
 test rax,rax
 js .unknown_width
 movzx eax,word ptr [rsp+2]
 add rsp,16
 ret
.unknown_width:
 xor eax,eax
 add rsp,16
 ret
rt_string_byte_at:
 test rdi,rdi
 jz rt_null_error
 test rsi,rsi
 js rt_index_error
 cmp rsi,[rdi]
 jae rt_index_error
 movzx eax,byte ptr [rdi+rsi+8]
 ret
rt_write_all:
 test rdx,rdx
 jz .written
 mov eax,1
 syscall
 cmp rax,-4
 je rt_write_all
 test rax,rax
 jle rt_io_error
 add rsi,rax
 sub rdx,rax
 jmp rt_write_all
.written:
 ret
rt_read_all:
 test rdx,rdx
 jz .read
 xor eax,eax
 syscall
 cmp rax,-4
 je rt_read_all
 test rax,rax
 jle rt_io_error
 add rsi,rax
 sub rdx,rax
 jmp rt_read_all
.read:
 ret
rt_exists:
 test rdi,rdi
 jz rt_null_error
 add rdi,8
 xor esi,esi
 xor edx,edx
 mov eax,2
 syscall
 test rax,rax
 js .not_exists
 mov rdi,rax
 mov eax,3
 syscall
 mov eax,1
 ret
.not_exists:
 xor eax,eax
 ret
rt_read_text:
 test rdi,rdi
 jz rt_null_error
 push rbx
 push r12
 push r13
 add rdi,8
 xor esi,esi
 xor edx,edx
 mov eax,2
 syscall
 test rax,rax
 js rt_io_error
 mov rbx,rax
 mov rdi,rbx
 xor esi,esi
 mov edx,2
 mov eax,8
 syscall
 test rax,rax
 js rt_io_error
 cmp rax,0x1000000
 ja rt_size_error
 mov r12,rax
 mov rdi,rbx
 xor esi,esi
 xor edx,edx
 mov eax,8
 syscall
 test rax,rax
 js rt_io_error
 lea rdi,[r12+9]
 call rt_alloc
 mov r13,rax
 mov [rax],r12
 lea rsi,[rax+8]
 mov rdx,r12
 mov rdi,rbx
 call rt_read_all
.check_extra:
 mov rdi,rbx
 lea rsi,[r13+r12+8]
 mov edx,1
 xor eax,eax
 syscall
 cmp rax,-4
 je .check_extra
 test rax,rax
 jne rt_io_error
 mov rdi,rbx
 mov eax,3
 syscall
 test rax,rax
 js rt_io_error
 mov byte ptr [r13+r12+8],0
 mov rax,r13
 pop r13
 pop r12
 pop rbx
 ret
rt_read_bytes:
 test rdi,rdi
 jz rt_null_error
 push rbx
 push r12
 push r13
 add rdi,8
 xor esi,esi
 xor edx,edx
 mov eax,2
 syscall
 test rax,rax
 js rt_io_error
 mov rbx,rax
 mov rdi,rbx
 xor esi,esi
 mov edx,2
 mov eax,8
 syscall
 test rax,rax
 js rt_io_error
 cmp rax,0x7ffffff
 ja rt_size_error
 mov r12,rax
 mov rdi,rbx
 xor esi,esi
 xor edx,edx
 mov eax,8
 syscall
 test rax,rax
 js rt_io_error
 mov rdi,r12
 call rt_byte_array
 mov r13,rax
 lea rsi,[rax+8]
 mov rdx,r12
 mov rdi,rbx
 call rt_read_all
 mov rdi,rbx
 mov eax,3
 syscall
 test rax,rax
 js rt_io_error
 mov rax,r13
 pop r13
 pop r12
 pop rbx
 ret
rt_write_text:
 test rdi,rdi
 jz rt_null_error
 test rsi,rsi
 jz rt_null_error
 push rbx
 push r12
 push r13
 mov r13,rdi
 mov r12,rsi
 call rt_create_parents
 mov rdi,r13
 add rdi,8
 mov esi,0x241
 mov edx,420
 mov eax,2
 syscall
 test rax,rax
 js rt_io_error
 mov rbx,rax
 mov rdi,rax
 lea rsi,[r12+8]
 mov rdx,[r12]
 call rt_write_all
 mov rdi,rbx
 mov eax,3
 syscall
 test rax,rax
 js rt_io_error
 pop r13
 pop r12
 pop rbx
 xor eax,eax
 ret
rt_write_bytes:
 test rdi,rdi
 jz rt_null_error
 test rsi,rsi
 jz rt_null_error
 push rbx
 push r12
 push r13
 mov r13,rdi
 mov r12,rsi
 call rt_create_parents
 lea rdi,[r13+8]
 mov esi,0x241
 mov edx,420
 mov eax,2
 syscall
 test rax,rax
 js rt_io_error
 mov rbx,rax
 mov rdi,rbx
 lea rsi,[r12+8]
 mov rdx,[r12]
 call rt_write_all
 mov rdi,rbx
 mov eax,3
 syscall
 test rax,rax
 js rt_io_error
 pop r13
 pop r12
 pop rbx
 xor eax,eax
 ret
rt_create_parents:
 test rdi,rdi
 jz rt_null_error
 push rbx
 push r12
 push r13
 mov rbx,rdi
 mov r12,[rdi]
 test r12,r12
 jz rt_io_error
 add rbx,8
 xor r13d,r13d
.mkdir_parts:
 cmp r13,r12
 jae .mkdir_done
 cmp byte ptr [rbx+r13],47
 jne .mkdir_next
 test r13,r13
 jz .mkdir_next
 mov byte ptr [rbx+r13],0
 mov edi,-100
 mov rsi,rbx
 mov edx,493
 mov eax,258
 syscall
 mov byte ptr [rbx+r13],47
 test rax,rax
 jz .mkdir_next
 cmp rax,-17
 jne rt_io_error
.mkdir_next:
 inc r13
 jmp .mkdir_parts
.mkdir_done:
 pop r13
 pop r12
 pop rbx
 xor eax,eax
 ret
rt_args:
 push rbx
 push r12
 push r13
 mov rdi,[r14]
 dec rdi
 call rt_array
 mov rbx,rax
 xor r12d,r12d
.args_loop:
 cmp r12,[rbx]
 jae .args_done
 mov r13,[r14+r12*8+16]
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
rt_null_error:
 lea rsi,[rip+.null_message]
 mov edx,.null_end-.null_message
 jmp rt_error
rt_index_error:
 lea rsi,[rip+.index_message]
 mov edx,.index_end-.index_message
 jmp rt_error
rt_size_error:
 lea rsi,[rip+.size_message]
 mov edx,.size_end-.size_message
 jmp rt_error
rt_oom:
 lea rsi,[rip+.oom_message]
 mov edx,.oom_end-.oom_message
 jmp rt_error
rt_io_error:
 lea rsi,[rip+.io_message]
 mov edx,.io_end-.io_message
 jmp rt_error
rt_convert_error:
 lea rsi,[rip+.convert_message]
 mov edx,.convert_end-.convert_message
rt_error:
 mov edi,2
 mov eax,1
 syscall
 mov edi,1
 mov eax,60
 syscall
 ud2
.newline: .ascii "\n"
.true_bytes: .ascii "true"
.false_bytes: .ascii "false"
.null_message: .ascii "runtime error: null reference\n"
.null_end:
.index_message: .ascii "runtime error: index out of range\n"
.index_end:
.size_message: .ascii "runtime error: invalid allocation size\n"
.size_end:
.oom_message: .ascii "runtime error: allocation failed\n"
.oom_end:
.io_message: .ascii "runtime error: file I/O failed\n"
.io_end:
.convert_message: .ascii "runtime error: invalid integer string\n"
.convert_end:
