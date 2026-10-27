package main

type Node struct{ At Pos }

func (n Node) P() Pos { return n.At }

type Expr interface{ P() Pos }

type (
	IntLit struct {
		Node
		V int64
	}
	StrLit struct {
		Node
		V string
	}
	BoolLit struct {
		Node
		V bool
	}
	Ident struct {
		Node
		Name string
	}
	CtorRef struct {
		Node
		Name string
	}
	Call struct {
		Node
		Fn   Expr
		Args []Expr
	}
	Field struct {
		Node
		X    Expr
		Name string
	}
	ListLit struct {
		Node
		Items []Expr
	}
	RecordLit struct {
		Node
		Type   string
		Fields []FieldInit
	}
	RecordUpd struct {
		Node
		X      Expr
		Fields []FieldInit
	}
	If struct {
		Node
		Conds  []Expr
		Bodies []*Block
		Else   *Block
	}
	Match struct {
		Node
		X    Expr
		Arms []Arm
	}
	Lambda struct {
		Node
		Params []Param
		Body   *Block
	}
)

type FieldInit struct {
	At   Pos
	Name string
	X    Expr
}

type Arm struct {
	Pat  Pattern
	Body *Block
}

// Stmt is `let Name = X` when Let != "", otherwise an expression statement.
type Stmt struct {
	At  Pos
	Let string
	X   Expr
}

type Block struct{ Stmts []Stmt }

type Pattern interface{ P() Pos }

type (
	PWild struct{ Node }
	PVar  struct {
		Node
		Name string
	}
	PInt struct {
		Node
		V int64
	}
	PStr struct {
		Node
		V string
	}
	PBool struct {
		Node
		V bool
	}
	PCtor struct {
		Node
		Name string
		Args []Pattern
	}
	// PList matches [a, b] exactly, or [a, b, ..rest] when Rest != nil.
	PList struct {
		Node
		Items []Pattern
		Rest  Pattern
	}
)

// TypeExpr is kept for the future static type checker; v0 only checks that it parses.
type TypeExpr struct {
	Name string
	Args []TypeExpr // for Fn: params..., return type last
}

type Param struct {
	Name string
	Type *TypeExpr
}

type FnDecl struct {
	Node
	Name    string
	Params  []Param
	Ret     TypeExpr
	Effects []string
	Body    *Block
}

type CtorDecl struct {
	At   Pos
	Name string
	Args []TypeExpr
}

type FieldDecl struct {
	Name string
	Type TypeExpr
}

type TypeDecl struct {
	Node
	Name     string
	TParams  []string
	IsRecord bool
	Ctors    []CtorDecl
	Fields   []FieldDecl
}

type TestDecl struct {
	Node
	Name string
	Body *Block
}

type LetDecl struct {
	Node
	Name string
	X    Expr
}

type Import struct {
	Node
	Name string
}

type File struct {
	Path    string
	Imports []*Import
	Types   []*TypeDecl
	Fns     []*FnDecl
	Tests   []*TestDecl
	Lets    []*LetDecl
}
