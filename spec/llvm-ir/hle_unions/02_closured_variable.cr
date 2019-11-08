require "crystal/lib_tsx"

# The lock is at the end of the unions
#
# ```
# CHECK: %"(Bool | Int32)" = type { i32, [1 x i64], i32 }
# ```

closured_var = uninitialized Int32 | Bool

# After the closured is allocated in thh heap, the lock is initialized
#
# ```
# CHECK: [[IR_CLOSURED_VAR_ALLOC:%.*]] = call i8* @malloc(i64 ptrtoint (%"(Bool | Int32)"* getelementptr (%"(Bool | Int32)", %"(Bool | Int32)"* null, i32 1) to i64))
# CHECK: [[IR_CLOSURED_VAR_ALLOC_CAST:%.*]] = bitcast i8* {{.*}}[[IR_CLOSURED_VAR_ALLOC]] to %closure_1*
# CHECK: %closured_var = getelementptr inbounds %closure_1, %closure_1* {{.*}}[[IR_CLOSURED_VAR_ALLOC_CAST]], i32 0, i32 0
#
# CHECK: [[IR_CLOSURED_VAR_LOCK:%.*]] = getelementptr inbounds [[T:.*]], {{.*}}[[T]]* %closured_var, i32 0, i32 2
# CHECK: call void @spin_init_hle(i32* {{.*}}[[IR_CLOSURED_VAR_LOCK]])
# ```

int32_type_id = 0.crystal_type_id
# ```
# CHECK: store i32 [[INT32_TID:[0-9]+]], i32* %int32_type_id
# ```

set_var = ->{
  # `closured_var` is obtained from the closure argument `%0`
  #
  # ```
  # CHECK: %1 = bitcast i8* %0 to %closure_1*
  # CHECK: %closured_var = getelementptr inbounds %closure_1, %closure_1* %1, i32 0, i32 0
  # ```

  asm("# bookmark_set_var")
  # ```
  # CHECK: bookmark_set_var
  # ```

  closured_var = 2
  # The assignment of type (`INT32_TID`) and value (`2`) is performed around
  # `@spin_lock_hle` / `@spin_unlock_hle`
  #
  # ```
  # CHECK: [[IR_CLOSURED_VAR_BLOB:%.*]] = getelementptr inbounds [[T:.*]], {{.*}}[[T]]* %closured_var, i32 0, i32 1
  # CHECK: [[IR_CLOSURED_VAR_BLOB_AS_INT32:%.*]] = bitcast [1 x i64]* {{.*}}[[IR_CLOSURED_VAR_BLOB]] to i32*
  # CHECK: [[IR_CLOSURED_VAR_LOCK:%.*]] = getelementptr inbounds [[T:.*]], {{.*}}[[T]]* %closured_var, i32 0, i32 2
  #
  # CHECK: call void @spin_lock_hle(i32* {{.*}}[[IR_CLOSURED_VAR_LOCK]])
  #
  # CHECK: [[IR_CLOSURED_VAR_TID:%.*]] = getelementptr inbounds [[T:.*]], {{.*}}[[T]]* %closured_var, i32 0, i32 0
  # CHECK: store i32 {{.*}}[[INT32_TID]], i32* {{.*}}[[IR_CLOSURED_VAR_TID]]
  # CHECK: store i32 2, i32* {{.*}}[[IR_CLOSURED_VAR_BLOB_AS_INT32]]
  #
  # CHECK: call void @spin_unlock_hle(i32* %5)
  # ```
}
