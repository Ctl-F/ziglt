#META: The language seeks to be low-level and zig-flavored

## Variables
# const by default
# mutable available
# mutable variables must be mutated
# all variables must be used or explicitly discarded

const [varname]: [type] = [expr];

var [varname]: [type] = [expr];
varname += expr;

_ = [varname]


## Comments
// this is a comment
// this is really the only comment type available

## Types
u8, u16, u32, u64,
i8, i16, i32, i64,
f32, f64, void, anyopaque,

## Slices
[]type, []const type


Strings are treated as []const u8. They are not null-terminated by default


## Arrays
[size]type, [size]const type

Arrays are initialized like such:
[size]type { ... };
[_]type { ... }; // size is detected by params

Arrays can be "multiplied" or auto sized by a comptime integer

[_]i32 { 0 } ** 100; // produces a 100 long zero-initialized i32 array


## SIMD
SIMD (Vector) types are explicit and follow Zig's model for version 0.1.
The valid SIMD array types are:
[2]u64/i64/f64/u32/i32/f32/u16/i16/u8/i8/bool
[4]u32/i32/f32/u16/i16/u8/i8/bool
[8]u16/i16/u8/i8/bool
[16]u8/i8/bool

An array of any other size or type cannot be treated as a SIMD vector.
Operations that are valid on Vector Arrays:
+ - * / %
@shuffle(...), @select(...), @abs(...), @max(...), @min(...), @reduce(...), @sqrt(...), @exp(...), @exp2(...),
@sin(...), @cos(...), @tan(...), @round(...), @floor(...), @ceil(...),
scalars can quickly be made into a vector with @splat(size, value)

Reduce Operations: And, Or, Xor, Min, Max, Add, Mul

## Pointers
*type, *const type --> pointer to a single object
[*]type -> pointer to multiple objects of unknown count

ptr.*

A c-string would be represented as:
?[*]const u8

this would be read as "nullable pointer to an unknown number of immutable unsigned 8-bit integers"

If the size is known then I would use an array pointer:
*[2]u16 --> pointer to an array of 2 u16 slots

## Nullables
?type

nullable orelse [unwrapped value]
nullable.? --> nullable orelse unreachable;

Nullable non-pointers will be tagged values structures
struct {
  isNull: bool,
  payload: Type,
};

If and while allow for nullable unwrapping

if(nullable) |nonNull| { }
while(nullable) |nonNull| { }


## Control Flow
expr can be a single expression or an expression block. (defined as { expr; expr; expr; ... })
control flow can be as a statement or embedded in an expression. 
if and switch can always be used as expressions. while and for are currently not planned to be expressions in the same way, though while(){}else{} may be considered in the future.

if(condition) expr [[else expr]]
if(nullable) |capture| expr [[else expr]]

[[label:]] for(collection) |value| expr [[else expr]];
[[label:]] for(range) |value| expr [[else expr]];
[[label:]] for(collection, 0..) |value, index| expr [[else expr]];

[[label:]] while(condition) [[continue expr]] expr [[else expr]];
[[label:]] while(nullable) [[continue expr]] |value| expr [[else expr]];

when for and while have an else handler, the else happens if the main loop body is not broken.
while and for results are still being considered and may not be supported in version 0.1.

fn findFirstLargerEntry(collection: []u32, target: u32) ?u32 {
    return for(collection) |entry| RESULT: {
        if(entry > target) break :RESULT entry;
    } else null;
}

fn finalIterationExample() u32 {
    const collection = [_]u32{ 1, 2, 3, 4, 5 };
    var index: u32 = 0;

    // this is a somewhat convoluted way to do this, TODO: think of a better example
    // result will simply be 5 since it's the final entry.
    const result = while(index < collection.len) : (index += 1) collection[index];
}


switch(integral) {
    casevalue => expr,
    casevalue2 => expr,
    casevalue3..casevalue4 => expr,
    else => defaultHandler,
}

switch(taggedUnion) {
    caseValue => |payload| expr,
    caseValue2 => |payload| expr,
}

switch must handle all cases or provide a default handler.

Blocks can be labeled and broken/continued explicitly
When a block is broken it can return a value and control continues at the end of the block
When a block is continued control returns to the top of the block and the block executes again.

const result = Label: {
    // calculate result here
    break :Label myCalculatedResult;
};

InfiniteLoop: {

    // this loop is semantically the same as while(true) { ... }
    // except it has no conditional exit logic

    continue :InfiniteLoop;
}

Use Case {
    const window = try sdl.InitializeAndCreateWindow(.Default);
    defer |window| sdl.DeinitializeAndDestroyWindow(window);

    MainLoop: {
        var event: sdl.Event = undefined;
        while(sdl.PollEvent(&event)) {
            switch(event.type){
                sdl.EventQuit => break :MainLoop,
                else => {},
            }
        }

        sdl.ClearWindow();
        sdl.UpdateWindow();

        continue :MainLoop;
    }

}

Anonymous Functions:
Anonymous functions can be declared inline as an expression. They are not closures and do not capture any surrounding state
these only act as syntactic sugar and will be outlined, assigned a name, and compiled as any other function

    const myMax = fn(a: i32, b: i32) i32 { return @max(a, b); };

In this example the function gets outlined and then myMax get assigned the pointer to that function:
    fn anonymousNameXXX(a: i32, b: i32) i32 { return @max(a, b); };
    // ...
    const myMax = &anonymousNameXXX;

Defer + ErrDefer:
defer can be used to defer execution at the end of a block. It works in ziglt by creating an anonymous function
with an explicit capture list. For version 0.1, defer REQUIRES a capture list and compiles using anonymous functions.
Later we might refactor this to be able to access the parent scope directly.

defer |capture list| body;

A defer-made anonymous function cannot return any result ever. It is not allowed to return errors either.
The parameters of the function are deduced and captured by the list. The values are captured by value at the point
that defer executes.

    const pointer = myAllocator.alloc(u8, 10);
    defer |pointer, myAllocator| myAllocator.free(pointer);

the above becomes something like the following:
    fn anonymousDeferXXX(pointer: []u8, myAllocator: allocator) void {
        myAllocator.free(pointer)
    }
    // (...)
    @pushDefer(.{ .target = &anonymousDeferXXX, .args = .{ pointer, myAllocator } });

errdefer works the same way as defer and uses the same syntax, the critical differences is:
    defer executes at the end of block
    errdefer executes at the end of function

    defer always executes when leaving the block
    errdefer only executes when exiting the function via error result.


Complex types:

    structs follow the c-layout in memory
    enums are integer-backed, they default to u32 but this can be overridden
    unions are always tagged and a tag must be provided explicitly (TODO: allow implicit tagging)

    const myStruct = struct { a: i32, b: i32, c: f32 };
    const myEnum = enum{ None, First, Second, Fifth = 5 };
    const myUnion = union(myEnum) {
        None: void,
        First: i32,
        Second: myStruct,
        Fifth: []const u32,
    };

    structs are allowed to contain function definitions as a way to namespace functions.
    they may also contain constant definitions. data members must be kept in a single sequential block

    pub const myStruct = struct {
        a: i32, b: i32, c: f32

        pub fn maxOfMe(this: @This()) i32 {
            const maxInt: i32 = @max(this.a, this.b);
            const asFloat: f32 = @floatFromInt(maxInt);
            return @max(asFloat, this.c);
        }
    };

    // (...)
    const value = myStruct{
        .a = 100,
        .b = 32,
        .c = 42.0,
    };
    // future versions of the langauge will allow value.maxOfMe. Version 0.1 does not support that syntax
    const maxMember = myStruct.maxOfMe(value);

    struct members may define a default initializer and when a default initializer is specified
    the initializer for that member becomes optional

    const Features = struct {
        SSE2: bool = true,
        AVX: bool = false,
        AVX2: bool = false,
        AVX512: bool = false,
    };

    const requestedFeatures: Features = .{ .AVX512 = true };
    // requestedFeatures == Features{ .SSE2 = true, .AVX = false, .AVX2 = false, .AVX512 = true };


Error Handling:
    Errors are handled as tagged error unions. An error is a member of an error set. Errors can be
    designed in individual blocks or as a part of the global error set.

    const myErrorSet = error{ MyError0, MyError1 };

    fn throwsError() myErrorSet!void {
        return error.MyError0; // since the error set is explicitly defiend as the myErrorSet, we will use that error set
    }

    fn throwsImplicitError() !void {
        return error.ImplicitError; // since the error set is ommitted "ImplicitError" will get added to the global error set if it does not already exist
    }

    Error sets cannot be implicitly mixed. Explicit coersion must be used.

    fn convertsError() !void {
        throwsError() catch |e| {
            if(e == myErrorSet.MyError0) return error.ImplicitError;
            return error.UnexpectedError;
        };
    }

Try/catch
    catch receives and error and handles it or propogates it.

    canFail() catch |e| { handleE(e); };

    if you don't care about receiving the error itself then the catch can be ommitted

    canFail() catch unreachable;

    try will propogate an error
    // these two statements are essentially the same
    try canFail();
    canFail() catch |e| return e;

Unreachable
    This acts as a trap. If execution reaches this statement then the program will panic. It should be used
    to notate where control flow should never go. May futurely be used in optimizations and can be used for
    debug assertions. In the future when optimizations are more fully implemented then we will provide a "release"
    optimization profile that will strip away many unreachable branches and leave basic traps in any branches we cannot
    strip away. debug assert will then become:

    fn assert(value: bool) void {
        if(!value) unreachable;
    }

Undefined:
    When creating a variable you must always provide a value. Uninitialized variables are not allowed by default:

    var a: i32; // this is never valid

    If you do need an uninitialized variable you must explicitly set it to undefined:

    // a will not be set to anything.
    var a: i32 = undefined;

An imported file gets wrapped in a struct


Update to "const" keyword:

    const [label] = [expression];
    const [label]: [type] = [expression];


In the first instance, we are defining an AST container that will then be referenced and inlined
in future semantic passes (constant folding).
The second instance is constant runtime data.


Comptime:
    comptime is more primitive in ziglt than in zig. We will have basic constant propogation and folding.
    comptime function will be able to generate AST nodes and types from comptime parameters.

comptime fn AList(T: type) type {
    return struct {
        items: []T,
        ...
    };
}

const IntegerList = AList(i32);

const list: IntegerList = IntegerList{ ... };


Note the multiple types of const here:
    const IntegerList = AList(i32);
This will call AList() and generate a resulting ASTNode which will then get stored under the name "IntegerList"
From there we create a constant (runtime-data) list that is instantiated to IntegerList. Constant popogation and folding
will resolve the references in the ast and the above will effectually get compiled as if it were the following:

const list: struct { items: []i32, ... } = struct { items: []i32, ... }{ ... };
