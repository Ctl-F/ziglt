pub const Kind = enum {
    Void,
    U8,
    U16,
    U32,
    U64,
    I8,
    I16,
    I32,
    I64,
    F32,
    F64,
    Struct,
    Union,
    Enum,
    Function,
    Error,
    Pointer,
};

pub const PointerType = union(enum) {
    Single,
    Multiple,
    MultipleKnown: u32,
};

const Type = u32;

pub const TypeInfo = union(Kind) {
    Void,
    U8,
    U16,
    U32,
    U64,
    I8,
    I16,
    I32,
    I64,
    F32,
    F64,
    Struct: StructInfo,
    Union: UnionInfo,
    Enum: EnumInfo,
    Function: FunctionInfo,
    Error: ErrorInfo,
    Pointer: PointerInfo,

    pub const StructInfo = struct {
        const Member = struct {
            name: []const u8,
            type: Type,
        };

        layout: enum { ExternC },
        members: []const Member,
    };
    pub const UnionInfo = struct {};
    pub const EnumInfo = struct {};
    pub const FunctionInfo = struct {};
    pub const ErrorInfo = struct {};
    pub const PointerInfo = struct {};
};

pub const ErrorSet = struct {};
