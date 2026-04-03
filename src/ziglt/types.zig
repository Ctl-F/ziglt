const std = @import("std");

pub const Kind = enum {
    Void,
    Opaque,
    Integer,
    Float,
    Struct,
    Union,
    Enum,
    Function,
    Error,
    Pointer,
    Nullable,
};

pub const PointerType = union(enum) {
    Single,
    Multiple,
    Fixed: usize,
};

const Type = usize;
pub const ErrorSetID = usize;

pub const TypeInfo = union(Kind) {
    Void,
    Opaque,
    Integer: IntInfo,
    Float: FloatInfo,
    Struct: StructInfo,
    Union: UnionInfo,
    Enum: EnumInfo,
    Function: FunctionInfo,
    Error: ErrorInfo,
    Pointer: PointerInfo,
    Nullable: NullableInfo,

    pub const StructInfo = struct {
        layout: enum { Packed, C },
        members: []const Member,
        decls: []const Decl,
    };

    pub const UnionInfo = struct {
        tag: ?Type,
        members: []const Member,
        decls: []const Decl,
    };

    pub const EnumInfo = struct {
        backing: Type,
        fields: []const EnumField,
        decls: []const Decl,
    };

    pub const FunctionInfo = struct {
        returnType: Type,
        parameterTypes: []const Type,
        callConv: enum { C, Inline },
    };

    pub const ErrorInfo = struct {
        set: ErrorSetID,
    };

    pub const PointerInfo = struct {
        kind: PointerType,
        child: Type,
        alignment: u8,
        mutability: enum { Const, Variable },
    };

    pub const IntInfo = struct {
        size: u8,
        signed: bool,
    };

    pub const FloatInfo = struct {
        size: enum { Single, Double },
    };

    pub const NullableInfo = struct {
        child: Type,
    };

    pub const Member = struct {
        name: []const u8,
        type: Type,
    };

    pub const Decl = struct {
        name: []const u8,
    };

    pub const EnumField = struct {
        name: []const u8,
        default: ?u128,
    };
};

pub const ErrorSet = struct {
    errorCodes: []const []const u8,
};

pub const TypeRegistry = struct {
    const This = @This();

    allocator: std.mem.Allocator,
    types: std.ArrayList(TypeInfo),
    errorSets: std.ArrayList(ErrorSet),

    pub fn default(allocator: std.mem.Allocator) !This {
        var new = empty(allocator);

        (&new).* = new;

        return new;
    }

    pub fn empty(allocator: std.mem.Allocator) This {
        return This{
            .allocator = allocator,
            .types = std.ArrayList(TypeInfo).empty,
            .errorSets = std.ArrayList(ErrorSet).empty,
        };
    }

    pub fn registerType(this: *This, info: TypeInfo) !Type {
        const typeID = this.types.items.len;
        try this.types.append(this.allocator, info);
        return typeID;
    }

    pub fn registerErrorSet(this: *This, set: ErrorSet) !void {
        try this.errorSets.append(this.allocator, set);
    }
};

pub const SymbolTable = struct {
    const This = @This();

    pub const ROOT_TYPE: Type = @bitCast(@as(isize, -1));

    pub const Symbol = struct {
        name: []const u8,
        type: Type,
        children: std.ArrayList(*Symbol),
    };

    // USE ARENA ALLOCATOR HERE!!!!
    allocator: std.mem.Allocator,
    root: *Symbol,

    /// PLEASE USE AN ARENA ALLOCATOR HERE!!!!
    pub fn init(allocator: std.mem.Allocator) !This {
        const root = try makeSymbol(allocator, "", ROOT_TYPE);

        return .{ .allocator = allocator, .root = root };
    }

    fn makeSymbol(allocator: std.mem.Allocator, name: []const u8, _type: Type) !*Symbol {
        const node = try allocator.create(Symbol);
        node.* = .{
            .name = name,
            .type = _type,
            .children = std.ArrayList(*Symbol).empty,
        };
        return node;
    }

    pub fn insert(this: *This, name: []const u8, _type: Type, where: *Symbol) !void {
        for (where.children.items) |existing| {
            if (std.mem.eql(existing.name, name)) {
                return error.DuplicateSymbol;
            }
        }

        const node = try makeSymbol(this.allocator, name, _type);
        errdefer this.allocator.free(node);

        try where.children.append(node);
    }

    pub fn search(this: *This, name: []const []const u8) ?*Symbol {
        return searchFrom(name, this.root);
    }

    fn searchFrom(name: []const []const u8, where: *Symbol) ?*Symbol {
        if (name.len == 0) return where;
        const thisName = name[0];
        const remainingNames = name[1..];

        for (where.children.items) |child| {
            if (std.mem.eql(u8, child.name, thisName)) {
                return searchFrom(remainingNames, child);
            }
        }

        return null;
    }
};
