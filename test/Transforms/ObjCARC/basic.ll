; RUN: opt -objc-arc -S < %s | FileCheck %s

target datalayout = "e-p:64:64:64"

declare i8* @objc_retain(i8*)
declare void @objc_release(i8*)
declare i8* @objc_autorelease(i8*)
declare void @objc_autoreleasePoolPop(i8*)
declare void @objc_autoreleasePoolPush()
declare i8* @objc_retainBlock(i8*)

declare i8* @objc_retainedObject(i8*)
declare i8* @objc_unretainedObject(i8*)
declare i8* @objc_unretainedPointer(i8*)

declare void @use_pointer(i8*)
declare void @callee()
declare void @callee_fnptr(void ()*)
declare void @invokee()
declare i8* @returner()

declare void @llvm.dbg.value(metadata, i64, metadata)

declare i8* @objc_msgSend(i8*, i8*, ...)

; Simple retain+release pair deletion, with some intervening control
; flow and harmless instructions.

; CHECK: define void @test0(
; CHECK-NOT: @objc_
; CHECK: }
define void @test0(i32* %x, i1 %p) nounwind {
entry:
  %a = bitcast i32* %x to i8*
  %0 = call i8* @objc_retain(i8* %a) nounwind
  br i1 %p, label %t, label %f

t:
  store i8 3, i8* %a
  %b = bitcast i32* %x to float*
  store float 2.0, float* %b
  br label %return

f:
  store i32 7, i32* %x
  br label %return

return:
  %c = bitcast i32* %x to i8*
  call void @objc_release(i8* %c) nounwind
  ret void
}

; Like test0 but the release isn't always executed when the retain is,
; so the optimization is not safe.

; TODO: Make the objc_release's argument be %0.

; CHECK: define void @test1(
; CHECK: @objc_retain(i8* %a)
; CHECK: @objc_release
; CHECK: }
define void @test1(i32* %x, i1 %p, i1 %q) nounwind {
entry:
  %a = bitcast i32* %x to i8*
  %0 = call i8* @objc_retain(i8* %a) nounwind
  br i1 %p, label %t, label %f

t:
  store i8 3, i8* %a
  %b = bitcast i32* %x to float*
  store float 2.0, float* %b
  br label %return

f:
  store i32 7, i32* %x
  call void @callee()
  br i1 %q, label %return, label %alt_return

return:
  %c = bitcast i32* %x to i8*
  call void @objc_release(i8* %c) nounwind
  ret void

alt_return:
  ret void
}

; Like test0 but the pointer is passed to an intervening call,
; so the optimization is not safe.

; CHECK: define void @test2(
; CHECK: @objc_retain(i8* %a)
; CHECK: @objc_release
; CHECK: }
define void @test2(i32* %x, i1 %p) nounwind {
entry:
  %a = bitcast i32* %x to i8*
  %0 = call i8* @objc_retain(i8* %a) nounwind
  br i1 %p, label %t, label %f

t:
  store i8 3, i8* %a
  %b = bitcast i32* %x to float*
  store float 2.0, float* %b
  br label %return

f:
  store i32 7, i32* %x
  call void @use_pointer(i8* %0)
  %d = bitcast i32* %x to float*
  store float 3.0, float* %d
  br label %return

return:
  %c = bitcast i32* %x to i8*
  call void @objc_release(i8* %c) nounwind
  ret void
}

; Like test0 but the release is in a loop,
; so the optimization is not safe.

; TODO: For now, assume this can't happen.

; CHECK: define void @test3(
; TODO: @objc_retain(i8* %a)
; TODO: @objc_release
; CHECK: }
define void @test3(i32* %x, i1* %q) nounwind {
entry:
  %a = bitcast i32* %x to i8*
  %0 = call i8* @objc_retain(i8* %a) nounwind
  br label %loop

loop:
  %c = bitcast i32* %x to i8*
  call void @objc_release(i8* %c) nounwind
  %j = volatile load i1* %q
  br i1 %j, label %loop, label %return

return:
  ret void
}

; TODO: For now, assume this can't happen.

; Like test0 but the retain is in a loop,
; so the optimization is not safe.

; CHECK: define void @test4(
; TODO: @objc_retain(i8* %a)
; TODO: @objc_release
; CHECK: }
define void @test4(i32* %x, i1* %q) nounwind {
entry:
  br label %loop

loop:
  %a = bitcast i32* %x to i8*
  %0 = call i8* @objc_retain(i8* %a) nounwind
  %j = volatile load i1* %q
  br i1 %j, label %loop, label %return

return:
  %c = bitcast i32* %x to i8*
  call void @objc_release(i8* %c) nounwind
  ret void
}

; Like test0 but the pointer is conditionally passed to an intervening call,
; so the optimization is not safe.

; CHECK: define void @test5(
; CHECK: @objc_retain(i8*
; CHECK: @objc_release
; CHECK: }
define void @test5(i32* %x, i1 %q, i8* %y) nounwind {
entry:
  %a = bitcast i32* %x to i8*
  %0 = call i8* @objc_retain(i8* %a) nounwind
  %s = select i1 %q, i8* %y, i8* %0
  call void @use_pointer(i8* %s)
  store i32 7, i32* %x
  %c = bitcast i32* %x to i8*
  call void @objc_release(i8* %c) nounwind
  ret void
}

; retain+release pair deletion, where the release happens on two different
; flow paths.

; CHECK: define void @test6(
; CHECK-NOT: @objc_
; CHECK: }
define void @test6(i32* %x, i1 %p) nounwind {
entry:
  %a = bitcast i32* %x to i8*
  %0 = call i8* @objc_retain(i8* %a) nounwind
  br i1 %p, label %t, label %f

t:
  store i8 3, i8* %a
  %b = bitcast i32* %x to float*
  store float 2.0, float* %b
  %ct = bitcast i32* %x to i8*
  call void @objc_release(i8* %ct) nounwind
  br label %return

f:
  store i32 7, i32* %x
  call void @callee()
  %cf = bitcast i32* %x to i8*
  call void @objc_release(i8* %cf) nounwind
  br label %return

return:
  ret void
}

; retain+release pair deletion, where the retain happens on two different
; flow paths.

; CHECK: define void @test7(
; CHECK-NOT: @objc_
; CHECK: }
define void @test7(i32* %x, i1 %p) nounwind {
entry:
  %a = bitcast i32* %x to i8*
  br i1 %p, label %t, label %f

t:
  %0 = call i8* @objc_retain(i8* %a) nounwind
  store i8 3, i8* %a
  %b = bitcast i32* %x to float*
  store float 2.0, float* %b
  br label %return

f:
  %1 = call i8* @objc_retain(i8* %a) nounwind
  store i32 7, i32* %x
  call void @callee()
  br label %return

return:
  %c = bitcast i32* %x to i8*
  call void @objc_release(i8* %c) nounwind
  ret void
}

; Like test7, but there's a retain/retainBlock mismatch. Don't delete!

; CHECK: define void @test7b
; CHECK: t:
; CHECK: call i8* @objc_retainBlock
; CHECK: f:
; CHECK: call i8* @objc_retain
; CHECK: return:
; CHECK: call void @objc_release
; CHECK: }
define void @test7b(i32* %x, i1 %p) nounwind {
entry:
  %a = bitcast i32* %x to i8*
  br i1 %p, label %t, label %f

t:
  %0 = call i8* @objc_retainBlock(i8* %a) nounwind
  store i8 3, i8* %a
  %b = bitcast i32* %x to float*
  store float 2.0, float* %b
  br label %return

f:
  %1 = call i8* @objc_retain(i8* %a) nounwind
  store i32 7, i32* %x
  call void @callee()
  br label %return

return:
  %c = bitcast i32* %x to i8*
  call void @objc_release(i8* %c) nounwind
  ret void
}

; retain+release pair deletion, where the retain and release both happen on
; different flow paths. Wild!

; CHECK: define void @test8(
; CHECK-NOT: @objc_
; CHECK: }
define void @test8(i32* %x, i1 %p, i1 %q) nounwind {
entry:
  %a = bitcast i32* %x to i8*
  br i1 %p, label %t, label %f

t:
  %0 = call i8* @objc_retain(i8* %a) nounwind
  store i8 3, i8* %a
  %b = bitcast i32* %x to float*
  store float 2.0, float* %b
  br label %mid

f:
  %1 = call i8* @objc_retain(i8* %a) nounwind
  store i32 7, i32* %x
  br label %mid

mid:
  br i1 %q, label %u, label %g

u:
  call void @callee()
  %cu = bitcast i32* %x to i8*
  call void @objc_release(i8* %cu) nounwind
  br label %return

g:
  %cg = bitcast i32* %x to i8*
  call void @objc_release(i8* %cg) nounwind
  br label %return

return:
  ret void
}

; Trivial retain+release pair deletion.

; CHECK: define void @test9(
; CHECK-NOT: @objc_
; CHECK: }
define void @test9(i8* %x) nounwind {
entry:
  %0 = call i8* @objc_retain(i8* %x) nounwind
  call void @objc_release(i8* %0) nounwind
  ret void
}

; Retain+release pair, but on an unknown pointer relationship. Don't delete!

; CHECK: define void @test9b
; CHECK: @objc_retain(i8* %x)
; CHECK: @objc_release(i8* %s)
; CHECK: }
define void @test9b(i8* %x, i1 %j, i8* %p) nounwind {
entry:
  %0 = call i8* @objc_retain(i8* %x) nounwind
  %s = select i1 %j, i8* %x, i8* %p
  call void @objc_release(i8* %s) nounwind
  ret void
}

; Trivial retain+release pair with intervening calls - don't delete!

; CHECK: define void @test10(
; CHECK: @objc_retain(i8* %x)
; CHECK: @use_pointer
; CHECK: @objc_release
; CHECK: }
define void @test10(i8* %x) nounwind {
entry:
  %0 = call i8* @objc_retain(i8* %x) nounwind
  call void @use_pointer(i8* %x)
  call void @use_pointer(i8* %x)
  call void @objc_release(i8* %0) nounwind
  ret void
}

; Trivial retain+autoreleaserelease pair. Don't delete!
; Also, add a tail keyword, since objc_retain can never be passed
; a stack argument.

; CHECK: define void @test11(
; CHECK: tail call i8* @objc_retain(i8* %x) nounwind
; CHECK: tail call i8* @objc_autorelease(i8* %0) nounwind
; CHECK: }
define void @test11(i8* %x) nounwind {
entry:
  %0 = call i8* @objc_retain(i8* %x) nounwind
  call i8* @objc_autorelease(i8* %0) nounwind
  call void @use_pointer(i8* %x)
  ret void
}

; Same as test11 but with no use_pointer call. Delete the pair!

; CHECK: define void @test11a(
; CHECK: entry:
; CHECK-NEXT: ret void
; CHECK: }
define void @test11a(i8* %x) nounwind {
entry:
  %0 = call i8* @objc_retain(i8* %x) nounwind
  call i8* @objc_autorelease(i8* %0) nounwind
  ret void
}

; Same as test11 but the value is returned. Do an RV optimization.

; CHECK: define i8* @test11b(
; CHECK: tail call i8* @objc_retain(i8* %x) nounwind
; CHECK: tail call i8* @objc_autoreleaseReturnValue(i8* %0) nounwind
; CHECK: }
define i8* @test11b(i8* %x) nounwind {
entry:
  %0 = call i8* @objc_retain(i8* %x) nounwind
  call i8* @objc_autorelease(i8* %0) nounwind
  ret i8* %x
}

; Trivial retain,release pair with intervening call, but it's dominated
; by another retain - delete!

; CHECK: define void @test12(
; CHECK-NEXT: entry:
; CHECK-NEXT: @objc_retain(i8* %x)
; CHECK-NOT: @objc_
; CHECK: }
define void @test12(i8* %x, i64 %n) {
entry:
  call i8* @objc_retain(i8* %x) nounwind
  call i8* @objc_retain(i8* %x) nounwind
  call void @use_pointer(i8* %x)
  call void @use_pointer(i8* %x)
  call void @objc_release(i8* %x) nounwind
  ret void
}

; Trivial retain,autorelease pair. Don't delete!

; CHECK: define void @test13(
; CHECK: tail call i8* @objc_retain(i8* %x) nounwind
; CHECK: tail call i8* @objc_retain(i8* %x) nounwind
; CHECK: @use_pointer(i8* %x)
; CHECK: tail call i8* @objc_autorelease(i8* %x) nounwind
; CHECK: }
define void @test13(i8* %x, i64 %n) {
entry:
  call i8* @objc_retain(i8* %x) nounwind
  call i8* @objc_retain(i8* %x) nounwind
  call void @use_pointer(i8* %x)
  call i8* @objc_autorelease(i8* %x) nounwind
  ret void
}

; Delete the retain+release pair.

; CHECK: define void @test13b
; CHECK-NEXT: entry:
; CHECK-NEXT: @objc_retain(i8* %x)
; CHECK-NEXT: @use_pointer
; CHECK-NEXT: @use_pointer
; CHECK-NEXT: ret void
define void @test13b(i8* %x, i64 %n) {
entry:
  call i8* @objc_retain(i8* %x) nounwind
  call i8* @objc_retain(i8* %x) nounwind
  call void @use_pointer(i8* %x)
  call void @use_pointer(i8* %x)
  call void @objc_release(i8* %x) nounwind
  ret void
}

; Don't delete the retain+release pair because there's an
; autoreleasePoolPop in the way.

; CHECK: define void @test13c
; CHECK: @objc_retain(i8* %x)
; CHECK: @objc_autoreleasePoolPop
; CHECK: @objc_retain(i8* %x)
; CHECK: @use_pointer
; CHECK: @objc_release
; CHECK: }
define void @test13c(i8* %x, i64 %n) {
entry:
  call i8* @objc_retain(i8* %x) nounwind
  call void @objc_autoreleasePoolPop(i8* undef)
  call i8* @objc_retain(i8* %x) nounwind
  call void @use_pointer(i8* %x)
  call void @use_pointer(i8* %x)
  call void @objc_release(i8* %x) nounwind
  ret void
}

; Like test13c, but there's an autoreleasePoolPush in the way, but that
; doesn't matter.

; CHECK: define void @test13d
; CHECK-NEXT: entry:
; CHECK-NEXT: @objc_retain(i8* %x)
; CHECK-NEXT: @objc_autoreleasePoolPush
; CHECK-NEXT: @use_pointer
; CHECK-NEXT: @use_pointer
; CHECK-NEXT: ret void
define void @test13d(i8* %x, i64 %n) {
entry:
  call i8* @objc_retain(i8* %x) nounwind
  call void @objc_autoreleasePoolPush()
  call i8* @objc_retain(i8* %x) nounwind
  call void @use_pointer(i8* %x)
  call void @use_pointer(i8* %x)
  call void @objc_release(i8* %x) nounwind
  ret void
}

; Trivial retain,release pair with intervening call, but it's post-dominated
; by another release - delete!

; CHECK: define void @test14(
; CHECK-NEXT: entry:
; CHECK-NEXT: @use_pointer
; CHECK-NEXT: @use_pointer
; CHECK-NEXT: @objc_release
; CHECK-NEXT: ret void
; CHECK-NEXT: }
define void @test14(i8* %x, i64 %n) {
entry:
  call i8* @objc_retain(i8* %x) nounwind
  call void @use_pointer(i8* %x)
  call void @use_pointer(i8* %x)
  call void @objc_release(i8* %x) nounwind
  call void @objc_release(i8* %x) nounwind
  ret void
}

; Trivial retain,autorelease pair with intervening call, but it's post-dominated
; by another release. Don't delete anything.

; CHECK: define void @test15(
; CHECK-NEXT: entry:
; CHECK-NEXT: @objc_retain(i8* %x)
; CHECK-NEXT: @use_pointer
; CHECK-NEXT: @objc_autorelease(i8* %x)
; CHECK-NEXT: @objc_release
; CHECK-NEXT: ret void
; CHECK-NEXT: }
define void @test15(i8* %x, i64 %n) {
entry:
  call i8* @objc_retain(i8* %x) nounwind
  call void @use_pointer(i8* %x)
  call i8* @objc_autorelease(i8* %x) nounwind
  call void @objc_release(i8* %x) nounwind
  ret void
}

; Trivial retain,autorelease pair, post-dominated
; by another release. Delete the retain and release.

; CHECK: define void @test15b
; CHECK-NEXT: entry:
; CHECK-NEXT: @objc_autorelease
; CHECK-NEXT: ret void
; CHECK-NEXT: }
define void @test15b(i8* %x, i64 %n) {
entry:
  call i8* @objc_retain(i8* %x) nounwind
  call i8* @objc_autorelease(i8* %x) nounwind
  call void @objc_release(i8* %x) nounwind
  ret void
}

; Retain+release pairs in diamonds, all dominated by a retain.

; CHECK: define void @test16(
; CHECK: @objc_retain(i8* %x)
; CHECK-NOT: @objc
; CHECK: }
define void @test16(i1 %a, i1 %b, i8* %x) {
entry:
  call i8* @objc_retain(i8* %x) nounwind
  br i1 %a, label %red, label %orange

red:
  call i8* @objc_retain(i8* %x) nounwind
  br label %yellow

orange:
  call i8* @objc_retain(i8* %x) nounwind
  br label %yellow

yellow:
  call void @use_pointer(i8* %x)
  call void @use_pointer(i8* %x)
  br i1 %b, label %green, label %blue

green:
  call void @objc_release(i8* %x) nounwind
  br label %purple

blue:
  call void @objc_release(i8* %x) nounwind
  br label %purple

purple:
  ret void
}

; Retain+release pairs in diamonds, all post-dominated by a release.

; CHECK: define void @test17(
; CHECK-NOT: @objc_
; CHECK: purple:
; CHECK: @objc_release
; CHECK: }
define void @test17(i1 %a, i1 %b, i8* %x) {
entry:
  br i1 %a, label %red, label %orange

red:
  call i8* @objc_retain(i8* %x) nounwind
  br label %yellow

orange:
  call i8* @objc_retain(i8* %x) nounwind
  br label %yellow

yellow:
  call void @use_pointer(i8* %x)
  call void @use_pointer(i8* %x)
  br i1 %b, label %green, label %blue

green:
  call void @objc_release(i8* %x) nounwind
  br label %purple

blue:
  call void @objc_release(i8* %x) nounwind
  br label %purple

purple:
  call void @objc_release(i8* %x) nounwind
  ret void
}

; Delete no-ops.

; CHECK: define void @test18(
; CHECK-NOT: @objc_
; CHECK: }
define void @test18() {
  call i8* @objc_retain(i8* null)
  call void @objc_release(i8* null)
  call i8* @objc_autorelease(i8* null)
  ret void
}

; Delete no-ops where undef can be assumed to be null.

; CHECK: define void @test18b
; CHECK-NOT: @objc_
; CHECK: }
define void @test18b() {
  call i8* @objc_retain(i8* undef)
  call void @objc_release(i8* undef)
  call i8* @objc_autorelease(i8* undef)
  ret void
}

; Replace uses of arguments with uses of return values, to reduce
; register pressure.

; CHECK: define void @test19(i32* %y) {
; CHECK:   %z = bitcast i32* %y to i8*
; CHECK:   %0 = bitcast i32* %y to i8*
; CHECK:   %1 = tail call i8* @objc_retain(i8* %0)
; CHECK:   call void @use_pointer(i8* %z)
; CHECK:   call void @use_pointer(i8* %z)
; CHECK:   %2 = bitcast i32* %y to i8*
; CHECK:   call void @objc_release(i8* %2)
; CHECK:   ret void
; CHECK: }
define void @test19(i32* %y) {
entry:
  %x = bitcast i32* %y to i8*
  %0 = call i8* @objc_retain(i8* %x) nounwind
  %z = bitcast i32* %y to i8*
  call void @use_pointer(i8* %z)
  call void @use_pointer(i8* %z)
  call void @objc_release(i8* %x)
  ret void
}

; Bitcast insertion

; CHECK: define void @test20(
; CHECK: %tmp1 = tail call i8* @objc_retain(i8* %tmp) nounwind
; CHECK-NEXT: invoke
define void @test20(double* %self) {
if.then12:
  %tmp = bitcast double* %self to i8*
  %tmp1 = call i8* @objc_retain(i8* %tmp) nounwind
  invoke void @invokee()
          to label %invoke.cont23 unwind label %lpad20

invoke.cont23:                                    ; preds = %if.then12
  invoke void @invokee()
          to label %if.end unwind label %lpad20

lpad20:                                           ; preds = %invoke.cont23, %if.then12
  %tmp502 = phi double* [ undef, %invoke.cont23 ], [ %self, %if.then12 ]
  unreachable

if.end:                                           ; preds = %invoke.cont23
  ret void
}

; Delete a redundant retain,autorelease when forwaring a call result
; directly to a return value.

; CHECK: define i8* @test21(
; CHECK: call i8* @returner()
; CHECK-NEXT: ret i8* %call
define i8* @test21() {
entry:
  %call = call i8* @returner()
  %0 = call i8* @objc_retain(i8* %call) nounwind
  %1 = call i8* @objc_autorelease(i8* %0) nounwind
  ret i8* %1
}

; Move an objc call up through a phi that has null operands.

; CHECK: define void @test22(
; CHECK: B:
; CHECK:   %1 = bitcast double* %p to i8*
; CHECK:   call void @objc_release(i8* %1)
; CHECK:   br label %C
; CHECK: C:                                                ; preds = %B, %A
; CHECK-NOT: @objc_release
; CHECK: }
define void @test22(double* %p, i1 %a) {
  br i1 %a, label %A, label %B
A:
  br label %C
B:
  br label %C
C:
  %h = phi double* [ null, %A ], [ %p, %B ]
  %c = bitcast double* %h to i8*
  call void @objc_release(i8* %c)
  ret void
}

; Optimize objc_retainBlock.

; CHECK: define void @test23(
; CHECK-NOT: @objc_
; CHECK: }
%block0 = type { i64, i64, i8*, i8* }
%block1 = type { i8**, i32, i32, i32 (%struct.__block_literal_1*)*, %block0* }
%struct.__block_descriptor = type { i64, i64 }
%struct.__block_literal_1 = type { i8**, i32, i32, i8**, %struct.__block_descriptor* }
@__block_holder_tmp_1 = external constant %block1
define void @test23() {
entry:
  %0 = call i8* @objc_retainBlock(i8* bitcast (%block1* @__block_holder_tmp_1 to i8*)) nounwind
  call void @bar(i32 ()* bitcast (%block1* @__block_holder_tmp_1 to i32 ()*))
  call void @bar(i32 ()* bitcast (%block1* @__block_holder_tmp_1 to i32 ()*))
  call void @objc_release(i8* bitcast (%block1* @__block_holder_tmp_1 to i8*)) nounwind
  ret void
}

; Don't optimize objc_retainBlock.

; CHECK: define void @test23b
; CHECK: @objc_retainBlock
; CHECK: @objc_release
; CHECK: }
define void @test23b(i8* %p) {
entry:
  %0 = call i8* @objc_retainBlock(i8* %p) nounwind
  call void @use_pointer(i8* %p)
  call void @use_pointer(i8* %p)
  call void @objc_release(i8* %p) nounwind
  ret void
}

; Any call can decrement a retain count.

; CHECK: define void @test24(
; CHECK: @objc_retain(i8* %a)
; CHECK: @objc_release
; CHECK: }
define void @test24(i8* %r, i8* %a) {
  call i8* @objc_retain(i8* %a)
  call void @use_pointer(i8* %r)
  %q = load i8* %a
  call void @objc_release(i8* %a)
  ret void
}

; Don't move a retain/release pair if the release can be moved
; but the retain can't be moved to balance it.

; CHECK: define void @test25(
; CHECK: entry:
; CHECK:   call i8* @objc_retain(i8* %p)
; CHECK: true:
; CHECK: done:
; CHECK:   call void @objc_release(i8* %p)
; CHECK: }
define void @test25(i8* %p, i1 %x) {
entry:
  %f0 = call i8* @objc_retain(i8* %p)
  call void @callee()
  br i1 %x, label %true, label %done

true:
  store i8 0, i8* %p
  br label %done

done:
  call void @objc_release(i8* %p)
  ret void
}

; Don't move a retain/release pair if the retain can be moved
; but the release can't be moved to balance it.

; CHECK: define void @test26(
; CHECK: entry:
; CHECK:   call i8* @objc_retain(i8* %p)
; CHECK: true:
; CHECK: done:
; CHECK:   call void @objc_release(i8* %p)
; CHECK: }
define void @test26(i8* %p, i1 %x) {
entry:
  %f0 = call i8* @objc_retain(i8* %p)
  br i1 %x, label %true, label %done

true:
  call void @callee()
  br label %done

done:
  store i8 0, i8* %p
  call void @objc_release(i8* %p)
  ret void
}

; Don't sink the retain,release into the loop.

; CHECK: define void @test27(
; CHECK: entry:
; CHECK: call i8* @objc_retain(i8* %p)
; CHECK: loop:
; CHECK-NOT: @objc_
; CHECK: done:
; CHECK: call void @objc_release
; CHECK: }
define void @test27(i8* %p, i1 %x, i1 %y) {
entry: 
  %f0 = call i8* @objc_retain(i8* %p)
  br i1 %x, label %loop, label %done

loop:
  call void @callee()
  store i8 0, i8* %p
  br i1 %y, label %done, label %loop
  
done: 
  call void @objc_release(i8* %p)
  ret void
}

; Trivial code motion case: Triangle.

; CHECK: define void @test28(
; CHECK-NOT: @objc_
; CHECK: true:
; CHECK: call i8* @objc_retain(
; CHECK: call void @callee()
; CHECK: store
; CHECK: call void @objc_release
; CHECK: done:
; CHECK-NOT: @objc_
; CHECK: }
define void @test28(i8* %p, i1 %x) {
entry:
  %f0 = call i8* @objc_retain(i8* %p)
  br i1 %x, label %true, label %done

true:
  call void @callee()
  store i8 0, i8* %p
  br label %done

done:
  call void @objc_release(i8* %p), !clang.imprecise_release !0
  ret void
}

; Trivial code motion case: Triangle, but no metadata. Don't move past
; unrelated memory references!

; CHECK: define void @test28b
; CHECK: call i8* @objc_retain(
; CHECK: true:
; CHECK-NOT: @objc_
; CHECK: call void @callee()
; CHECK-NOT: @objc_
; CHECK: store
; CHECK-NOT: @objc_
; CHECK: done:
; CHECK: @objc_release
; CHECK: }
define void @test28b(i8* %p, i1 %x, i8* noalias %t) {
entry:
  %f0 = call i8* @objc_retain(i8* %p)
  br i1 %x, label %true, label %done

true:
  call void @callee()
  store i8 0, i8* %p
  br label %done

done:
  store i8 0, i8* %t
  call void @objc_release(i8* %p)
  ret void
}

; Trivial code motion case: Triangle, with metadata. Do move past
; unrelated memory references! And preserve the metadata.

; CHECK: define void @test28c
; CHECK-NOT: @objc_
; CHECK: true:
; CHECK: call i8* @objc_retain(
; CHECK: call void @callee()
; CHECK: store
; CHECK: call void @objc_release(i8* %p) nounwind, !clang.imprecise_release
; CHECK: done:
; CHECK-NOT: @objc_
; CHECK: }
define void @test28c(i8* %p, i1 %x, i8* noalias %t) {
entry:
  %f0 = call i8* @objc_retain(i8* %p)
  br i1 %x, label %true, label %done

true:
  call void @callee()
  store i8 0, i8* %p
  br label %done

done:
  store i8 0, i8* %t
  call void @objc_release(i8* %p), !clang.imprecise_release !0
  ret void
}

; Like test28. but with two releases.

; CHECK: define void @test29(
; CHECK-NOT: @objc_
; CHECK: true:
; CHECK: call i8* @objc_retain(
; CHECK: call void @callee()
; CHECK: store
; CHECK: call void @objc_release
; CHECK-NOT: @objc_release
; CHECK: done:
; CHECK-NOT: @objc_
; CHECK: ohno:
; CHECK-NOT: @objc_
; CHECK: }
define void @test29(i8* %p, i1 %x, i1 %y) {
entry:
  %f0 = call i8* @objc_retain(i8* %p)
  br i1 %x, label %true, label %done

true:
  call void @callee()
  store i8 0, i8* %p
  br i1 %y, label %done, label %ohno

done:
  call void @objc_release(i8* %p)
  ret void

ohno:
  call void @objc_release(i8* %p)
  ret void
}

; Basic case with the use and call in a diamond
; with an extra release.

; CHECK: define void @test30(
; CHECK-NOT: @objc_
; CHECK: true:
; CHECK: call i8* @objc_retain(
; CHECK: call void @callee()
; CHECK: store
; CHECK: call void @objc_release
; CHECK-NOT: @objc_release
; CHECK: false:
; CHECK-NOT: @objc_
; CHECK: done:
; CHECK-NOT: @objc_
; CHECK: ohno:
; CHECK-NOT: @objc_
; CHECK: }
define void @test30(i8* %p, i1 %x, i1 %y, i1 %z) {
entry:
  %f0 = call i8* @objc_retain(i8* %p)
  br i1 %x, label %true, label %false

true:
  call void @callee()
  store i8 0, i8* %p
  br i1 %y, label %done, label %ohno

false:
  br i1 %z, label %done, label %ohno

done:
  call void @objc_release(i8* %p)
  ret void

ohno:
  call void @objc_release(i8* %p)
  ret void
}

; Basic case with a mergeable release.

; CHECK: define void @test31(
; CHECK: call i8* @objc_retain(i8* %p)
; CHECK: call void @callee()
; CHECK: store
; CHECK: call void @objc_release
; CHECK-NOT: @objc_release
; CHECK: true:
; CHECK-NOT: @objc_release
; CHECK: false:
; CHECK-NOT: @objc_release
; CHECK: ret void
; CHECK-NOT: @objc_release
; CHECK: }
define void @test31(i8* %p, i1 %x) {
entry:
  %f0 = call i8* @objc_retain(i8* %p)
  call void @callee()
  store i8 0, i8* %p
  br i1 %x, label %true, label %false
true:
  call void @objc_release(i8* %p)
  ret void
false:
  call void @objc_release(i8* %p)
  ret void
}

; Don't consider bitcasts or getelementptrs direct uses.

; CHECK: define void @test32(
; CHECK-NOT: @objc_
; CHECK: true:
; CHECK: call i8* @objc_retain(
; CHECK: call void @callee()
; CHECK: store
; CHECK: call void @objc_release
; CHECK: done:
; CHECK-NOT: @objc_
; CHECK: }
define void @test32(i8* %p, i1 %x) {
entry:
  %f0 = call i8* @objc_retain(i8* %p)
  br i1 %x, label %true, label %done

true:
  call void @callee()
  store i8 0, i8* %p
  br label %done

done:
  %g = bitcast i8* %p to i8*
  %h = getelementptr i8* %g, i64 0
  call void @objc_release(i8* %g)
  ret void
}

; Do consider icmps to be direct uses.

; CHECK: define void @test33(
; CHECK-NOT: @objc_
; CHECK: true:
; CHECK: call i8* @objc_retain(
; CHECK: call void @callee()
; CHECK: icmp
; CHECK: call void @objc_release
; CHECK: done:
; CHECK-NOT: @objc_
; CHECK: }
define void @test33(i8* %p, i1 %x, i8* %y) {
entry:
  %f0 = call i8* @objc_retain(i8* %p)
  br i1 %x, label %true, label %done

true:
  call void @callee()
  %v = icmp eq i8* %p, %y
  br label %done

done:
  %g = bitcast i8* %p to i8*
  %h = getelementptr i8* %g, i64 0
  call void @objc_release(i8* %g)
  ret void
}

; Delete retain,release if there's just a possible dec.

; CHECK: define void @test34(
; CHECK-NOT: @objc_
; CHECK: }
define void @test34(i8* %p, i1 %x, i8* %y) {
entry:
  %f0 = call i8* @objc_retain(i8* %p)
  br i1 %x, label %true, label %done

true:
  call void @callee()
  br label %done

done:
  %g = bitcast i8* %p to i8*
  %h = getelementptr i8* %g, i64 0
  call void @objc_release(i8* %g)
  ret void
}

; Delete retain,release if there's just a use.

; CHECK: define void @test35(
; CHECK-NOT: @objc_
; CHECK: }
define void @test35(i8* %p, i1 %x, i8* %y) {
entry:
  %f0 = call i8* @objc_retain(i8* %p)
  br i1 %x, label %true, label %done

true:
  %v = icmp eq i8* %p, %y
  br label %done

done:
  %g = bitcast i8* %p to i8*
  %h = getelementptr i8* %g, i64 0
  call void @objc_release(i8* %g)
  ret void
}

; Delete a retain,release if there's no actual use.

; CHECK: define void @test36(
; CHECK-NOT: @objc_
; CHECK: call void @callee()
; CHECK-NOT: @objc_
; CHECK: call void @callee()
; CHECK-NOT: @objc_
; CHECK: }
define void @test36(i8* %p) {
entry:
  call i8* @objc_retain(i8* %p)
  call void @callee()
  call void @callee()
  call void @objc_release(i8* %p)
  ret void
}

; Like test36, but with metadata.

; CHECK: define void @test37(
; CHECK-NOT: @objc_
; CHECK: }
define void @test37(i8* %p) {
entry:
  call i8* @objc_retain(i8* %p)
  call void @callee()
  call void @callee()
  call void @objc_release(i8* %p), !clang.imprecise_release !0
  ret void
}

; Be aggressive about analyzing phis to eliminate possible uses.

; CHECK: define void @test38(
; CHECK-NOT: @objc_
; CHECK: }
define void @test38(i8* %p, i1 %u, i1 %m, i8* %z, i8* %y, i8* %x, i8* %w) {
entry:
  call i8* @objc_retain(i8* %p)
  br i1 %u, label %true, label %false
true:
  br i1 %m, label %a, label %b
false:
  br i1 %m, label %c, label %d
a:
  br label %e
b:
  br label %e
c:
  br label %f
d:
  br label %f
e:
  %j = phi i8* [ %z, %a ], [ %y, %b ]
  br label %g
f:
  %k = phi i8* [ %w, %c ], [ %x, %d ]
  br label %g
g:
  %h = phi i8* [ %j, %e ], [ %k, %f ]
  call void @use_pointer(i8* %h)
  call void @objc_release(i8* %p), !clang.imprecise_release !0
  ret void
}

; Delete retain,release pairs around loops.

; CHECK: define void @test39(
; CHECK_NOT: @objc_
; CHECK: }
define void @test39(i8* %p) {
entry:
  %0 = call i8* @objc_retain(i8* %p)
  br label %loop

loop:                                             ; preds = %loop, %entry
  br i1 undef, label %loop, label %exit

exit:                                             ; preds = %loop
  call void @objc_release(i8* %0), !clang.imprecise_release !0
  ret void
}

; Delete retain,release pairs around loops containing uses.

; CHECK: define void @test39b(
; CHECK_NOT: @objc_
; CHECK: }
define void @test39b(i8* %p) {
entry:
  %0 = call i8* @objc_retain(i8* %p)
  br label %loop

loop:                                             ; preds = %loop, %entry
  store i8 0, i8* %0
  br i1 undef, label %loop, label %exit

exit:                                             ; preds = %loop
  call void @objc_release(i8* %0), !clang.imprecise_release !0
  ret void
}

; Delete retain,release pairs around loops containing potential decrements.

; CHECK: define void @test39c(
; CHECK_NOT: @objc_
; CHECK: }
define void @test39c(i8* %p) {
entry:
  %0 = call i8* @objc_retain(i8* %p)
  br label %loop

loop:                                             ; preds = %loop, %entry
  call void @use_pointer(i8* %0)
  br i1 undef, label %loop, label %exit

exit:                                             ; preds = %loop
  call void @objc_release(i8* %0), !clang.imprecise_release !0
  ret void
}

; Delete retain,release pairs around loops even if
; the successors are in a different order.

; CHECK: define void @test40(
; CHECK_NOT: @objc_
; CHECK: }
define void @test40(i8* %p) {
entry:
  %0 = call i8* @objc_retain(i8* %p)
  br label %loop

loop:                                             ; preds = %loop, %entry
  call void @use_pointer(i8* %0)
  br i1 undef, label %exit, label %loop

exit:                                             ; preds = %loop
  call void @objc_release(i8* %0), !clang.imprecise_release !0
  ret void
}

; Do the known-incremented retain+release elimination even if the pointer
; is also autoreleased.

; CHECK: define void @test42(
; CHECK-NEXT: entry:
; CHECK-NEXT: call i8* @objc_retain(i8* %p)
; CHECK-NEXT: call i8* @objc_autorelease(i8* %p)
; CHECK-NEXT: call void @use_pointer(i8* %p)
; CHECK-NEXT: call void @use_pointer(i8* %p)
; CHECK-NEXT: ret void
; CHECK-NEXT: }
define void @test42(i8* %p) {
entry:
  call i8* @objc_retain(i8* %p)
  call i8* @objc_autorelease(i8* %p)
  call i8* @objc_retain(i8* %p)
  call void @use_pointer(i8* %p)
  call void @use_pointer(i8* %p)
  call void @objc_release(i8* %p)
  ret void
}

; Don't the known-incremented retain+release elimination if the pointer is
; autoreleased and there's an autoreleasePoolPop.

; CHECK: define void @test43(
; CHECK-NEXT: entry:
; CHECK-NEXT: call i8* @objc_retain(i8* %p)
; CHECK-NEXT: call i8* @objc_autorelease(i8* %p)
; CHECK-NEXT: call i8* @objc_retain
; CHECK-NEXT: call void @use_pointer(i8* %p)
; CHECK-NEXT: call void @use_pointer(i8* %p)
; CHECK-NEXT: call void @objc_autoreleasePoolPop(i8* undef)
; CHECK-NEXT: call void @objc_release
; CHECK-NEXT: ret void
; CHECK-NEXT: }
define void @test43(i8* %p) {
entry:
  call i8* @objc_retain(i8* %p)
  call i8* @objc_autorelease(i8* %p)
  call i8* @objc_retain(i8* %p)
  call void @use_pointer(i8* %p)
  call void @use_pointer(i8* %p)
  call void @objc_autoreleasePoolPop(i8* undef)
  call void @objc_release(i8* %p)
  ret void
}

; Do the known-incremented retain+release elimination if the pointer is
; autoreleased and there's an autoreleasePoolPush.

; CHECK: define void @test43b
; CHECK-NEXT: entry:
; CHECK-NEXT: call i8* @objc_retain(i8* %p)
; CHECK-NEXT: call i8* @objc_autorelease(i8* %p)
; CHECK-NEXT: call void @use_pointer(i8* %p)
; CHECK-NEXT: call void @use_pointer(i8* %p)
; CHECK-NEXT: call void @objc_autoreleasePoolPush()
; CHECK-NEXT: ret void
; CHECK-NEXT: }
define void @test43b(i8* %p) {
entry:
  call i8* @objc_retain(i8* %p)
  call i8* @objc_autorelease(i8* %p)
  call i8* @objc_retain(i8* %p)
  call void @use_pointer(i8* %p)
  call void @use_pointer(i8* %p)
  call void @objc_autoreleasePoolPush()
  call void @objc_release(i8* %p)
  ret void
}

; Do retain+release elimination for non-provenance pointers.

; CHECK: define void @test44(
; CHECK-NOT: objc_
; CHECK: }
define void @test44(i8** %pp) {
  %p = load i8** %pp
  %q = call i8* @objc_retain(i8* %p)
  call void @objc_release(i8* %q)
  ret void
}

; Don't delete retain+release with an unknown-provenance
; may-alias objc_release between them.

; CHECK: define void @test45(
; CHECK: call i8* @objc_retain(i8* %p)
; CHECK: call void @objc_release(i8* %q)
; CHECK: call void @use_pointer(i8* %p)
; CHECK: call void @objc_release(i8* %p)
define void @test45(i8** %pp, i8** %qq) {
  %p = load i8** %pp
  %q = load i8** %qq
  call i8* @objc_retain(i8* %p)
  call void @objc_release(i8* %q)
  call void @use_pointer(i8* %p)
  call void @objc_release(i8* %p)
  ret void
}

; Don't delete retain and autorelease here.

; CHECK: define void @test46(
; CHECK: tail call i8* @objc_retain(i8* %p) nounwind
; CHECK: true:
; CHECK: tail call i8* @objc_autorelease(i8* %p) nounwind
define void @test46(i8* %p, i1 %a) {
entry:
  call i8* @objc_retain(i8* %p)
  br i1 %a, label %true, label %false

true:
  call i8* @objc_autorelease(i8* %p)
  call void @use_pointer(i8* %p)
  ret void

false:
  ret void
}

; Delete no-op cast calls.

; CHECK: define i8* @test47(
; CHECK-NOT: call
; CHECK: ret i8* %p
define i8* @test47(i8* %p) nounwind {
  %x = call i8* @objc_retainedObject(i8* %p)
  ret i8* %x
}

; Delete no-op cast calls.

; CHECK: define i8* @test48(
; CHECK-NOT: call
; CHECK: ret i8* %p
define i8* @test48(i8* %p) nounwind {
  %x = call i8* @objc_unretainedObject(i8* %p)
  ret i8* %x
}

; Delete no-op cast calls.

; CHECK: define i8* @test49(
; CHECK-NOT: call
; CHECK: ret i8* %p
define i8* @test49(i8* %p) nounwind {
  %x = call i8* @objc_unretainedPointer(i8* %p)
  ret i8* %x
}

; Do delete retain+release with intervening stores of the
; address value;

; CHECK: define void @test50(
; CHECK-NOT: @objc_
; CHECK: }
define void @test50(i8* %p, i8** %pp) {
  call i8* @objc_retain(i8* %p)
  call void @callee()
  store i8* %p, i8** %pp
  call void @objc_release(i8* %p)
  ret void
}

; Don't delete retain+release with intervening stores through the
; address value.

; CHECK: define void @test51(
; CHECK: call i8* @objc_retain(i8* %p)
; CHECK: call void @objc_release(i8* %p)
define void @test51(i8* %p) {
  call i8* @objc_retain(i8* %p)
  call void @callee()
  store i8 0, i8* %p
  call void @objc_release(i8* %p)
  ret void
}

; Don't delete retain+release with intervening use of a pointer of
; unknown provenance.

; CHECK: define void @test52(
; CHECK: call i8* @objc_retain
; CHECK: call void @callee()
; CHECK: call void @use_pointer(i8* %z)
; CHECK: call void @objc_release
define void @test52(i8** %zz, i8** %pp) {
  %p = load i8** %pp
  %1 = call i8* @objc_retain(i8* %p)
  call void @callee()
  %z = load i8** %zz
  call void @use_pointer(i8* %z)
  call void @objc_release(i8* %p)
  ret void
}

; Like test52, but the pointer has function type, so it's assumed to
; be not reference counted.

; CHECK: define void @test53(
; CHECK-NOT: @objc_
; CHECK: }
define void @test53(void ()** %zz, i8** %pp) {
  %p = load i8** %pp
  %1 = call i8* @objc_retain(i8* %p)
  call void @callee()
  %z = load void ()** %zz
  call void @callee_fnptr(void ()* %z)
  call void @objc_release(i8* %p)
  ret void
}

; Convert autorelease to release if the value is unused.

; CHECK: define void @test54(
; CHECK: call i8* @returner()
; CHECK-NEXT: call void @objc_release(i8* %t) nounwind, !clang.imprecise_release !0
; CHECK-NEXT: ret void
define void @test54() {
  %t = call i8* @returner()
  call i8* @objc_autorelease(i8* %t)
  ret void
}

; Nested retain+release pairs. Delete them both.

; CHECK: define void @test55(
; CHECK-NOT: @objc
; CHECK: }
define void @test55(i8* %x) { 
entry: 
  %0 = call i8* @objc_retain(i8* %x) nounwind 
  %1 = call i8* @objc_retain(i8* %x) nounwind 
  call void @objc_release(i8* %x) nounwind 
  call void @objc_release(i8* %x) nounwind 
  ret void 
}

; Nested retain+release pairs where the inner pair depends
; on the outer pair to be removed, and then the outer pair
; can be partially eliminated. Plus an extra outer pair to
; eliminate, for fun.

; CHECK: define void @test56(
; CHECK-NOT: @objc
; CHECK: if.then:
; CHECK-NEXT: %0 = tail call i8* @objc_retain(i8* %x) nounwind
; CHECK-NEXT: tail call void @use_pointer(i8* %x)
; CHECK-NEXT: tail call void @use_pointer(i8* %x)
; CHECK-NEXT: tail call void @objc_release(i8* %x) nounwind, !clang.imprecise_release !0
; CHECK-NEXT: br label %if.end
; CHECK-NOT: @objc
; CHECK: }
define void @test56(i8* %x, i32 %n) {
entry:
  %0 = tail call i8* @objc_retain(i8* %x) nounwind
  %1 = tail call i8* @objc_retain(i8* %0) nounwind
  %tobool = icmp eq i32 %n, 0
  br i1 %tobool, label %if.end, label %if.then

if.then:                                          ; preds = %entry
  %2 = tail call i8* @objc_retain(i8* %1) nounwind
  tail call void @use_pointer(i8* %2)
  tail call void @use_pointer(i8* %2)
  tail call void @objc_release(i8* %2) nounwind, !clang.imprecise_release !0
  br label %if.end

if.end:                                           ; preds = %entry, %if.then
  tail call void @objc_release(i8* %1) nounwind, !clang.imprecise_release !0
  tail call void @objc_release(i8* %0) nounwind, !clang.imprecise_release !0
  ret void
}

declare void @bar(i32 ()*)

; A few real-world testcases.

@.str4 = private unnamed_addr constant [33 x i8] c"-[A z] = { %f, %f, { %f, %f } }\0A\00"
@"OBJC_IVAR_$_A.myZ" = global i64 20, section "__DATA, __objc_const", align 8
declare i32 @printf(i8* nocapture, ...) nounwind
declare i32 @puts(i8* nocapture) nounwind
@str = internal constant [16 x i8] c"-[ Top0 _getX ]\00"

; CHECK: @"\01-[A z]"
; CHECK-NOT: @objc_
; CHECK: }

define {<2 x float>, <2 x float>} @"\01-[A z]"({}* %self, i8* nocapture %_cmd) nounwind {
invoke.cont:
  %0 = bitcast {}* %self to i8*
  %1 = tail call i8* @objc_retain(i8* %0) nounwind
  tail call void @llvm.dbg.value(metadata !{{}* %self}, i64 0, metadata !0)
  tail call void @llvm.dbg.value(metadata !{{}* %self}, i64 0, metadata !0)
  %ivar = load i64* @"OBJC_IVAR_$_A.myZ", align 8
  %add.ptr = getelementptr i8* %0, i64 %ivar
  %tmp1 = bitcast i8* %add.ptr to float*
  %tmp2 = load float* %tmp1, align 4
  %conv = fpext float %tmp2 to double
  %add.ptr.sum = add i64 %ivar, 4
  %tmp6 = getelementptr inbounds i8* %0, i64 %add.ptr.sum
  %2 = bitcast i8* %tmp6 to float*
  %tmp7 = load float* %2, align 4
  %conv8 = fpext float %tmp7 to double
  %add.ptr.sum36 = add i64 %ivar, 8
  %tmp12 = getelementptr inbounds i8* %0, i64 %add.ptr.sum36
  %arrayidx = bitcast i8* %tmp12 to float*
  %tmp13 = load float* %arrayidx, align 4
  %conv14 = fpext float %tmp13 to double
  %tmp12.sum = add i64 %ivar, 12
  %arrayidx19 = getelementptr inbounds i8* %0, i64 %tmp12.sum
  %3 = bitcast i8* %arrayidx19 to float*
  %tmp20 = load float* %3, align 4
  %conv21 = fpext float %tmp20 to double
  %call = tail call i32 (i8*, ...)* @printf(i8* getelementptr inbounds ([33 x i8]* @.str4, i64 0, i64 0), double %conv, double %conv8, double %conv14, double %conv21)
  %ivar23 = load i64* @"OBJC_IVAR_$_A.myZ", align 8
  %add.ptr24 = getelementptr i8* %0, i64 %ivar23
  %4 = bitcast i8* %add.ptr24 to i128*
  %srcval = load i128* %4, align 4
  tail call void @objc_release(i8* %0) nounwind
  %tmp29 = trunc i128 %srcval to i64
  %tmp30 = bitcast i64 %tmp29 to <2 x float>
  %tmp31 = insertvalue {<2 x float>, <2 x float>} undef, <2 x float> %tmp30, 0
  %tmp32 = lshr i128 %srcval, 64
  %tmp33 = trunc i128 %tmp32 to i64
  %tmp34 = bitcast i64 %tmp33 to <2 x float>
  %tmp35 = insertvalue {<2 x float>, <2 x float>} %tmp31, <2 x float> %tmp34, 1
  ret {<2 x float>, <2 x float>} %tmp35
}

; CHECK: @"\01-[Top0 _getX]"
; CHECK-NOT: @objc_
; CHECK: }

define i32 @"\01-[Top0 _getX]"({}* %self, i8* nocapture %_cmd) nounwind {
invoke.cont:
  %0 = bitcast {}* %self to i8*
  %1 = tail call i8* @objc_retain(i8* %0) nounwind
  %puts = tail call i32 @puts(i8* getelementptr inbounds ([16 x i8]* @str, i64 0, i64 0))
  tail call void @objc_release(i8* %0) nounwind
  ret i32 0
}

@"\01L_OBJC_METH_VAR_NAME_" = internal global [5 x i8] c"frob\00", section "__TEXT,__cstring,cstring_literals", align 1@"\01L_OBJC_SELECTOR_REFERENCES_" = internal global i8* getelementptr inbounds ([5 x i8]* @"\01L_OBJC_METH_VAR_NAME_", i64 0, i64 0), section "__DATA, __objc_selrefs, literal_pointers, no_dead_strip"
@"\01L_OBJC_IMAGE_INFO" = internal constant [2 x i32] [i32 0, i32 16], section "__DATA, __objc_imageinfo, regular, no_dead_strip"
@llvm.used = appending global [3 x i8*] [i8* getelementptr inbounds ([5 x i8]* @"\01L_OBJC_METH_VAR_NAME_", i32 0, i32 0), i8* bitcast (i8** @"\01L_OBJC_SELECTOR_REFERENCES_" to i8*), i8* bitcast ([2 x i32]* @"\01L_OBJC_IMAGE_INFO" to i8*)], section "llvm.metadata"

; A simple loop. Eliminate the retain and release inside of it!

; CHECK: define void @loop
; CHECK: for.body:
; CHECK-NOT: @objc_
; CHECK: @objc_msgSend
; CHECK-NOT: @objc_
; CHECK: for.end:
define void @loop(i8* %x, i64 %n) {
entry:
  %0 = tail call i8* @objc_retain(i8* %x) nounwind
  %cmp9 = icmp sgt i64 %n, 0
  br i1 %cmp9, label %for.body, label %for.end

for.body:                                         ; preds = %entry, %for.body
  %i.010 = phi i64 [ %inc, %for.body ], [ 0, %entry ]
  %1 = tail call i8* @objc_retain(i8* %x) nounwind
  %tmp5 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_", align 8
  %call = tail call i8* (i8*, i8*, ...)* @objc_msgSend(i8* %1, i8* %tmp5)
  tail call void @objc_release(i8* %1) nounwind, !clang.imprecise_release !0
  %inc = add nsw i64 %i.010, 1
  %exitcond = icmp eq i64 %inc, %n
  br i1 %exitcond, label %for.end, label %for.body

for.end:                                          ; preds = %for.body, %entry
  tail call void @objc_release(i8* %x) nounwind, !clang.imprecise_release !0
  ret void
}

; ObjCARCOpt can delete the retain,release on self.

; CHECK: define void @TextEditTest
; CHECK-NOT: call i8* @objc_retain(i8* %tmp7)
; CHECK: }

%0 = type { i8* (i8*, %struct._message_ref_t*, ...)*, i8* }
%1 = type opaque
%2 = type opaque
%3 = type opaque
%4 = type opaque
%5 = type opaque
%struct.NSConstantString = type { i32*, i32, i8*, i64 }
%struct._NSRange = type { i64, i64 }
%struct.__CFString = type opaque
%struct.__method_list_t = type { i32, i32, [0 x %struct._objc_method] }
%struct._class_ro_t = type { i32, i32, i32, i8*, i8*, %struct.__method_list_t*, %struct._objc_protocol_list*, %struct._ivar_list_t*, i8*, %struct._prop_list_t* }
%struct._class_t = type { %struct._class_t*, %struct._class_t*, %struct._objc_cache*, i8* (i8*, i8*)**, %struct._class_ro_t* }
%struct._ivar_list_t = type { i32, i32, [0 x %struct._ivar_t] }
%struct._ivar_t = type { i64*, i8*, i8*, i32, i32 }
%struct._message_ref_t = type { i8*, i8* }
%struct._objc_cache = type opaque
%struct._objc_method = type { i8*, i8*, i8* }
%struct._objc_protocol_list = type { i64, [0 x %struct._protocol_t*] }
%struct._prop_list_t = type { i32, i32, [0 x %struct._message_ref_t] }
%struct._protocol_t = type { i8*, i8*, %struct._objc_protocol_list*, %struct.__method_list_t*, %struct.__method_list_t*, %struct.__method_list_t*, %struct.__method_list_t*, %struct._prop_list_t*, i32, i32 }

@"\01L_OBJC_CLASSLIST_REFERENCES_$_17" = external hidden global %struct._class_t*, section "__DATA, __objc_classrefs, regular, no_dead_strip", align 8
@kUTTypePlainText = external constant %struct.__CFString*
@"\01L_OBJC_SELECTOR_REFERENCES_19" = external hidden global i8*, section "__DATA, __objc_selrefs, literal_pointers, no_dead_strip"
@"\01L_OBJC_SELECTOR_REFERENCES_21" = external hidden global i8*, section "__DATA, __objc_selrefs, literal_pointers, no_dead_strip"
@"\01L_OBJC_SELECTOR_REFERENCES_23" = external hidden global i8*, section "__DATA, __objc_selrefs, literal_pointers, no_dead_strip"
@"\01L_OBJC_SELECTOR_REFERENCES_25" = external hidden global i8*, section "__DATA, __objc_selrefs, literal_pointers, no_dead_strip"
@"\01L_OBJC_CLASSLIST_REFERENCES_$_26" = external hidden global %struct._class_t*, section "__DATA, __objc_classrefs, regular, no_dead_strip", align 8
@"\01L_OBJC_SELECTOR_REFERENCES_28" = external hidden global i8*, section "__DATA, __objc_selrefs, literal_pointers, no_dead_strip"
@"\01L_OBJC_CLASSLIST_REFERENCES_$_29" = external hidden global %struct._class_t*, section "__DATA, __objc_classrefs, regular, no_dead_strip", align 8
@"\01L_OBJC_SELECTOR_REFERENCES_31" = external hidden global i8*, section "__DATA, __objc_selrefs, literal_pointers, no_dead_strip"
@"\01L_OBJC_SELECTOR_REFERENCES_33" = external hidden global i8*, section "__DATA, __objc_selrefs, literal_pointers, no_dead_strip"
@"\01L_OBJC_SELECTOR_REFERENCES_35" = external hidden global i8*, section "__DATA, __objc_selrefs, literal_pointers, no_dead_strip"
@"\01L_OBJC_SELECTOR_REFERENCES_37" = external hidden global i8*, section "__DATA, __objc_selrefs, literal_pointers, no_dead_strip"
@"\01L_OBJC_CLASSLIST_REFERENCES_$_38" = external hidden global %struct._class_t*, section "__DATA, __objc_classrefs, regular, no_dead_strip", align 8
@"\01L_OBJC_SELECTOR_REFERENCES_40" = external hidden global i8*, section "__DATA, __objc_selrefs, literal_pointers, no_dead_strip"
@"\01L_OBJC_SELECTOR_REFERENCES_42" = external hidden global i8*, section "__DATA, __objc_selrefs, literal_pointers, no_dead_strip"
@_unnamed_cfstring_44 = external hidden constant %struct.NSConstantString, section "__DATA,__cfstring"
@"\01L_OBJC_SELECTOR_REFERENCES_46" = external hidden global i8*, section "__DATA, __objc_selrefs, literal_pointers, no_dead_strip"
@"\01L_OBJC_SELECTOR_REFERENCES_48" = external hidden global i8*, section "__DATA, __objc_selrefs, literal_pointers, no_dead_strip"
@"\01l_objc_msgSend_fixup_isEqual_" = external hidden global %0, section "__DATA, __objc_msgrefs, coalesced", align 16
@"\01L_OBJC_CLASSLIST_REFERENCES_$_50" = external hidden global %struct._class_t*, section "__DATA, __objc_classrefs, regular, no_dead_strip", align 8
@NSCocoaErrorDomain = external constant %1*
@"\01L_OBJC_CLASSLIST_REFERENCES_$_51" = external hidden global %struct._class_t*, section "__DATA, __objc_classrefs, regular, no_dead_strip", align 8
@NSFilePathErrorKey = external constant %1*
@"\01L_OBJC_SELECTOR_REFERENCES_53" = external hidden global i8*, section "__DATA, __objc_selrefs, literal_pointers, no_dead_strip"
@"\01L_OBJC_SELECTOR_REFERENCES_55" = external hidden global i8*, section "__DATA, __objc_selrefs, literal_pointers, no_dead_strip"
@"\01L_OBJC_CLASSLIST_REFERENCES_$_56" = external hidden global %struct._class_t*, section "__DATA, __objc_classrefs, regular, no_dead_strip", align 8
@"\01L_OBJC_SELECTOR_REFERENCES_58" = external hidden global i8*, section "__DATA, __objc_selrefs, literal_pointers, no_dead_strip"
@"\01L_OBJC_SELECTOR_REFERENCES_60" = external hidden global i8*, section "__DATA, __objc_selrefs, literal_pointers, no_dead_strip"

declare %1* @truncatedString(%1*, i64)
define void @TextEditTest(%2* %self, %3* %pboard) {
entry:
  %err = alloca %4*, align 8
  %tmp7 = bitcast %2* %self to i8*
  %tmp8 = call i8* @objc_retain(i8* %tmp7) nounwind
  store %4* null, %4** %err, align 8
  %tmp1 = load %struct._class_t** @"\01L_OBJC_CLASSLIST_REFERENCES_$_17", align 8
  %tmp2 = load %struct.__CFString** @kUTTypePlainText, align 8
  %tmp3 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_19", align 8
  %tmp4 = bitcast %struct._class_t* %tmp1 to i8*
  %call5 = call i8* (i8*, i8*, ...)* @objc_msgSend(i8* %tmp4, i8* %tmp3, %struct.__CFString* %tmp2)
  %tmp5 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_21", align 8
  %tmp6 = bitcast %3* %pboard to i8*
  %call76 = call i8* (i8*, i8*, ...)* @objc_msgSend(i8* %tmp6, i8* %tmp5, i8* %call5)
  %tmp9 = call i8* @objc_retain(i8* %call76) nounwind
  %tobool = icmp eq i8* %tmp9, null
  br i1 %tobool, label %end, label %land.lhs.true

land.lhs.true:                                    ; preds = %entry
  %tmp11 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_23", align 8
  %call137 = call i8* (i8*, i8*, ...)* @objc_msgSend(i8* %tmp6, i8* %tmp11, i8* %tmp9)
  %tmp = bitcast i8* %call137 to %1*
  %tmp10 = call i8* @objc_retain(i8* %call137) nounwind
  call void @objc_release(i8* null) nounwind
  %tmp12 = call i8* @objc_retain(i8* %call137) nounwind
  call void @objc_release(i8* null) nounwind
  %tobool16 = icmp eq i8* %call137, null
  br i1 %tobool16, label %end, label %if.then

if.then:                                          ; preds = %land.lhs.true
  %tmp19 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_25", align 8
  %call21 = call signext i8 bitcast (i8* (i8*, i8*, ...)* @objc_msgSend to i8 (i8*, i8*)*)(i8* %call137, i8* %tmp19)
  %tobool22 = icmp eq i8 %call21, 0
  br i1 %tobool22, label %if.then44, label %land.lhs.true23

land.lhs.true23:                                  ; preds = %if.then
  %tmp24 = load %struct._class_t** @"\01L_OBJC_CLASSLIST_REFERENCES_$_26", align 8
  %tmp26 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_28", align 8
  %tmp27 = bitcast %struct._class_t* %tmp24 to i8*
  %call2822 = call i8* (i8*, i8*, ...)* @objc_msgSend(i8* %tmp27, i8* %tmp26, i8* %call137)
  %tmp13 = bitcast i8* %call2822 to %5*
  %tmp14 = call i8* @objc_retain(i8* %call2822) nounwind
  call void @objc_release(i8* null) nounwind
  %tobool30 = icmp eq i8* %call2822, null
  br i1 %tobool30, label %if.then44, label %if.end

if.end:                                           ; preds = %land.lhs.true23
  %tmp32 = load %struct._class_t** @"\01L_OBJC_CLASSLIST_REFERENCES_$_29", align 8
  %tmp33 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_31", align 8
  %tmp34 = bitcast %struct._class_t* %tmp32 to i8*
  %call35 = call i8* (i8*, i8*, ...)* @objc_msgSend(i8* %tmp34, i8* %tmp33)
  %tmp37 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_33", align 8
  %call3923 = call i8* (i8*, i8*, ...)* @objc_msgSend(i8* %call35, i8* %tmp37, i8* %call2822, i32 signext 1, %4** %err)
  %cmp = icmp eq i8* %call3923, null
  br i1 %cmp, label %if.then44, label %end

if.then44:                                        ; preds = %if.end, %land.lhs.true23, %if.then
  %url.025 = phi %5* [ %tmp13, %if.end ], [ %tmp13, %land.lhs.true23 ], [ null, %if.then ]
  %tmp49 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_35", align 8
  %call51 = call %struct._NSRange bitcast (i8* (i8*, i8*, ...)* @objc_msgSend to %struct._NSRange (i8*, i8*, i64, i64)*)(i8* %call137, i8* %tmp49, i64 0, i64 0)
  %call513 = extractvalue %struct._NSRange %call51, 0
  %call514 = extractvalue %struct._NSRange %call51, 1
  %tmp52 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_37", align 8
  %call548 = call i8* (i8*, i8*, ...)* @objc_msgSend(i8* %call137, i8* %tmp52, i64 %call513, i64 %call514)
  %tmp55 = load %struct._class_t** @"\01L_OBJC_CLASSLIST_REFERENCES_$_38", align 8
  %tmp56 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_40", align 8
  %tmp57 = bitcast %struct._class_t* %tmp55 to i8*
  %call58 = call i8* (i8*, i8*, ...)* @objc_msgSend(i8* %tmp57, i8* %tmp56)
  %tmp59 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_42", align 8
  %call6110 = call i8* (i8*, i8*, ...)* @objc_msgSend(i8* %call548, i8* %tmp59, i8* %call58)
  %tmp15 = call i8* @objc_retain(i8* %call6110) nounwind
  call void @objc_release(i8* %call137) nounwind
  %tmp64 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_46", align 8
  %call66 = call signext i8 bitcast (i8* (i8*, i8*, ...)* @objc_msgSend to i8 (i8*, i8*, %1*)*)(i8* %call6110, i8* %tmp64, %1* bitcast (%struct.NSConstantString* @_unnamed_cfstring_44 to %1*))
  %tobool67 = icmp eq i8 %call66, 0
  br i1 %tobool67, label %if.end74, label %if.then68

if.then68:                                        ; preds = %if.then44
  %tmp70 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_48", align 8
  %call7220 = call i8* (i8*, i8*, ...)* @objc_msgSend(i8* %call6110, i8* %tmp70)
  %tmp16 = call i8* @objc_retain(i8* %call7220) nounwind
  call void @objc_release(i8* %call6110) nounwind
  br label %if.end74

if.end74:                                         ; preds = %if.then68, %if.then44
  %filename.0.in = phi i8* [ %call7220, %if.then68 ], [ %call6110, %if.then44 ]
  %filename.0 = bitcast i8* %filename.0.in to %1*
  %tmp17 = load i8** bitcast (%0* @"\01l_objc_msgSend_fixup_isEqual_" to i8**), align 16
  %tmp18 = bitcast i8* %tmp17 to i8 (i8*, %struct._message_ref_t*, i8*, ...)*
  %call78 = call signext i8 (i8*, %struct._message_ref_t*, i8*, ...)* %tmp18(i8* %call137, %struct._message_ref_t* bitcast (%0* @"\01l_objc_msgSend_fixup_isEqual_" to %struct._message_ref_t*), i8* %filename.0.in)
  %tobool79 = icmp eq i8 %call78, 0
  br i1 %tobool79, label %land.lhs.true80, label %if.then109

land.lhs.true80:                                  ; preds = %if.end74
  %tmp82 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_25", align 8
  %call84 = call signext i8 bitcast (i8* (i8*, i8*, ...)* @objc_msgSend to i8 (i8*, i8*)*)(i8* %filename.0.in, i8* %tmp82)
  %tobool86 = icmp eq i8 %call84, 0
  br i1 %tobool86, label %if.then109, label %if.end106

if.end106:                                        ; preds = %land.lhs.true80
  %tmp88 = load %struct._class_t** @"\01L_OBJC_CLASSLIST_REFERENCES_$_26", align 8
  %tmp90 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_28", align 8
  %tmp91 = bitcast %struct._class_t* %tmp88 to i8*
  %call9218 = call i8* (i8*, i8*, ...)* @objc_msgSend(i8* %tmp91, i8* %tmp90, i8* %filename.0.in)
  %tmp20 = bitcast i8* %call9218 to %5*
  %tmp21 = call i8* @objc_retain(i8* %call9218) nounwind
  %tmp22 = bitcast %5* %url.025 to i8*
  call void @objc_release(i8* %tmp22) nounwind
  %tmp94 = load %struct._class_t** @"\01L_OBJC_CLASSLIST_REFERENCES_$_29", align 8
  %tmp95 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_31", align 8
  %tmp96 = bitcast %struct._class_t* %tmp94 to i8*
  %call97 = call i8* (i8*, i8*, ...)* @objc_msgSend(i8* %tmp96, i8* %tmp95)
  %tmp99 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_33", align 8
  %call10119 = call i8* (i8*, i8*, ...)* @objc_msgSend(i8* %call97, i8* %tmp99, i8* %call9218, i32 signext 1, %4** %err)
  %phitmp = icmp eq i8* %call10119, null
  br i1 %phitmp, label %if.then109, label %end

if.then109:                                       ; preds = %if.end106, %land.lhs.true80, %if.end74
  %url.129 = phi %5* [ %tmp20, %if.end106 ], [ %url.025, %if.end74 ], [ %url.025, %land.lhs.true80 ]
  %tmp110 = load %4** %err, align 8
  %tobool111 = icmp eq %4* %tmp110, null
  br i1 %tobool111, label %if.then112, label %if.end125

if.then112:                                       ; preds = %if.then109
  %tmp113 = load %struct._class_t** @"\01L_OBJC_CLASSLIST_REFERENCES_$_50", align 8
  %tmp114 = load %1** @NSCocoaErrorDomain, align 8
  %tmp115 = load %struct._class_t** @"\01L_OBJC_CLASSLIST_REFERENCES_$_51", align 8
  %call117 = call %1* @truncatedString(%1* %filename.0, i64 1034)
  %tmp118 = load %1** @NSFilePathErrorKey, align 8
  %tmp119 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_53", align 8
  %tmp120 = bitcast %struct._class_t* %tmp115 to i8*
  %call12113 = call i8* (i8*, i8*, ...)* @objc_msgSend(i8* %tmp120, i8* %tmp119, %1* %call117, %1* %tmp118, i8* null)
  %tmp122 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_55", align 8
  %tmp123 = bitcast %struct._class_t* %tmp113 to i8*
  %call12414 = call i8* (i8*, i8*, ...)* @objc_msgSend(i8* %tmp123, i8* %tmp122, %1* %tmp114, i64 258, i8* %call12113)
  %tmp23 = call i8* @objc_retain(i8* %call12414) nounwind
  %tmp25 = call i8* @objc_autorelease(i8* %tmp23) nounwind
  %tmp28 = bitcast i8* %tmp25 to %4*
  store %4* %tmp28, %4** %err, align 8
  br label %if.end125

if.end125:                                        ; preds = %if.then112, %if.then109
  %tmp127 = phi %4* [ %tmp110, %if.then109 ], [ %tmp28, %if.then112 ]
  %tmp126 = load %struct._class_t** @"\01L_OBJC_CLASSLIST_REFERENCES_$_56", align 8
  %tmp128 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_58", align 8
  %tmp129 = bitcast %struct._class_t* %tmp126 to i8*
  %call13015 = call i8* (i8*, i8*, ...)* @objc_msgSend(i8* %tmp129, i8* %tmp128, %4* %tmp127)
  %tmp131 = load i8** @"\01L_OBJC_SELECTOR_REFERENCES_60", align 8
  %call13317 = call i8* (i8*, i8*, ...)* @objc_msgSend(i8* %call13015, i8* %tmp131)
  br label %end

end:                                              ; preds = %if.end125, %if.end106, %if.end, %land.lhs.true, %entry
  %filename.2 = phi %1* [ %filename.0, %if.end106 ], [ %filename.0, %if.end125 ], [ %tmp, %land.lhs.true ], [ null, %entry ], [ %tmp, %if.end ]
  %origFilename.0 = phi %1* [ %tmp, %if.end106 ], [ %tmp, %if.end125 ], [ %tmp, %land.lhs.true ], [ null, %entry ], [ %tmp, %if.end ]
  %url.2 = phi %5* [ %tmp20, %if.end106 ], [ %url.129, %if.end125 ], [ null, %land.lhs.true ], [ null, %entry ], [ %tmp13, %if.end ]
  call void @objc_release(i8* %tmp9) nounwind, !clang.imprecise_release !0
  %tmp29 = bitcast %5* %url.2 to i8*
  call void @objc_release(i8* %tmp29) nounwind, !clang.imprecise_release !0
  %tmp30 = bitcast %1* %origFilename.0 to i8*
  call void @objc_release(i8* %tmp30) nounwind, !clang.imprecise_release !0
  %tmp31 = bitcast %1* %filename.2 to i8*
  call void @objc_release(i8* %tmp31) nounwind, !clang.imprecise_release !0
  call void @objc_release(i8* %tmp7) nounwind, !clang.imprecise_release !0
  ret void
}

!0 = metadata !{}