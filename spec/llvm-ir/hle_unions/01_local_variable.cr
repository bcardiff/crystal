require "crystal/lib_tsx"

# The lock is at the end of the unions
#
# ```
# CHECK: %"(Bool | Int32)" = type { i32, [1 x i64], i32 }
# ```

local_var = uninitialized Int32 | Bool

# After the `alloca` the lock is initialized
#
# ```
# CHECK: %local_var = alloca %"(Bool | Int32)"
# CHECK: [[IR_LOCAL_VAR_LOCK:%.*]] = getelementptr inbounds %"(Bool | Int32)", %"(Bool | Int32)"* %local_var, i32 0, i32 2
# CHECK: call void @spin_init_hle(i32* {{.*}}[[IR_LOCAL_VAR_LOCK]])
# ```

int32_type_id = 0.crystal_type_id
# ```
# CHECK: store i32 [[INT32_TID:[0-9]+]], i32* %int32_type_id
# ```

local_var = 2

# ```
# CHECK: [[IR_LOCAL_VAR_BLOB:%.*]] = getelementptr inbounds [[T:.*]], {{.*}}[[T]]* %local_var, i32 0, i32 1
# CHECK: [[IR_LOCAL_VAR_BLOB_AS_INT32:%.*]] = bitcast {{.*}}* {{.*}}[[IR_LOCAL_VAR_BLOB]] to i32*
# CHECK: [[IR_LOCAL_VAR_LOCK:%.*]] = getelementptr inbounds [[T:.*]], {{.*}}[[T]]* %local_var, i32 0, i32 2
#
# CHECK: call void @spin_lock_hle(i32* {{.*}}[[IR_LOCAL_VAR_LOCK]])
#
# CHECK: [[IR_LOCAL_VAR_TID:%.*]] = getelementptr inbounds [[T:.*]], {{.*}}[[T]]* %local_var, i32 0, i32 0
# ```

# The assignment of type (`INT32_TID`) and value (`2`) is performed around
# `@spin_lock_hle` / `@spin_unlock_hle`
#
# ```
# CHECK: store i32 {{.*}}[[INT32_TID]], i32* {{.*}}[[IR_LOCAL_VAR_TID]]
# CHECK: store i32 2, i32* {{.*}}[[IR_LOCAL_VAR_BLOB_AS_INT32]]
#
# CHECK: call void @spin_unlock_hle(i32* {{.*}}[[IR_LOCAL_VAR_LOCK]])
# ```
