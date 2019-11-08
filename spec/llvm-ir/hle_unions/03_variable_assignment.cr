require "crystal/lib_tsx"

local_var = 2 || false

# The lock is at the end of the unions
#
# ```
# CHECK: %"(Bool | Int32)" = type { i32, [1 x i64], i32 }
# ```

copy_var = uninitialized Int32 | Bool
asm("# bookmark_assing")
copy_var = local_var

# After the `alloca`, the lock of both variables is initialized as free (1)
#
# ```
# CHECK: %local_var = alloca %"(Bool | Int32)"
# CHECK: [[IR_LOCAL_VAR_LOCK:%.*]] = getelementptr inbounds %"(Bool | Int32)", %"(Bool | Int32)"* %local_var, i32 0, i32 2
# CHECK: call void @spin_init_hle(i32* {{.*}}[[IR_LOCAL_VAR_LOCK]])
#
# CHECK: %copy_var = alloca %"(Bool | Int32)"
# CHECK: [[IR_COPY_VAR_LOCK:%.*]] = getelementptr inbounds %"(Bool | Int32)", %"(Bool | Int32)"* %copy_var, i32 0, i32 2
# CHECK: call void @spin_init_hle(i32* {{.*}}[[IR_COPY_VAR_LOCK]])
# ```

# ```
# CHECK: bookmark_assing
# ```

# To perform the assignment the first step is to read `local_var` within
# `@spin_lock_hle` / @spin_unlock_hle
# and store the content in `[[SAFE_TID:%.*]] = alloca i32` and `[[SAFE_BLOB:%.*]] = alloca [1 x i64]`
#
# ```
# CHECK: [[IR_LOCAL_VAR_LOCK:%.*]] = getelementptr inbounds [[T:.*]], {{.*}}[[T]]* %local_var, i32 0, i32 2
#
# CHECK: call void @spin_lock_hle(i32* {{.*}}[[IR_LOCAL_VAR_LOCK]])
#
# CHECK: [[IR_LOCAL_VAR_TID:%.*]] = getelementptr inbounds [[T:.*]], {{.*}}[[T]]* %local_var, i32 0, i32 0
# CHECK: [[TEMP1:%.*]] = load i32, i32* {{.*}}[[IR_LOCAL_VAR_TID]]
# CHECK: store i32 {{.*}}[[TEMP1]], i32* [[SAFE_TID:%.*]]
#
# CHECK: [[IR_LOCAL_VAR_BLOB:%.*]] = getelementptr inbounds [[T:.*]], {{.*}}[[T]]* %local_var, i32 0, i32 1
# CHECK: [[TEMP1:%.*]] = load [1 x i64], [1 x i64]* {{.*}}[[IR_LOCAL_VAR_BLOB]]
# CHECK: store [1 x i64] {{.*}}[[TEMP1]], [1 x i64]* [[SAFE_BLOB:%.*]]
#
# CHECK: call void @spin_unlock_hle(i32* {{.*}}[[IR_LOCAL_VAR_LOCK]])
# ```
#
# The second step is to perform the store in `copy_var` within
# `@spin_lock_hle` / `@spin_unlock_hle`.
# Note: This is no longer locking the `local_var`.
#
# ```
# CHECK: [[SAFE_TID_VALUE:%.*]] = load i32, i32* [[SAFE_TID:%.*]]
# CHECK: [[SAFE_BLOB_VALUE:%.*]] = load [1 x i64], [1 x i64]* [[SAFE_BLOB:%.*]]
#
# CHECK: [[IR_COPY_VAR_BLOB:%.*]] = getelementptr inbounds [[T:.*]], {{.*}}[[T]]* %copy_var, i32 0, i32 1
# CHECK: [[IR_COPY_VAR_LOCK:%.*]] = getelementptr inbounds [[T:.*]], {{.*}}[[T]]* %copy_var, i32 0, i32 2
#
# CHECK: call void @spin_lock_hle(i32* {{.*}}[[IR_COPY_VAR_LOCK]])
#
# CHECK: [[IR_COPY_VAR_TID:%.*]] = getelementptr inbounds [[T:.*]], {{.*}}[[T]]* %copy_var, i32 0, i32 0
# CHECK: store i32 {{.*}}[[SAFE_TID_VALUE]], i32* {{.*}}[[IR_COPY_VAR_TID]]
# CHECK: store [1 x i64] {{.*}}[[SAFE_BLOB_VALUE]], [1 x i64]* {{.*}}[[IR_COPY_VAR_BLOB]]
#
# CHECK: call void @spin_unlock_hle(i32* {{.*}}[[IR_COPY_VAR_LOCK]])
# ```
