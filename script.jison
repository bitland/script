/* description: Compiles Bitcoin Script to JavaScript. */

%{
    var base = 16;

    // Utilities required in Jison compiler
    var bigInt = require('big-integer');
    var beautify = require('js-beautify').js_beautify;
    var O = require('observed');

    // Utilities required in compiled code
    var util = {
        // Crypto
        ripemd160: function(data) {
            data = data.toString(base);
            return require('ripemd160')(data).toString('hex');
        },
        sha1: function(data) {
            data = data.toString(base);
            return require('sha1')(data);
        },
        sha256: function(data) {
            data = data.toString(base);
            return require('sha256')(data);
        },
    };

    // Setup
    var ScriptStack = function() {
        var serialize = function(data) {
            return data.toString(base);
        };
        var deserialize = function(data) {
            return bigInt(data, base);
        };

        // We store the history of pushes and pops, for later inspection
        // Pops are represented by pushing `null`
        var self = this;
        self.history = [];

        this.push = function() {
            var serialized = [].map.call(arguments, serialize);
            var result = Array.prototype.push.apply(this, serialized);
            serialized.forEach(function(value) {
                self.history.push(value);
            });
            return result;
        };
        this.pop = function() {
            var result = deserialize(Array.prototype.pop.apply(this));
            self.history.push(null);
            return result;
        };
    };
%}

/* lexical grammar */
%lex

%%
\s+                       { /* skip whitespace */ }
0x([0-9]|[A-F]|[a-f])+\b  { return 'DATA'; }
/* Constants */
"OP_0"                    { return 'OP_0'; }
"OP_FALSE"                { return 'OP_0'; }
"OP_1NEGATE"              { return 'OP_1NEGATE'; }
"OP_1"                    { return 'OP_1'; }
"OP_TRUE"                 { return 'OP_1'; }
OP_([2-9]|1[0-6])         { return 'OP_DATA'; }
/* Flow control */
"OP_NOP"                  { return 'OP_NOP'; }
"OP_IF"                   { return 'OP_IF'; }
"OP_NOTIF"                { return 'OP_NOTIF'; }
"OP_ELSE"                 { return 'OP_ELSE'; }
"OP_ENDIF"                { return 'OP_ENDIF'; }
"OP_VERIFY"               { return 'OP_VERIFY'; }
"OP_RETURN"               { return 'OP_RETURN'; }
/* Stack */
"OP_DROP"                 { return 'OP_DROP'; }
"OP_DUP"                  { return 'OP_DUP'; }
"OP_SWAP"                 { return 'OP_SWAP'; }
/* Bitwise logic */
"OP_EQUAL"                { return 'OP_EQUAL'; }
/* Arithmetic */
"OP_1ADD"                 { return 'OP_1ADD'; }
"OP_1SUB"                 { return 'OP_1SUB'; }
"OP_NEGATE"               { return 'OP_NEGATE'; }
"OP_ABS"                  { return 'OP_ABS'; }
/* Crypto */
"OP_RIPEMD160"            { return 'OP_RIPEMD160'; }
"OP_SHA1"                 { return 'OP_SHA1'; }
"OP_SHA256"               { return 'OP_SHA256'; }
"OP_HASH160"              { return 'OP_HASH160'; }
"OP_HASH256"              { return 'OP_HASH256'; }
<<EOF>>                   { return 'EOF'; }

/lex

%nonassoc OP_ELSE
%nonassoc OP_ENDIF

%start expressions

%% /* language grammar */

expressions
    : nonterminal expressions
    | terminal EOF
        %{
            var js = beautify($1);
            var evaluate = new Function('stack', 'util', js);

            var stack = new ScriptStack();
            return {
                evaluate: function() {
                    return evaluate(stack, util);
                },
                stack: stack
            };
        %}
    ;

terminal
    : OP_VERIFY
        %{
            $$ = ($0 || '') + 'return (stack.pop().compare(0) !== 0);';
        %}
    | OP_RETURN
        %{
            $$ = ($0 || '') + 'return false;';
        %}
    ;

statement
    : nonterminal
    | nonterminal statement
    ;

nonterminal
    : DATA
        %{
            $$ = ($0 || '') + 'stack.push(' + $1 + ');';
        %}
    | OP_IF statement OP_ELSE statement OP_ENDIF
        %{
            var b1 = $statement1.substr('OP_IF'.length);
            var b2 = $statement2.substr('OP_ELSE'.length);
            $$ = ($0 || '') + 'if (stack.pop().compare(0) !== 0) {' + b1 + '} else {' + b2 + '};';
        %}
    | OP_IF statement OP_ENDIF
        %{
            var b1 = $statement.substr('OP_IF'.length);
            $$ = ($0 || '') + 'if (stack.pop().compare(0) !== 0) {' + b1 + '};';
        %}
    | OP_NOTIF statement OP_ELSE statement OP_ENDIF
        %{
            var b1 = $statement1.substr('OP_NOTIF'.length);
            var b2 = $statement2.substr('OP_ELSE'.length);
            $$ = ($0 || '') + 'if (stack.pop().compare(0) === 0) {' + b1 + '} else {' + b2 + '};';
        %}
    | OP_NOTIF statement OP_ENDIF
        %{
            var b1 = $statement.substr('OP_NOTIF'.length);
            $$ = ($0 || '') + 'if (stack.pop().compare(0) === 0) {' + b1 + '};';
        %}
    | OP_NOP
        %{
            $$ = ($0 || '');
        %}
    | OP_0
        %{
            $$ = ($0 || '') + 'stack.push(0);';
        %}
    | OP_1
        %{
            $$ = ($0 || '') + 'stack.push(1);';
        %}
    | OP_1NEGATE
        %{
            $$ = ($0 || '') + 'stack.push(-1);';
        %}
    | OP_DATA
        %{
            var value = $1.substr('OP_'.length);
            $$ = ($0 || '') + 'stack.push(' + value + ');';
        %}
    | OP_DROP
        %{
            $$ = ($0 || '') + 'stack.pop();';
        %}
    | OP_DUP
        %{
            $$ = ($0 || '') + 'var data = stack.pop(); stack.push(data); stack.push(data);';
        %}
    | OP_SWAP
        %{
            $$ = ($0 || '') + 'var u = stack.pop(); var v = stack.pop(); stack.push(u); stack.push(v);';
        %}
    | OP_EQUAL
        %{
            $$ = ($0 || '') + 'if (stack.pop().equals(stack.pop())) { stack.push(1); } else { stack.push(0); }; ';
        %}
    | OP_1ADD
        %{
            $$ = ($0 || '') + 'stack.push(stack.pop().add(1));';
        %}
    | OP_1SUB
        %{
            $$ = ($0 || '') + 'stack.push(stack.pop().minus(1));';
        %}
    | OP_NEGATE
        %{
            $$ = ($0 || '') + 'stack.push(stack.pop().multiply(-1));';
        %}
    | OP_ABS
        %{
            $$ = ($0 || '') + 'stack.push(stack.pop().abs());';
        %}
    | OP_RIPEMD160
        %{
            $$ = ($0 || '') + 'stack.push(util.ripemd160(stack.pop()));';
        %}
    | OP_SHA1
        %{
            $$ = ($0 || '') + 'stack.push(util.sha1(stack.pop()));';
        %}
    | OP_SHA256
        %{
            $$ = ($0 || '') + 'stack.push(util.sha256(stack.pop()));';
        %}
    | OP_HASH160
        %{
            $$ = ($0 || '') + 'stack.push(util.ripemd160(util.sha256(stack.pop())));';
        %}
    | OP_HASH256
        %{
            $$ = ($0 || '') + 'stack.push(util.sha256(util.sha256(stack.pop())));';
        %}
    ;