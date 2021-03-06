; RUN: llc < %s -march=x86 -asm-verbose=false                           | FileCheck %s -check-prefix=FP-ELIM
; RUN: llc < %s -march=x86 -asm-verbose=false -disable-fp-elim          | FileCheck %s -check-prefix=NO-ELIM

; Implement -momit-leaf-frame-pointer
; rdar://7886181

define i32 @t1() "no-frame-pointer-elim-non-leaf"="false" nounwind readnone {
entry:
; FP-ELIM-LABEL:  t1:
; FP-ELIM-NEXT:     movl
; FP-ELIM-NEXT:     ret

; NO-ELIM-LABEL:  t1:
; NO-ELIM-NEXT:     pushl %ebp
; NO-ELIM:          popl %ebp
; NO-ELIM-NEXT:     ret
  ret i32 10
}

define void @t2() "no-frame-pointer-elim-non-leaf"="false" nounwind {
entry:
; FP-ELIM-LABEL:  t2:
; FP-ELIM-NOT:      pushl %ebp
; FP-ELIM:          ret

; NO-ELIM-LABEL:  t2:
; NO-ELIM-NEXT:     pushl %ebp
; NO-ELIM:          popl %ebp
; NO-ELIM-NEXT:     ret
  tail call void @foo(i32 0) nounwind
  ret void
}

define i32 @t3() "no-frame-pointer-elim-non-leaf"="true" nounwind readnone {
entry:
; FP-ELIM-LABEL:  t3:
; FP-ELIM-NEXT:     movl
; FP-ELIM-NEXT:     ret

; NO-ELIM-LABEL:  t3:
; NO-ELIM-NEXT:     pushl %ebp
; NO-ELIM:          popl %ebp
; NO-ELIM-NEXT:     ret
  ret i32 10
}

define void @t4() "no-frame-pointer-elim-non-leaf"="true" nounwind {
entry:
; FP-ELIM-LABEL:  t4:
; FP-ELIM-NEXT:     pushl %ebp
; FP-ELIM:          popl %ebp
; FP-ELIM-NEXT:     ret

; NO-ELIM-LABEL:  t4:
; NO-ELIM-NEXT:     pushl %ebp
; NO-ELIM:          popl %ebp
; NO-ELIM-NEXT:     ret
  tail call void @foo(i32 0) nounwind
  ret void
}

declare void @foo(i32)
