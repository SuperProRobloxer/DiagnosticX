--!strict
-- [[ FAULT CATALOG: COMPREHENSIVE ENGINE & SYNTAX TAXONOMY ]] --
-- Encyclopedic database of Luau runtime errors, engine exceptions, syntax failures,
-- and library constraints, with pre-compiled zero-allocation fragment matching.

-- [[ DEPENDENCIES ]] --
local Types = require(script.Parent.Parent.Types)

-- [[ VM OPTIMIZATIONS & LOCALIZED GLOBALS ]] --
local string_find = string.find
local table_insert = table.insert
local table_freeze = table.freeze

-- [[ TYPE DEFINITIONS ]] --
export type FaultRule = {
	Pattern: string,
	ID: string,
	Name: string,
	Mechanism: string,
	Weight: number,
	SuggestedFix: string?,
	Category: string?,
	PossibleReason: string?,
	IsPlain: boolean?,
}

type CompiledFaultRule = {
	Pattern: string,
	IsPlain: boolean,
	Fragment: Types.FaultFragment,
}

-- [[ MODULE DEFINITION ]] --
local FaultCatalog = {}

-- Pre-allocated fallback fragment returned when an error does not match known rules
local FALLBACK_FAULT: Types.FaultFragment = {
	ID = "GENERIC_RUNTIME_EXCEPTION",
	OperationName = "Unhandled Runtime Exception",
	Mechanism = "An unhandled exception propagated to the thread root without a matched catalog rule.",
	Weight = 20,
	SuggestedFix = "Inspect the line of origin, verify instance hierarchy existence, and check calling arguments.",
	Category = "General Runtime",
	PossibleReason = "An unexpected engine condition or unhandled logic branch failed.",
}

-- [[ SECTION 1: RULE TAXONOMY DECLARATION ]] --
local RAW_RULES: { FaultRule } = {
	-- =========================================================================
	-- 1. SYNTAX, COMPILE & MODULE INITIALIZATION FAILURES
	-- =========================================================================
	{
		Pattern = "Expected 'end' %(to close '.-' at line %d+%), got '<eof>'",
		ID = "SYNTAX_UNCLOSED_BLOCK",
		Name = "Missing 'end' Block Terminator (EOF)",
		Mechanism = "A block-level keyword (function, if, for, while, do) was opened, but the file reached the end of script (<eof>) without finding a matching 'end'.",
		Weight = 40,
		Category = "Luau Syntax & Compilation",
		SuggestedFix = "Count your opening block keywords (function, if, for, while, do). Ensure each opened block has a corresponding 'end'.",
	},
	{
		Pattern = "Expected identifier, got",
		ID = "SYNTAX_EXPECTED_IDENTIFIER",
		Name = "Unexpected Token / Reserved Keyword Usage",
		Mechanism = "The Luau parser expected a valid variable name, parameter, or property identifier, but encountered a reserved keyword, operator, or invalid character.",
		Weight = 40,
		Category = "Luau Syntax & Compilation",
		SuggestedFix = "Check for reserved Luau keywords used as variable names (e.g., local local = 1) or stray commas and misplaced operators.",
	},
	{
		Pattern = "Incomplete statement: expected assignment or a function call",
		ID = "SYNTAX_INCOMPLETE_STATEMENT",
		Name = "Incomplete Luau Statement",
		Mechanism = "An expression or standalone value was written on a line without assigning it to a variable or invoking it as a function.",
		Weight = 40,
		Category = "Luau Syntax & Compilation",
		SuggestedFix = "Ensure expressions perform an action or assignment: local result = value, or execute a function call: doSomething().",
	},
	{
		Pattern = "Unclosed string",
		ID = "SYNTAX_UNCLOSED_STRING",
		Name = "Unclosed String Literal",
		Mechanism = "A string literal was opened with quotes (' or \") or multi-line brackets ([=[) but reached the end of the line or file without closing delimiters.",
		Weight = 40,
		Category = "Luau Syntax & Compilation",
		SuggestedFix = "Add the matching closing quotation mark or bracket delimiter on the same line or block.",
	},
	{
		Pattern = "Expected 'then' when parsing if statement",
		ID = "SYNTAX_MISSING_THEN",
		Name = "Missing 'then' Keyword in Conditional",
		Mechanism = "An 'if' or 'elseif' statement condition was declared without the required 'then' keyword.",
		Weight = 40,
		Category = "Luau Syntax & Compilation",
		SuggestedFix = "Add 'then' after the condition: if condition then ... end.",
	},
	{
		Pattern = "Expected 'do' when parsing",
		ID = "SYNTAX_MISSING_DO",
		Name = "Missing 'do' Keyword in Loop",
		Mechanism = "A 'for' or 'while' loop declaration was missing the required 'do' keyword.",
		Weight = 40,
		Category = "Luau Syntax & Compilation",
		SuggestedFix = "Add 'do' after the loop clause: for i = 1, 10 do ... end.",
	},
	{
		Pattern = "Expected closing '%)' to match '%('",
		ID = "SYNTAX_UNMATCHED_PARENTHESIS",
		Name = "Unmatched Opening Parenthesis",
		Mechanism = "A function call, parameter list, or grouping parenthesis was opened '(' but never closed with ')'.",
		Weight = 40,
		Category = "Luau Syntax & Compilation",
		SuggestedFix = "Balance parentheses: verify each '(' has a matching ')' on the same line or block.",
	},
	{
		Pattern = "Requested module experienced an error while loading",
		ID = "MODULE_INITIALIZATION_CRASH",
		Name = "ModuleScript Runtime Initialization Crash",
		Mechanism = "A required ModuleScript threw an unhandled runtime error while executing its body before returning its table.",
		Weight = 40,
		Category = "Module Lifecycle & Loading",
		SuggestedFix = "Open the required ModuleScript and inspect top-level statements outside functions. Wrap volatile initialization calls in pcall.",
	},
	{
		Pattern = "Module code did not return exactly one value",
		ID = "MODULE_MISSING_RETURN",
		Name = "ModuleScript Missing Return Value",
		Mechanism = "A ModuleScript reached its end without returning a value, or returned multiple or zero values.",
		Weight = 40,
		Category = "Module Lifecycle & Loading",
		SuggestedFix = "Ensure the final statement of the ModuleScript returns exactly one value: return ModuleTable.",
	},
	{
		Pattern = "recursive require detected",
		ID = "CIRCULAR_DEPENDENCY_DEADLOCK",
		Name = "Circular Module Dependency Deadlock",
		Mechanism = "Module A requires Module B, while Module B directly or indirectly requires Module A, causing a dependency deadlock.",
		Weight = 40,
		Category = "Module Lifecycle & Loading",
		SuggestedFix = "Break the cycle: pass dependencies as function parameters, apply dependency injection, or move shared data into a separate third ModuleScript.",
	},

	-- =========================================================================
	-- 2. COMMON SCRIPTING MISTAKES & LIBRARY MISUSE
	-- =========================================================================
	{
		Pattern = "is not a valid member of",
		ID = "INVALID_MEMBER_DEREFERENCE",
		Name = "Invalid Instance Child or Property Dereference",
		Mechanism = "Attempted to access a property or child that does not exist on the target Instance (commonly caused by typos or network replication delay).",
		Weight = 40,
		Category = "Instance Tree / Property Dereference",
		SuggestedFix = "Check spelling and PascalCase capitalization (e.g. HumanoidRootPart, Position). If accessing a replicated child, use :WaitForChild(\"Name\", 5).",
	},
	{
		Pattern = "attempt to call method '([^']+)' %(a nil value%)",
		ID = "CALL_ON_NIL_METHOD",
		Name = "Unknown or Misspelled Method Invocation",
		Mechanism = "Invoked a non-existent method using colon syntax on an object (e.g. part:destory() instead of part:Destroy()).",
		Weight = 40,
		Category = "API Invocation Mismatch",
		SuggestedFix = "Check method spelling and capitalization: use :Destroy() not :destroy(), :FindFirstChild() not :findFirstChild().",
	},
	{
		Pattern = "attempt to call field '([^']+)' %(a nil value%)",
		ID = "CALL_ON_NIL_FIELD",
		Name = "Unassigned Table Field Invocation",
		Mechanism = "Invoked a table field that evaluated to nil (e.g. Module.myFunction() when myFunction was never assigned or misspelled).",
		Weight = 40,
		Category = "Table Member Invocation",
		SuggestedFix = "Verify the function is assigned to the table before being called. Check module exports for matching identifiers.",
	},
	{
		Pattern = "bad argument #1 to 'pairs' %(table expected, got nil%)",
		ID = "PAIRS_ON_NIL",
		Name = "Iterating Nil with pairs()",
		Mechanism = "pairs() was passed a nil reference instead of a valid table or dictionary.",
		Weight = 40,
		Category = "Iterator Function Misuse",
		SuggestedFix = "Ensure the table exists before looping: if myTable then for k, v in pairs(myTable) do ... end end.",
	},
	{
		Pattern = "bad argument #1 to 'ipairs' %(table expected, got nil%)",
		ID = "IPAIRS_ON_NIL",
		Name = "Iterating Nil with ipairs()",
		Mechanism = "ipairs() was passed a nil reference instead of a valid array.",
		Weight = 40,
		Category = "Iterator Function Misuse",
		SuggestedFix = "Ensure the array exists before looping: if myArray then for i, v in ipairs(myArray) do ... end end.",
	},
	{
		Pattern = "bad argument #1 to 'insert' %(table expected, got",
		ID = "TABLE_INSERT_ARG_MISMATCH",
		Name = "table.insert Target Parameter Invalid",
		Mechanism = "table.insert() was passed a non-table value as argument 1, or arguments were inverted (e.g. table.insert(value, myTable)).",
		Weight = 40,
		Category = "Table Library Misuse",
		SuggestedFix = "Ensure argument 1 is the table: table.insert(myTable, newItem).",
	},
	{
		Pattern = "interval is empty",
		ID = "MATH_RANDOM_EMPTY_INTERVAL",
		Name = "math.random Inverted / Empty Range",
		Mechanism = "math.random(m, n) was invoked where m > n (e.g. math.random(10, 1)), producing an impossible range.",
		Weight = 40,
		Category = "Math Library Misuse",
		SuggestedFix = "Ensure minimum bound is less than or equal to maximum bound: math.random(math.min(a, b), math.max(a, b)).",
	},
	{
		Pattern = "cannot use ':' to call a function on a table",
		ID = "COLON_DOT_SYNTAX_CONFUSION",
		Name = "Colon vs Dot Method Syntax Confusion",
		Mechanism = "Colon ':' syntax was used on a library function that expects dot '.' syntax (e.g. math:random() instead of math.random()).",
		Weight = 40,
		Category = "API Syntax Mismatch",
		SuggestedFix = "Replace ':' with '.' when calling standard library functions: math.random(), table.insert(), string.sub().",
	},
	{
		Pattern = "Argument 1 missing or nil",
		ID = "MANDATORY_ARGUMENT_MISSING",
		Name = "Required Engine Method Parameter Missing",
		Mechanism = "An engine method was called without providing its mandatory first argument (e.g. TweenService:Create() missing target instance).",
		Weight = 40,
		Category = "Engine API Constraint",
		SuggestedFix = "Check method parameters in the Creator Documentation. Verify all mandatory arguments are non-nil.",
	},
	{
		Pattern = "Unable to cast .- to (Dictionary|Array)",
		ID = "COLLECTION_CAST_MISMATCH",
		Name = "Datatype Mismatch on Engine API Parameter",
		Mechanism = "An engine API expected an array or dictionary table but received an incompatible type (string, number, or Instance).",
		Weight = 40,
		Category = "Engine API Constraint",
		SuggestedFix = "Pass a valid table formatted as required by the API (e.g. RaycastParams.FilterDescendantsInstances = { part1, part2 }).",
	},

	-- =========================================================================
	-- 3. LUAU VM CORE, TYPES & PRIMITIVES
	-- =========================================================================
	{
		Pattern = "attempt to index nil with '([^']+)'",
		ID = "INDEX_ON_NIL",
		Name = "Property Dereference on Nil",
		Mechanism = "The Luau VM attempted to dereference a member key from a nil variable reference.",
		Weight = 40,
		Category = "Memory & Pointer Dereference",
		SuggestedFix = "Ensure the parent table or Instance exists before indexing. Use :WaitForChild() or an early guard: if not var then return end.",
	},
	{
		Pattern = "attempt to index nil with",
		ID = "INDEX_ON_NIL",
		Name = "Member Dereference on Nil",
		Mechanism = "An expression preceding member access evaluated to nil.",
		Weight = 40,
		Category = "Memory & Pointer Dereference",
		SuggestedFix = "Verify that the variable was assigned and not overwritten by an asynchronous callback or nil function return.",
	},
	{
		Pattern = "attempt to index a ([%w_]+) value",
		ID = "INDEX_ON_PRIMITIVE",
		Name = "Invalid Primitive Member Index",
		Mechanism = "Attempted to index a field on a primitive datatype (boolean, number, thread) that does not support table fields.",
		Weight = 40,
		Category = "Type Invariance Violation",
		SuggestedFix = "Check variable assignments. Ensure a table reference was not overwritten with a boolean or number.",
	},
	{
		Pattern = "attempt to call a ([%w_]+) value",
		ID = "CALL_ON_NON_FUNCTION",
		Name = "Invocation of Non-Callable Value",
		Mechanism = "An invocation '()' was attempted on a value lacking a valid function type or __call metamethod.",
		Weight = 40,
		Category = "Type Invariance Violation",
		SuggestedFix = "Verify that the function name is spelled correctly and that you did not accidentally call a table without specifying the method.",
	},
	{
		Pattern = "attempt to perform arithmetic on a ([%w_]+) value",
		ID = "ARITHMETIC_ON_INVALID_TYPE",
		Name = "Arithmetic Datatype Mismatch",
		Mechanism = "A math operator (+, -, *, /, ^, %) was evaluated on an incompatible datatype (e.g., Instance, table, or nil).",
		Weight = 40,
		Category = "Type Invariance Violation",
		SuggestedFix = "Ensure all operands are numbers or mathematical structs (Vector3, CFrame). Use tonumber() on strings or read .Value from ValueObjects.",
	},
	{
		Pattern = "attempt to concatenate a ([%w_]+) value",
		ID = "CONCATENATION_MISMATCH",
		Name = "String Concatenation Mismatch",
		Mechanism = "The concatenation operator '..' was used on a datatype that cannot be automatically cast to string.",
		Weight = 40,
		Category = "Type Invariance Violation",
		SuggestedFix = "Wrap non-string operands in tostring() or use string.format() before concatenating.",
	},
	{
		Pattern = "attempt to compare ([%w_]+) with ([%w_]+)",
		ID = "COMPARISON_TYPE_MISMATCH",
		Name = "Relational Comparison Mismatch",
		Mechanism = "Relational operators (<, <=, >, >=) were applied across two distinct, incompatible datatypes.",
		Weight = 40,
		Category = "Type Invariance Violation",
		SuggestedFix = "Compare values of identical types. Ensure neither side of the comparison evaluates to nil.",
	},
	{
		Pattern = "attempt to get length of a ([%w_]+) value",
		ID = "LENGTH_OPERATOR_MISMATCH",
		Name = "Length Operator Mismatch",
		Mechanism = "The '#' length operator was used on a datatype that lacks length semantics (e.g., number, boolean, Instance).",
		Weight = 40,
		Category = "Type Invariance Violation",
		SuggestedFix = "Only use '#' on arrays, tables with array components, strings, or buffers. For instances, use #instance:GetChildren().",
	},
	{
		Pattern = "table index is nil",
		ID = "TABLE_INDEX_NIL",
		Name = "Table Assignment with Nil Key",
		Mechanism = "Attempted to use nil as an associative key: tbl[nil] = value.",
		Weight = 40,
		Category = "Table Key Constraint",
		SuggestedFix = "Verify that the variable representing the table key is properly initialized and non-nil before assignment.",
	},
	{
		Pattern = "table index is NaN",
		ID = "TABLE_INDEX_NAN",
		Name = "Table Assignment with NaN Key",
		Mechanism = "A mathematical expression evaluating the table key resulted in Not-a-Number (NaN) through 0/0 or invalid math.",
		Weight = 40,
		Category = "Table Key Constraint",
		SuggestedFix = "Check the math calculation producing the key. Guard against division by zero: if denom == 0 then return end.",
	},
	{
		Pattern = "attempt to modify a readonly table",
		ID = "READONLY_TABLE_MUTATION",
		Name = "Readonly Table Mutation Violation",
		Mechanism = "Attempted to write a key to a table that has been locked with table.freeze().",
		Weight = 40,
		Category = "Memory & Pointer Dereference",
		SuggestedFix = "Frozen tables are immutable. If modification is required, clone the table with table.clone() prior to mutating.",
	},
	{
		Pattern = "attempt to yield across a C%-call boundary",
		ID = "YIELD_ACROSS_C_BOUNDARY",
		Name = "C-Boundary Yield Violation",
		Mechanism = "A thread attempted to yield inside an engine metamethod (__index, __newindex) or C-pcall boundary.",
		Weight = 40,
		Category = "Thread Concurrency & Scheduling",
		SuggestedFix = "Move yielding operations into task.defer or task.spawn, or avoid calling synchronous yielding APIs inside metamethods.",
	},
	{
		Pattern = "stack overflow",
		ID = "STACK_OVERFLOW",
		Name = "Call-Stack Exhaustion / Infinite Recursion",
		Mechanism = "A function repeatedly called itself without reaching a termination base case, exceeding the Luau call-stack depth.",
		Weight = 40,
		Category = "Thread Concurrency & Scheduling",
		SuggestedFix = "Check recursive functions for missing base cases. Guard against circular event loops (e.g., event handler modifying its own source property).",
	},
	{
		Pattern = "Maximum event re%-entrancy depth exceeded",
		ID = "EVENT_REENTRANCY_OVERFLOW",
		Name = "Maximum Event Re-entrancy Depth Exceeded",
		Mechanism = "A signal listener modified the property it was listening to, causing it to recursively fire itself until exceeding the engine re-entrancy ceiling.",
		Weight = 45,
		Category = "Thread Concurrency & Scheduling",
		SuggestedFix = "Disconnect the listener before modifying the property, or add a re-entrancy boolean lock to prevent recursive fires.",
	},
	{
		Pattern = "buffer out of bounds",
		ID = "BUFFER_OUT_OF_BOUNDS",
		Name = "Buffer Memory Bounds Violation",
		Mechanism = "Attempted to read or write beyond the allocated byte capacity of a Luau buffer object.",
		Weight = 40,
		Category = "Memory & Pointer Dereference",
		SuggestedFix = "Verify buffer offsets and lengths. Ensure offset + write_size <= buffer.len(targetBuffer).",
	},

	-- =========================================================================
	-- 4. COROUTINE & THREAD LIFECYCLE
	-- =========================================================================
	{
		Pattern = "cannot resume dead coroutine",
		ID = "DEAD_COROUTINE_RESUMPTION",
		Name = "Dead Coroutine Resumption",
		Mechanism = "An execution attempt was made on a coroutine thread that has already completed, suspended permanently, or crashed.",
		Weight = 40,
		Category = "Thread Concurrency & Scheduling",
		SuggestedFix = "Check coroutine.status(thread). Instantiate a new thread via task.spawn or coroutine.create rather than resuming a finished thread.",
	},
	{
		Pattern = "cannot resume non%-suspended coroutine",
		ID = "COROUTINE_ALREADY_RUNNING",
		Name = "Active Coroutine Collision",
		Mechanism = "coroutine.resume() was called on a thread that is currently executing or active.",
		Weight = 40,
		Category = "Thread Concurrency & Scheduling",
		SuggestedFix = "Ensure the thread has yielded (coroutine.yield) before attempting to resume it.",
	},
	{
		Pattern = "task.cancel cannot cancel a thread",
		ID = "TASK_CANCEL_INVALID_STATE",
		Name = "Task Cancellation State Conflict",
		Mechanism = "task.cancel() was invoked on a thread that is either currently executing or has already terminated.",
		Weight = 40,
		Category = "Thread Concurrency & Scheduling",
		SuggestedFix = "Verify coroutine.status(thread) == 'suspended' before invoking task.cancel().",
	},
	{
		Pattern = "The current thread cannot be yielded",
		ID = "CANNOT_YIELD_THREAD",
		Name = "Illegal Yield in Non-Yieldable Thread",
		Mechanism = "Attempted to invoke task.wait() or a yielding method inside an engine callback that forbids yielding (such as certain bindable functions or physics steps).",
		Weight = 40,
		Category = "Thread Concurrency & Scheduling",
		SuggestedFix = "Wrap the yielding call inside task.spawn(function() ... end) to yield on an independent coroutine.",
	},

	-- =========================================================================
	-- 5. PARALLEL LUAU & ACTOR RESTRICTIONS
	-- =========================================================================
	{
		Pattern = "Cannot write to DataModel while desynchronized",
		ID = "PARALLEL_DESYNC_WRITE",
		Name = "Parallel Desynchronized Write Violation",
		Mechanism = "A Parallel Luau Actor thread attempted to modify an Instance property while desynchronized.",
		Weight = 40,
		Category = "Parallel Luau & Actor Safety",
		SuggestedFix = "Call task.synchronize() before mutating Instance properties, parenting, or destroying objects in Parallel Luau.",
	},
	{
		Pattern = "Cannot access non%-parallel safe Instance",
		ID = "PARALLEL_THREAD_UNSAFE_READ",
		Name = "Thread-Unsafe Instance Query in Parallel",
		Mechanism = "An Actor thread attempted to read a thread-unsafe engine property or service while running in parallel.",
		Weight = 40,
		Category = "Parallel Luau & Actor Safety",
		SuggestedFix = "Read all necessary configuration data prior to task.desynchronize(), or call task.synchronize() to perform the query.",
	},

	-- =========================================================================
	-- 6. DATAMODEL HIERARCHY, PARENTING & LIFECYCLE
	-- =========================================================================
	{
		Pattern = "Infinite yield possible on '([^']+)'",
		ID = "INFINITE_YIELD",
		Name = "Indefinite Synchronous Yield",
		Mechanism = "A thread yielded on :WaitForChild() for an Instance that was never replicated, never instantiated, or destroyed.",
		Weight = 40,
		Category = "Instance Tree / Hierarchy Mutation",
		SuggestedFix = "Supply a timeout argument: parent:WaitForChild('Child', 5), and check naming or server creation logic.",
	},
	{
		Pattern = "The Parent property of (.-) is locked",
		ID = "LOCKED_PARENT_MUTATION",
		Name = "Locked Hierarchy Parent Mutation",
		Mechanism = "Attempted to re-parent an Instance whose Parent property is permanently locked during its current lifecycle phase.",
		Weight = 40,
		Category = "Instance Tree / Hierarchy Mutation",
		SuggestedFix = "Avoid reparenting objects while they are undergoing engine deletion or within restricted container callbacks.",
	},
	{
		Pattern = "Parent of (.-) cannot be set to",
		ID = "CIRCULAR_PARENT_MUTATION",
		Name = "Circular / Self-Ancestry Assignment",
		Mechanism = "Attempted to set an Instance's Parent to itself or one of its descendants, causing a circular tree hierarchy.",
		Weight = 40,
		Category = "Instance Tree / Hierarchy Mutation",
		SuggestedFix = "Verify the target parent instance. Ensure that target ~= object and not target:IsDescendantOf(object).",
	},
	{
		Pattern = "Attempt to set the parent of Workspace",
		ID = "PARENT_WORKSPACE_VIOLATION",
		Name = "Illegal Workspace Reparenting",
		Mechanism = "Workspace is the root spatial DataModel container and cannot have its Parent property modified.",
		Weight = 45,
		Category = "Instance Tree / Hierarchy Mutation",
		SuggestedFix = "Do not set Workspace.Parent. Workspace must remain a top-level child of game.",
	},
	{
		Pattern = "Cannot clone an Instance that has Archivable set to false",
		ID = "CLONE_NON_ARCHIVABLE",
		Name = "Non-Archivable Instance Clone Attempt",
		Mechanism = "Instance:Clone() was invoked on an object with Archivable = false, which causes Clone() to return nil.",
		Weight = 40,
		Category = "Instance Tree / Hierarchy Mutation",
		SuggestedFix = "Set targetInstance.Archivable = true before cloning, or verify that the template model allows duplication.",
	},

	-- =========================================================================
	-- 7. PHYSICS, ASSEMBLIES & SPATIAL QUERIES
	-- =========================================================================
	{
		Pattern = "CFrame contains NaN or infinite",
		ID = "CFRAME_NAN_INFINITE",
		Name = "NaN / Infinite CFrame Assignment",
		Mechanism = "A CFrame assignment contained invalid float values (NaN, inf) resulting from division by zero or invalid vector math.",
		Weight = 40,
		Category = "Physics & Spatial Constraints",
		SuggestedFix = "Check vector calculations. Guard directional look-ats: if direction.Magnitude == 0 then return end.",
	},
	{
		Pattern = "AssemblyLinearVelocity contains NaN",
		ID = "VELOCITY_NAN",
		Name = "Assembly Velocity NaN Invalidation",
		Mechanism = "Physics assembly velocities became invalid due to infinite impulse forces or 0/0 vector calculations.",
		Weight = 40,
		Category = "Physics & Spatial Constraints",
		SuggestedFix = "Verify force vectors. Clamp impulse values and verify that delta-time is non-zero before calculating acceleration.",
	},
	{
		Pattern = "AssemblyMass cannot be zero or negative",
		ID = "INVALID_ASSEMBLY_MASS",
		Name = "Zero / Negative Mass Assembly Violation",
		Mechanism = "A root assembly has no physical parts with positive mass, or an attachment/constraint attempted invalid mass math.",
		Weight = 40,
		Category = "Physics & Spatial Constraints",
		SuggestedFix = "Ensure at least one BasePart in the assembly has Massless = false and valid non-zero dimensions.",
	},
	{
		Pattern = "WeldConstraint contains cyclic physics loop",
		ID = "CYCLIC_CONSTRAINT_LOOP",
		Name = "Cyclic Physics Constraint Loop",
		Mechanism = "Constraints connect two parts in an infinite cyclic loop, preventing rigid body assembly resolution.",
		Weight = 40,
		Category = "Physics & Spatial Constraints",
		SuggestedFix = "Inspect WeldConstraints and Motor6Ds. Ensure parts are arranged in a hierarchical tree without loops.",
	},
	{
		Pattern = "The Part passed to SetNetworkOwner cannot be anchored",
		ID = "NETWORK_OWNER_ANCHORED",
		Name = "Network Ownership on Anchored Part",
		Mechanism = "SetNetworkOwner() was called on an anchored BasePart. Anchored parts are non-physical and simulated server-side.",
		Weight = 45,
		Category = "Physics & Spatial Constraints",
		SuggestedFix = "Unanchor the part before setting network ownership: part.Anchored = false.",
	},
	{
		Pattern = "The Part passed to SetNetworkOwner must be a BasePart",
		ID = "NETWORK_OWNER_NON_PART",
		Name = "Network Ownership Target Not a BasePart",
		Mechanism = "SetNetworkOwner() was called on a Model, Folder, or non-physical instance rather than a BasePart.",
		Weight = 40,
		Category = "Physics & Spatial Constraints",
		SuggestedFix = "Invoke SetNetworkOwner on the assembly's PrimaryPart or root BasePart: model.PrimaryPart:SetNetworkOwner(player).",
	},
	{
		Pattern = "SetNetworkOwner can only be called from the server",
		ID = "NETWORK_OWNER_CLIENT_CALL",
		Name = "Client-Side Network Ownership Mutation",
		Mechanism = "SetNetworkOwner() was invoked from a client LocalScript. Network authority is strictly server-managed.",
		Weight = 40,
		Category = "Physics & Spatial Constraints",
		SuggestedFix = "Move all SetNetworkOwner and SetNetworkOwnershipAuto calls into server-side scripts in ServerScriptService.",
	},
	{
		Pattern = "RaycastParams filter table exceeds",
		ID = "RAYCAST_FILTER_OVERFLOW",
		Name = "Raycast Filter Table Limit Exceeded",
		Mechanism = "RaycastParams.FilterDescendantsInstances received an array exceeding the engine's hard instance limit.",
		Weight = 40,
		Category = "Physics & Spatial Constraints",
		SuggestedFix = "Filter higher-level container Folders or Models rather than individual parts, or clean up dead instances before querying.",
	},

	-- =========================================================================
	-- 8. TWEEN SERVICE & INTERPOLATION
	-- =========================================================================
	{
		Pattern = "TweenService:Create property .- is not a valid property",
		ID = "TWEEN_INVALID_PROPERTY",
		Name = "Invalid Property in Tween Goals",
		Mechanism = "TweenService:Create() received a goals dictionary containing a property that does not exist on the target Instance.",
		Weight = 40,
		Category = "Animation & Interpolation",
		SuggestedFix = "Verify property names in the goals dictionary for typos and correct casing (e.g. CFrame, Transparency, Size).",
	},
	{
		Pattern = "TweenInfo.new: time cannot be negative",
		ID = "TWEEN_NEGATIVE_TIME",
		Name = "Negative Duration in TweenInfo",
		Mechanism = "TweenInfo.new() received a duration less than 0 seconds.",
		Weight = 40,
		Category = "Animation & Interpolation",
		SuggestedFix = "Ensure duration is non-negative: TweenInfo.new(math.max(0, duration), ...).",
	},

	-- =========================================================================
	-- 9. NETWORKING, REPLICATION & REMOTES
	-- =========================================================================
	{
		Pattern = "FireServer can only be called from the client",
		ID = "FIRE_SERVER_ON_SERVER",
		Name = "Illegal Server-Side FireServer",
		Mechanism = "RemoteEvent:FireServer() was called from a server Script. FireServer can only be invoked by client LocalScripts.",
		Weight = 45,
		Category = "Networking & RPC Pipeline",
		SuggestedFix = "Use remote:FireClient(player) or remote:FireAllClients() when sending data from server to client.",
	},
	{
		Pattern = "FireAllClients can only be called from the server",
		ID = "FIRE_ALL_CLIENTS_ON_CLIENT",
		Name = "Illegal Client-Side FireAllClients",
		Mechanism = "RemoteEvent:FireAllClients() was called from a client LocalScript. Only the server can broadcast to all clients.",
		Weight = 45,
		Category = "Networking & RPC Pipeline",
		SuggestedFix = "Call remote:FireServer() from the client and let the server validate the broadcast request.",
	},
	{
		Pattern = "InvokeClient cannot be called from the client",
		ID = "INVOKE_CLIENT_AUTHORITY",
		Name = "Illegal Client-Side InvokeClient",
		Mechanism = "RemoteFunction:InvokeClient() was called from a LocalScript. InvokeClient is strictly server-authoritative.",
		Weight = 40,
		Category = "Networking & RPC Pipeline",
		SuggestedFix = "Clients must call RemoteFunction:InvokeServer() to initiate RPCs. Use RemoteEvents for server-to-client communication.",
	},
	{
		Pattern = "InvokeClient cannot be called without a player",
		ID = "INVOKE_CLIENT_MISSING_PLAYER",
		Name = "InvokeClient Missing Player Parameter",
		Mechanism = "RemoteFunction:InvokeClient() was called without a valid Player instance as the first argument.",
		Weight = 40,
		Category = "Networking & RPC Pipeline",
		SuggestedFix = "Pass the target Player as argument 1: remoteFunction:InvokeClient(targetPlayer, ...).",
	},
	{
		Pattern = "FireClient: player argument must be a Player",
		ID = "FIRE_CLIENT_MISSING_PLAYER",
		Name = "RemoteEvent FireClient Missing Player",
		Mechanism = "RemoteEvent:FireClient() requires a valid Player instance as argument 1, but received nil or an incompatible type.",
		Weight = 40,
		Category = "Networking & RPC Pipeline",
		SuggestedFix = "Verify that the player variable is valid: if player and player:IsA('Player') then remote:FireClient(player) end.",
	},
	{
		Pattern = "Cannot send table with cyclic references",
		ID = "REMOTE_CYCLIC_TABLE",
		Name = "Cyclic Table Serialization in Remote Call",
		Mechanism = "A table passed across a RemoteEvent or RemoteFunction contains self-referencing tables, which the network serializer cannot encode.",
		Weight = 45,
		Category = "Networking & RPC Pipeline",
		SuggestedFix = "Remove cyclic references or construct a clean, non-circular transfer dictionary prior to transmission.",
	},
	{
		Pattern = "UnreliableRemoteEvent payload exceeds",
		ID = "UNRELIABLE_PAYLOAD_OVERFLOW",
		Name = "UnreliableRemoteEvent Packet Size Overflow",
		Mechanism = "An UnreliableRemoteEvent fired a packet exceeding the hard 900-byte network limit.",
		Weight = 40,
		Category = "Networking & RPC Pipeline",
		SuggestedFix = "Compress or truncate the payload. For data larger than 900 bytes, use a standard reliable RemoteEvent.",
	},

	-- =========================================================================
	-- 10. CLOUD PERSISTENCE & DATASTORES
	-- =========================================================================
	{
		Pattern = "502: API Services rejected request",
		ID = "DATASTORE_SATURATION",
		Name = "DataStore Service Saturation (502)",
		Mechanism = "Engine cloud persistence throughput exceeded allowable per-key or per-server request budgets.",
		Weight = 40,
		Category = "Cloud Persistence & DataStores",
		SuggestedFix = "Implement write coalescing, cache values in memory, and back off requests with exponential jitter.",
	},
	{
		Pattern = "Cannot write to DataStore from client",
		ID = "DATASTORE_CLIENT_ACCESS",
		Name = "Client-Side DataStore Access Prohibited (104)",
		Mechanism = "A LocalScript attempted to read or write to DataStoreService. DataStores are strictly server-authoritative.",
		Weight = 40,
		Category = "Cloud Persistence & DataStores",
		SuggestedFix = "Move all DataStore operations into server Scripts in ServerScriptService. Relay data to client via Remotes.",
	},
	{
		Pattern = "Key name can't be empty",
		ID = "DATASTORE_EMPTY_KEY",
		Name = "Empty DataStore Key (101)",
		Mechanism = "A DataStore read or write was attempted with an empty string key (\"\").",
		Weight = 40,
		Category = "Cloud Persistence & DataStores",
		SuggestedFix = "Validate keys before querying: if key == '' or type(key) ~= 'string' then return end.",
	},
	{
		Pattern = "MemoryStoreService: Hash key size limit exceeded",
		ID = "MEMORY_STORE_KEY_LIMIT",
		Name = "MemoryStore Key Size Limit Exceeded",
		Mechanism = "A key stored in MemoryStoreService exceeded the maximum byte length limit.",
		Weight = 40,
		Category = "Cloud Persistence & DataStores",
		SuggestedFix = "Shorten the partition key or use a hash (SHA/MD5) representation of large key strings.",
	},

	-- =========================================================================
	-- 11. HTTP SERVICE & EXTERNAL WEB APIS
	-- =========================================================================
	{
		Pattern = "HttpService is not enabled",
		ID = "HTTP_SERVICE_DISABLED",
		Name = "HttpService Security Disabled",
		Mechanism = "An HTTP request was issued, but 'Allow HTTP Requests' is toggled off in Game Settings.",
		Weight = 40,
		Category = "External HTTP & Web Services",
		SuggestedFix = "Open Studio -> Home -> Game Settings -> Security -> Toggle ON 'Allow HTTP Requests'.",
	},
	{
		Pattern = "HTTP 429",
		ID = "HTTP_429_RATE_LIMITED",
		Name = "HTTP Rate Limit Exceeded (429)",
		Mechanism = "Roblox or the external web server rejected requests due to exceeding rate limits (500 requests/min ceiling).",
		Weight = 40,
		Category = "External HTTP & Web Services",
		SuggestedFix = "Implement request throttling, cache external responses in memory, and back off requests using task.delay.",
	},
	{
		Pattern = "JSON decode failed",
		ID = "HTTP_JSON_PARSE_ERROR",
		Name = "JSON Deserialization Syntax Error",
		Mechanism = "HttpService:JSONDecode() was passed invalid or malformed JSON text.",
		Weight = 40,
		Category = "External HTTP & Web Services",
		SuggestedFix = "Wrap JSONDecode in pcall. Inspect the raw HTTP response body to verify the server returned valid JSON.",
	},

	-- =========================================================================
	-- 12. ANIMATIONS & HUMANOID RIGS
	-- =========================================================================
	{
		Pattern = "cannot be played without Animator",
		ID = "ANIMATION_WITHOUT_ANIMATOR",
		Name = "Animation Played Without Animator",
		Mechanism = "AnimationTrack:Play() was called on a model lacking an active Animator instance inside its Humanoid or AnimationController.",
		Weight = 40,
		Category = "Animation & Rig Lifecycles",
		SuggestedFix = "Ensure an Animator instance exists inside the Humanoid or AnimationController before calling LoadAnimation.",
	},
	{
		Pattern = "Cannot change Humanoid state while in dead state",
		ID = "HUMANOID_STATE_CHANGE_DEAD",
		Name = "Dead Humanoid State Mutation",
		Mechanism = "Attempted to invoke ChangeState() on a Humanoid whose current state is already Enum.HumanoidStateType.Dead.",
		Weight = 40,
		Category = "Animation & Rig Lifecycles",
		SuggestedFix = "Guard state changes: if humanoid:GetState() == Enum.HumanoidStateType.Dead then return end.",
	},
	{
		Pattern = "Humanoid:ApplyDescription%(%) failed",
		ID = "APPLY_DESCRIPTION_FAIL",
		Name = "HumanoidDescription Asset Load Failure",
		Mechanism = "Humanoid:ApplyDescription() failed to load one or more accessory, shirt, or pants asset IDs.",
		Weight = 40,
		Category = "Animation & Rig Lifecycles",
		SuggestedFix = "Wrap ApplyDescription in pcall. Verify all asset IDs exist and are approved on the Roblox Creator Store.",
	},

	-- =========================================================================
	-- 13. MONETIZATION & MARKETPLACE
	-- =========================================================================
	{
		Pattern = "Third%-party sales are disabled",
		ID = "THIRD_PARTY_SALES_DISABLED",
		Name = "Third-Party Purchase Blocked",
		Mechanism = "MarketplaceService prompted a purchase for an asset owned by an external creator, but Third-Party Sales are disabled.",
		Weight = 40,
		Category = "Commerce & Monetization",
		SuggestedFix = "Open Game Settings -> Security -> Toggle ON 'Allow Third-Party Sales' if this experience sells external items.",
	},
	{
		Pattern = "ProcessReceipt callback must return",
		ID = "PROCESS_RECEIPT_INVALID_RETURN",
		Name = "ProcessReceipt Invalid Decision Return",
		Mechanism = "MarketplaceService.ProcessReceipt did not return Enum.ProductPurchaseDecision.PurchaseGranted or NotProcessedYet.",
		Weight = 40,
		Category = "Commerce & Monetization",
		SuggestedFix = "Ensure all code paths in ProcessReceipt return Enum.ProductPurchaseDecision.PurchaseGranted upon success.",
	},

	-- =========================================================================
	-- 14. AUDIO, WIRE & TELEPORTATION
	-- =========================================================================
	{
		Pattern = "Wire: source and target must be in the same DataModel",
		ID = "WIRE_DATAMODEL_MISMATCH",
		Name = "Wire Cross-DataModel Connection Violation",
		Mechanism = "A Wire instance attempted to link an AudioSource and AudioSink that reside in different DataModels.",
		Weight = 40,
		Category = "Audio & Wire Subsystems",
		SuggestedFix = "Ensure both the audio source instance and target sink instance reside under Workspace.",
	},
	{
		Pattern = "AudioEmitter must be parented",
		ID = "AUDIO_EMITTER_INVALID_PARENT",
		Name = "AudioEmitter Hierarchy Invalid",
		Mechanism = "An AudioEmitter instance must be parented to a BasePart or Attachment to emit spatialized audio.",
		Weight = 40,
		Category = "Audio & Wire Subsystems",
		SuggestedFix = "Parent the AudioEmitter to a valid Part, MeshPart, or Attachment in Workspace.",
	},
	{
		Pattern = "Cannot teleport in the Studio",
		ID = "TELEPORT_IN_STUDIO",
		Name = "Studio Teleportation Restriction",
		Mechanism = "TeleportService cannot transfer players between experiences while running in Roblox Studio.",
		Weight = 40,
		Category = "Teleportation & Place Boundaries",
		SuggestedFix = "Guard teleports with: if RunService:IsStudio() then warn('Teleport bypassed in Studio') return end.",
	},
}

-- [[ SECTION 2: COMPILATION & FAST-PATH PRE-PROCESSING ]] --
--[[
	Detects if a pattern contains Luau regex magic characters: ^ $ ( ) % [ ] * + - ?
]]
local function containsPatternMagic(pattern: string): boolean
	return string_find(pattern, "[%^%$%(%)%%%[%]%*%+%-%?]") ~= nil
end

--[[
	Compiles a raw FaultRule into an execution rule containing its pre-allocated
	Types.FaultFragment and plain-search optimization flag.
]]
local function compileRule(rule: FaultRule): CompiledFaultRule
	local isPlain: boolean = if rule.IsPlain ~= nil then (rule.IsPlain == true) else not containsPatternMagic(rule.Pattern)

	local fragment: Types.FaultFragment = {
		ID = rule.ID,
		OperationName = rule.Name,
		Mechanism = rule.Mechanism,
		Weight = rule.Weight,
		SuggestedFix = rule.SuggestedFix,
		Category = rule.Category,
		PossibleReason = rule.PossibleReason,
	}

	return {
		Pattern = rule.Pattern,
		IsPlain = isPlain,
		Fragment = fragment,
	}
end

-- Pre-compile the initial rule set
local compiledRules: { CompiledFaultRule } = {}
for i = 1, #RAW_RULES do
	table_insert(compiledRules, compileRule(RAW_RULES[i]))
end

-- [[ SECTION 3: PUBLIC API ]] --
--[[
	Registers a custom diagnostic rule at the front of the catalog, giving it priority.
]]
function FaultCatalog.RegisterRule(rule: FaultRule)
	local compiled = compileRule(rule)
	table_insert(compiledRules, 1, compiled)
end

--[[
	Batch registers an array of custom diagnostic rules.
]]
function FaultCatalog.RegisterRules(rules: { FaultRule })
	for i = 1, #rules do
		local compiled = compileRule(rules[i])
		table_insert(compiledRules, compiled)
	end
end

--[[
	Matches an error message against registered rules using fast plain search
	when available, returning pre-allocated fragments with zero heap allocations.
]]
function FaultCatalog.Match(message: string): Types.FaultFragment
	for i = 1, #compiledRules do
		local rule = compiledRules[i]

		if rule.IsPlain then
			-- Boyer-Moore fast substring search bypasses the pattern-matching state machine
			if string_find(message, rule.Pattern, 1, true) then
				return rule.Fragment
			end
		else
			-- Standard Luau regex pattern match
			if string_find(message, rule.Pattern) then
				return rule.Fragment
			end
		end
	end

	return FALLBACK_FAULT
end

return table_freeze(FaultCatalog)
