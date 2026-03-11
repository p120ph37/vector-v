module vrl

// AST node types for VRL expressions.
// Uses []Expr (single-element arrays) instead of &Expr to avoid
// V's pointer-to-sum-type issues with heap allocation.
pub type Expr = LiteralExpr
	| ArrayExpr
	| ObjectExpr
	| IdentExpr
	| PathExpr
	| MetaPathExpr
	| UnaryExpr
	| BinaryExpr
	| AssignExpr
	| MergeAssignExpr
	| IfExpr
	| BlockExpr
	| FnCallExpr
	| IndexExpr
	| CoalesceExpr
	| AbortExpr
	| ReturnExpr
	| NotExpr
	| ClosureExpr

pub struct LiteralExpr {
pub:
	value VrlValue
}

pub struct ArrayExpr {
pub:
	items []Expr
}

pub struct ObjectExpr {
pub:
	pairs []KeyValue
}

pub struct KeyValue {
pub:
	key   string
	value Expr
}

pub struct IdentExpr {
pub:
	name string
}

// PathExpr represents a dotted path like .foo.bar
pub struct PathExpr {
pub:
	path string
}

// MetaPathExpr represents metadata paths like %foo
pub struct MetaPathExpr {
pub:
	path string
}

pub struct UnaryExpr {
pub:
	op   string
	expr []Expr // single-element box
}

pub struct BinaryExpr {
pub:
	op    string
	left  []Expr // single-element box
	right []Expr // single-element box
}

pub struct AssignExpr {
pub:
	target []Expr // PathExpr or IdentExpr
	value  []Expr
}

pub struct MergeAssignExpr {
pub:
	target []Expr
	value  []Expr
}

pub struct IfExpr {
pub:
	condition  []Expr
	then_block []Expr
	else_block []Expr // empty = no else
}

pub struct BlockExpr {
pub:
	exprs []Expr
}

pub struct FnCallExpr {
pub:
	name    string
	args    []Expr
	closure []Expr // empty or single ClosureExpr
}

pub struct IndexExpr {
pub:
	expr  []Expr
	index []Expr
}

pub struct CoalesceExpr {
pub:
	expr     []Expr
	default_ []Expr
}

pub struct AbortExpr {
pub:
	message []Expr // empty = no message
}

pub struct ReturnExpr {
pub:
	value []Expr // the expression to return
}

pub struct NotExpr {
pub:
	expr []Expr
}

pub struct ClosureExpr {
pub:
	params []string
	body   []Expr
}
