const lexer = @import("lexer.zig");

pub const ASTNode = union(enum) {
    const Node = @This();

    immediate: ImmediatePrimitive,
    identifier: Identifier,
    binary: Binary,
    unary: Unary,
    @"if": If,
    @"while": While,
    @"for": For,
    @"switch": Switch,
    switchProng: SwitchProng,
    statement: Statement,
    capture: Capture,
    parameter: Parameter,
    argument: Argument,
    func: Func,
    declaration: Declaration,
    container: Container,
    @"enum": Enum,
    constDef: ConstDef,
    constRef: ConstRef,
    @"catch": Catch,
    @"defer": Defer,
    call: Call,
    interrupt: Interrupter,
    labelDefinition: LabelDefinition,
    labelReference: LabelReference,
    structInit: StructInitializer,
    arrayInit: ArrayInitializer,
    fieldInit: FieldInitializer,
    import: Import,
    type: Type,
    undefined,
    @"unreachable",

    pub const ImmediatePrimitive = union(enum) {
        uint: u128,
        float: f128,
        boolean: bool,
        string: []const u8,
        char: u8,
    };

    pub const Identifier = struct {
        lexme: []const u8,
    };

    pub const Binary = struct {
        op: BinaryOp,
        left: *Node,
        right: *Node,
    };

    pub const Unary = struct {
        op: UnaryOp,
        expr: *Node,
    };

    pub const If = struct {
        condition: *Node,
        capture: ?*Capture,
        body: *Statement,
        elseBlock: ?*Statement,
    };

    pub const While = struct {
        condition: *Node,
        continueExpression: ?*Node,
        capture: ?*Capture,
        body: *Statement,
        elseBlock: ?*Statement,
    };

    pub const For = struct {
        collection: *Node,
        capture: ?*Capture,
        body: *Statement,
        elseBlock: ?*Statement,
    };

    pub const Switch = struct {
        pub const Prong = struct { case: *SwitchProng, next: ?*Prong };

        condition: *Node,
        prongs: *Prong,
    };

    pub const SwitchProng = struct {
        value: *Node,
        capture: ?*Capture,
        payload: ?*Node,
    };

    pub const Statement = struct {
        payload: *Node,
        next: ?*Statement,
    };

    // |a, b, c|
    pub const Capture = struct {
        identifier: *Identifier,
        next: ?*Capture,
    };

    // a: type
    pub const Parameter = struct {
        name: *Identifier,
        typeName: *Node,
        next: ?*Parameter,
    };

    pub const Argument = struct {
        expression: *Node,
        next: ?*Argument,
    };

    pub const Func = struct {
        visiblity: Visibility,
        isComptime: bool,
        name: ?*Identifier,
        parameters: ?*Parameter,
        returnType: *Node,
        body: *Statement,
        next: ?*Func,
    };

    pub const Declaration = struct {
        mode: Visibility,
        name: *Identifier,
        typeName: *Node,
        expression: *Node,
        next: ?*Declaration,
    };

    pub const Container = struct {
        pub const Kind = enum { Struct, Union, Enum };

        kind: Kind,
        visibility: Visibility,
        constants: ?*ConstDef,
        functions: ?*Func,
        members: ?*Declaration,
    };

    pub const Enum = struct {
        pub const Member = struct { name: *Identifier, value: ?*Node, next: ?*Member };

        visibility: Visibility,
        backing: ?*Node,
        members: ?*Member,
    };

    pub const ConstDef = struct {
        visibility: Visibility,
        name: *Identifier,
        payload: *Node,
        next: ?*ConstDef,
    };
    pub const ConstRef = struct {
        referenced: *ConstDef,
    };

    pub const Catch = struct {
        capture: ?*Capture,
        body: *Statement,
    };

    pub const Defer = struct {
        isError: bool,
        capture: ?*Capture,
        expression: *Node,
    };

    pub const Call = struct {
        name: *Node,
        args: ?*Argument,
    };

    pub const Interrupter = struct {
        pub const Kind = enum { Break, Continue, Return };
        kind: Kind,
        label: ?*LabelReference,
        value: ?*Node,
    };

    pub const LabelDefinition = struct {
        name: *Identifier,
    };
    pub const LabelReference = struct {
        name: *Identifier,
    };

    pub const StructInitializer = struct {
        pub const InitializerList = struct { field: *FieldInitializer, next: ?*InitializerList };

        typeName: *Node,
        initializers: ?*InitializerList,
    };

    pub const ArrayInitializer = struct {
        pub const Value = struct { expr: *Node, next: ?*Value };

        typeID: *Node,
        size: *Node,
        isConst: bool,
        values: *Value,
    };

    pub const FieldInitializer = struct {
        name: *Identifier,
        value: *Node,
    };

    pub const Import = struct {
        path: []const u8,
    };

    pub const Type = struct {
        expr: *Node,
    };
};

pub const BinaryOp = enum {
    Add,
    Subtract,
    Multiply,
    Divide,
    Modulus,
    CompareEq,
    CompareNeq,
    CompareLt,
    CompareLe,
    CompareGt,
    CompareGe,
    LogicalAnd,
    LogicalOr,
    BitwiseAnd,
    BitwiseOr,
    BitwiseXor,
    BitwiseShiftLeft,
    BitwiseShiftRight,
    Assign,
    NullUnwrap,
    ErrorUnion,
    // New operators
    ArrayMultiply,
    Orelse,
    Catch,
    FieldAccess,
    IndexAccess,
    AddAssign,
    SubtractAssign,
    MultiplyAssign,
    DivideAssign,
    ModulusAssign,
    BitwiseAndAssign,
    BitwiseOrAssign,
    BitwiseXorAssign,
    BitwiseShiftLeftAssign,
    BitwiseShiftRightAssign,
};

pub const UnaryOp = enum {
    Negation,
    LogicalNot,
    BitwiseNot,
    AddressOf,
    OptionalUnwrap,
    Dereference,
    Try,
};

pub const Visibility = enum { Default, Public };

pub const Precedence = enum(u8) {
    Lowest, // values
    Assign, // = += *= etc.
    Or,
    And,
    Compare,
    Bitwise, // & ^ | orelse catch
    BitShift, // << >>
    Sum, // + -
    Product, // * / %
    Prefix, // -X ~X !X &X
    Initializer, // X{}
    ErrorUnion, // a!b
    Accessor, // X() X[] X.Y X.* X.?

    pub fn fromToken(id: lexer.TokenID) Precedence {
        return switch (id) {
            .Equal, .PlusEq, .MinusEq, .AsteriskEq, .ForwardSlEq, .PercentEq, .AmpEq, .PipeEq, .CaretEq, .LessLessEq, .GreaterGreaterEq => .Assign,
            .Or => .Or,
            .And => .And,
            .DoubleEqual, .NotEqual, .Less, .LessEqual, .Greater, .GreaterEqual => .Compare,
            .Amp, .Pipe, .Caret, .Orelse, .Catch => .Bitwise,
            .LessLess, .GreaterGreater => .BitShift,
            .Plus, .Minus => .Sum,
            .Asterisk, .ForwardSlash, .Percent => .Product,
            .LeftCurl => .Initializer,
            .Bang => .ErrorUnion,
            .LeftParen, .LeftBracket, .Period, .PeriodAst, .PeriodQuest => .Accessor,
            else => .Lowest,
        };
    }
};
