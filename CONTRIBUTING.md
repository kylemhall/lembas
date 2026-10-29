# Contributing to Lembas

## Running things

Everything runs in Docker, see `make help`. `git config core.hooksPath .githooks` once per clone makes every commit
check the formatting.

## The coverage gate

`make coverage` (`script/coverage`) fails unless every statement, branch, condition and subroutine of `lib/` is
covered by the tests. A few rules keep that possible without annotating the code:

- **No code for impossible states.** No `//` default where the left side is always defined, no guards on values that
  are always there, no `else { die 'unreachable' }`. If no test can reach a branch, delete the branch.
- **Defaults are branches, not `//`.** Devel::Cover counts `$x // 'default'` in an assignment as three cases, one of
  them "both sides undefined", which can never happen with a constant. Write
  `$x = 'default' unless defined $x;` or a `defined $x ? $x : 'default'` ternary instead.
- **No defaults in signatures.** `sub f ($self, $force = 0)` compiles to a hidden condition; pass the value instead.
- **Every `eval` has a test that makes it fail.** Write `eval { ...; 1 } or do { ... }` (Perl::Critic insists).
- **Compound conditions only when every combination can happen.** Otherwise use two early returns.
- **Inject what a test must control:** a `has` attribute with a default (the user agent of `Lembas::Model::OIDC`,
  the generator of `Lembas::Model::Endings`, the clock). Its default is code too: one test must use it.
- **Bare `return` is an empty list.** In a hash constructor or a `map` that shifts every following pair: write
  `scalar f()` when a helper may return nothing.
- **Templates are not measured.** Keep the logic in the controllers and models.

`# uncoverable` is only for code that cannot be measured for Perl or system reasons (code that only runs in a forked
child, which leaves with `POSIX::_exit`). Use the exact Devel::Cover form with a `note:`. The gate prints how many
there are, and one that runs fails it.

## Style

- `Mojo::Base` with `-signatures`, perltidy's formatting (`.perltidyrc`), Perl::Critic at severity 3.
- Full, snake_case names. Short comments that say why, not what.
- `q{}` for an empty string, `undef` for a missing value.
- Terse POD: one short paragraph per method.
- Commit subjects in the imperative mood ("Add", not "Added"), with at most a short paragraph of body.
