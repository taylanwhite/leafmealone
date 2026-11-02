"""Read the top-level constants of a GDScript file into Python values.

Stdlib only (docs/BALANCE.md). tools/balance_sim.py reads every tuning number
straight out of the game's own scripts with this, so the simulator can never
run on numbers the game doesn't have.

    consts, unparsed = parse_file("core/constants.gd")
    every = load_all(repo)   # {"Constants": {...}, "Balance": ..., "Ranks": ...,
                             #  "Seasons": ..., "Hoods": ..., "Catalog": ...}

What it understands, in a `const NAME[: Type] [:]= <expression>` at column 0
(the expression may run over several lines until its brackets close):

- numbers, strings, arrays, dictionaries, true/false/null
- &"name" (StringName) and ^"path" (NodePath) as plain strings
- Vector2/Vector2i/Vector3/Vector3i/Rect2/Rect2i/Color(...) as tuples
  (Color without alpha gets 1.0), Packed*Array([...]) as lists
- PI, TAU, INF, and + - * / % on numbers (int / int is integer division, as in
  GDScript), names of constants defined earlier in the same file, and
  "fmt" % [args] string formatting
- a `float` or `Array[float]` annotation turns ints into floats, as Godot does

Anything else (preload, calls, other scripts' constants) lands in `unparsed`
with the reason, instead of a wrong value. The engine parity check
(balance_sim.py --engine-dump) compares what this returns with Godot's own
get_script_constant_map(), so a silent misparse can't survive CI either.
"""

from __future__ import annotations

import ast
import io
import math
import os
import re
import tokenize

# The scripts the simulator reads, by the name it uses for each.
SOURCES = {
    "Constants": "core/constants.gd",
    "Balance": "core/balance.gd",
    "Ranks": "core/ranks.gd",
    "Seasons": "core/seasons.gd",
    "Hoods": "net/town/neighborhoods.gd",
    "Catalog": "core/catalog.gd",
}

_CONST_LINE = re.compile(
    r"^const\s+([A-Za-z_]\w*)\s*(?::\s*([A-Za-z_][\w\[\], ]*?)\s*)?(:=|=)\s*(.*)$"
)

_FLOAT_VECTORS = {"Vector2": 2, "Vector3": 3, "Vector4": 4, "Rect2": 4}
_INT_VECTORS = {"Vector2i": 2, "Vector3i": 3, "Vector4i": 4, "Rect2i": 4}
_NAMED = {"PI": math.pi, "TAU": math.tau, "INF": math.inf, "NAN": math.nan}


class Unparsed(Exception):
    """An expression this reader can't turn into a value."""


def parse_file(path: str) -> tuple[dict, list]:
    """Returns ({name: value}, [{"name", "reason"}]) for one .gd file."""
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    values: dict = {}
    unparsed: list = []
    index = 0
    while index < len(lines):
        match = _CONST_LINE.match(lines[index])
        if not match:
            index += 1
            continue
        name, type_hint = match.group(1), (match.group(2) or "").strip()
        text, used = _expression_text(match.group(4), lines, index + 1)
        index += used
        try:
            value = _evaluate(text, values)
            values[name] = _apply_type(value, type_hint)
        except (Unparsed, SyntaxError, ValueError, TypeError, ZeroDivisionError) as error:
            unparsed.append({"name": name, "reason": str(error) or type(error).__name__, "text": text.strip()[:120]})
    return values, unparsed


def load_all(repo: str) -> dict:
    """Every script the simulator reads: {script: {"values": {...}, "unparsed": [...]}}."""
    out = {}
    for script, relative in SOURCES.items():
        values, unparsed = parse_file(os.path.join(repo, relative))
        out[script] = {"values": values, "unparsed": unparsed, "path": relative}
    return out


def parse_value(text: str, known: dict | None = None):
    """One GDScript expression (for --set NAME=VALUE what-ifs)."""
    return _evaluate(text, known or {})


# ---------------------------------------------------------------- reading the text

def _expression_text(first: str, lines: list, next_index: int) -> tuple[str, int]:
    """The whole expression starting with `first`, joined over as many lines as
    its brackets need, and how many source lines that used (at least 1)."""
    text = first
    used = 1
    while True:
        try:
            _tokens(text)
            return text, used
        except tokenize.TokenError:
            if next_index + used - 1 >= len(lines):
                return text, used
            text += "\n" + lines[next_index + used - 1]
            used += 1


def _tokens(text: str) -> list:
    out = []
    for token in tokenize.generate_tokens(io.StringIO(text + "\n").readline):
        if token.type == tokenize.NEWLINE:
            break
        out.append(token)
    return out


def _to_python(text: str) -> str:
    """GDScript tokens to a Python expression: true/false/null, and the & and ^
    in front of string literals dropped."""
    tokens = [t for t in _tokens(text) if t.type not in (tokenize.COMMENT, tokenize.NL, tokenize.INDENT, tokenize.DEDENT)]
    pieces = []
    for position, token in enumerate(tokens):
        following = tokens[position + 1] if position + 1 < len(tokens) else None
        if token.type == tokenize.OP and token.string in ("&", "^") and following is not None and following.type == tokenize.STRING:
            continue
        if token.type == tokenize.NAME and token.string in ("true", "false", "null"):
            pieces.append((tokenize.NAME, {"true": "True", "false": "False", "null": "None"}[token.string]))
            continue
        if token.type == tokenize.ERRORTOKEN and token.string.strip() == "":
            continue
        pieces.append((token.type, token.string))
    return tokenize.untokenize(pieces)


def _evaluate(text: str, known: dict):
    tree = ast.parse(_to_python(text).strip(), mode="eval")
    return _eval_node(tree.body, known)


# ---------------------------------------------------------------- a small, safe evaluator

def _eval_node(node, known: dict):
    if isinstance(node, ast.Constant):
        return node.value
    if isinstance(node, ast.List):
        return [_eval_node(item, known) for item in node.elts]
    if isinstance(node, ast.Tuple):
        return [_eval_node(item, known) for item in node.elts]
    if isinstance(node, ast.Dict):
        out = {}
        for key, value in zip(node.keys, node.values):
            if key is None:
                raise Unparsed("dictionary unpacking")
            out[_hashable(_eval_node(key, known))] = _eval_node(value, known)
        return out
    if isinstance(node, ast.Name):
        if node.id in ("True", "False", "None"):
            return {"True": True, "False": False, "None": None}[node.id]
        if node.id in _NAMED:
            return _NAMED[node.id]
        if node.id in known:
            return known[node.id]
        raise Unparsed("unknown name %s" % node.id)
    if isinstance(node, ast.UnaryOp):
        operand = _eval_node(node.operand, known)
        if isinstance(node.op, ast.USub) and _is_number(operand):
            return -operand
        if isinstance(node.op, ast.UAdd) and _is_number(operand):
            return operand
        if isinstance(node.op, ast.Not):
            return not operand
        raise Unparsed("unary operator")
    if isinstance(node, ast.BinOp):
        return _binary(node.op, _eval_node(node.left, known), _eval_node(node.right, known))
    if isinstance(node, ast.Call):
        return _call(node, known)
    if isinstance(node, ast.Attribute):
        raise Unparsed("reference to %s" % ast.unparse(node))
    raise Unparsed("expression %s" % type(node).__name__)


def _call(node: ast.Call, known: dict):
    if not isinstance(node.func, ast.Name) or node.keywords:
        raise Unparsed("call to %s" % ast.unparse(node.func))
    name = node.func.id
    args = [_eval_node(arg, known) for arg in node.args]
    if name in _FLOAT_VECTORS:
        size = _FLOAT_VECTORS[name]
        if len(args) != size or not all(_is_number(a) for a in args):
            raise Unparsed("%s with %d arguments" % (name, len(args)))
        return tuple(float(a) for a in args)
    if name in _INT_VECTORS:
        size = _INT_VECTORS[name]
        if len(args) != size or not all(_is_number(a) for a in args):
            raise Unparsed("%s with %d arguments" % (name, len(args)))
        return tuple(int(a) for a in args)
    if name == "Color":
        if len(args) == 3 and all(_is_number(a) for a in args):
            return tuple(float(a) for a in args) + (1.0,)
        if len(args) == 4 and all(_is_number(a) for a in args):
            return tuple(float(a) for a in args)
        raise Unparsed("Color with %d arguments" % len(args))
    if name.startswith("Packed") and name.endswith("Array"):
        if not args:
            return []
        if len(args) == 1 and isinstance(args[0], list):
            if name in ("PackedFloat32Array", "PackedFloat64Array"):
                return [float(a) for a in args[0]]
            if name in ("PackedInt32Array", "PackedInt64Array"):
                return [int(a) for a in args[0]]
            return list(args[0])
        raise Unparsed("%s(...)" % name)
    if name in ("StringName", "String", "NodePath") and len(args) == 1 and isinstance(args[0], str):
        return args[0]
    if name == "float" and len(args) == 1 and _is_number(args[0]):
        return float(args[0])
    if name == "int" and len(args) == 1 and _is_number(args[0]):
        return int(args[0])
    raise Unparsed("call to %s" % name)


def _binary(op, left, right):
    if isinstance(op, ast.Mod) and isinstance(left, str):
        # GDScript "fmt" % [a, b] or "fmt" % a.
        args = tuple(right) if isinstance(right, list) else (right,)
        return left % args
    if isinstance(left, str) and isinstance(right, str) and isinstance(op, ast.Add):
        return left + right
    if not (_is_number(left) and _is_number(right)):
        raise Unparsed("operator on %s and %s" % (type(left).__name__, type(right).__name__))
    both_int = isinstance(left, int) and isinstance(right, int) and not isinstance(left, bool) and not isinstance(right, bool)
    if isinstance(op, ast.Add):
        return left + right
    if isinstance(op, ast.Sub):
        return left - right
    if isinstance(op, ast.Mult):
        return left * right
    if isinstance(op, ast.Div):
        if both_int:
            # GDScript integer division truncates toward zero.
            return int(left / right) if right != 0 else _raise_zero()
        return left / right
    if isinstance(op, ast.Mod):
        if both_int:
            return int(math.fmod(left, right))
        return math.fmod(left, right)
    raise Unparsed("operator %s" % type(op).__name__)


def _raise_zero():
    raise ZeroDivisionError("integer division by zero")


def _apply_type(value, type_hint: str):
    hint = type_hint.replace(" ", "")
    if hint == "float" and isinstance(value, int) and not isinstance(value, bool):
        return float(value)
    if hint in ("Array[float]", "PackedFloat32Array", "PackedFloat64Array") and isinstance(value, list):
        return [float(v) if isinstance(v, int) and not isinstance(v, bool) else v for v in value]
    if hint == "int" and isinstance(value, float):
        raise Unparsed("float in an int constant")
    return value


def _is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _hashable(value):
    return tuple(value) if isinstance(value, list) else value


if __name__ == "__main__":
    import json
    import sys

    repo = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..")
    every = load_all(repo)
    for script, entry in every.items():
        print("%-10s %3d constants, %d unparsed" % (script, len(entry["values"]), len(entry["unparsed"])))
        for item in entry["unparsed"]:
            print("    unparsed %s: %s" % (item["name"], item["reason"]))
    if "--json" in sys.argv:
        print(json.dumps({k: v["values"] for k, v in every.items()}, indent=1, default=str)[:4000])
